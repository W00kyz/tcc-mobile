import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/execution/execution_providers.dart'
    show localWriteStoreProvider, stopProgressStoreProvider;
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/sync_providers.dart';

/// How a request for a batch ended, for the screen to word.
enum AllocationOutcome {
  allocated,

  /// Nothing left to hand out today — also what `ROUTE_DONE` means: a retry
  /// after the empty-pool answer was lost.
  poolEmpty,
  notAServiceDay,
  workdayOver,
  outsideCampus,
  offline,
  locationUnavailable,

  /// Any other refusal: a 403 (privacy notice owed, worker not approved — the
  /// app's gates take it from there), a 404, a 5xx.
  failed,
}

/// The automatic next-batch pull, as the route screen shows it.
enum NextBatchState {
  idle,
  pulling,

  /// The batch is finished here but the server could not be reached (or does
  /// not have the last check-out yet); retried when the network comes back.
  waitingForNetwork,
}

/// "Iniciar rota" and the automatic next batch (spec §6.4): the server hands
/// out batches of the nearest free points, measured from where the worker is.
/// Watching [myDayProvider], it pulls the next batch by itself as soon as the
/// current one has no open stop left on this device.
///
///     final allocation = ref.read(batchAllocationProvider.notifier);
///     final outcome = await allocation.start();
final batchAllocationProvider =
    NotifierProvider<BatchAllocation, NextBatchState>(BatchAllocation.new);

/// What still keeps a route's writes from the server.
enum _OutboxHold {
  none,

  /// A row needs the worker's "Tentar de novo" (it halts the route queue).
  blocked,

  /// Rows not delivered yet: offline, or the server is failing.
  unsent,
}

class BatchAllocation extends Notifier<NextBatchState> {
  /// The route whose finished batch is waiting for the network.
  RouteSummary? _waiting;

  @override
  NextBatchState build() {
    ref.listen<AsyncValue<MyDay>>(myDayProvider, (_, next) {
      // Only a settled day: a reload in flight still carries the old route
      // (as refreshing data), and pulling for it would ask twice.
      if (next.isLoading) return;
      if (next case AsyncData(value: MyDay(:final route?))) {
        // Deferred — this can fire while the notifier is still building.
        scheduleMicrotask(() => _pullIfBatchClosed(route));
      }
    }, fireImmediately: true);
    final regained = ref
        .watch(connectivityProvider)
        .onOnlineChanged
        .listen((_) => _retryAfterReconnect());
    ref.onDispose(regained.cancel);
    return NextBatchState.idle;
  }

  /// "Iniciar rota": starts today's route, or resumes a paused one, with a
  /// batch measured from the current position. Reloads the day whenever the
  /// server answered.
  Future<AllocationOutcome> start() async {
    final repository = ref.read(routeRepositoryProvider);
    final (:outcome, result: _) = await _allocate(
      (position, now) => repository.startOrResume(
        lat: position.latitude,
        lng: position.longitude,
        capturedAt: now,
      ),
    );
    if (_serverAnswered(outcome) && ref.mounted) ref.invalidate(myDayProvider);
    return outcome;
  }

  Future<void> _pullIfBatchClosed(RouteSummary route) async {
    if (!ref.mounted || state == NextBatchState.pulling) return;
    if (route.status != 'IN_PROGRESS') return _stopWaiting();
    final progress = await ref
        .read(stopProgressStoreProvider)
        .allForRoute(route.stops.map((stop) => stop.id));
    final doneLocally = {
      for (final entry in progress)
        if (entry.status == StopLocalStatus.done) entry.routeStopId,
    };
    if (!route.currentBatchClosed(doneLocally: doneLocally)) {
      return _stopWaiting();
    }
    // Re-checked: another trigger may have started a pull meanwhile.
    if (!ref.mounted || state == NextBatchState.pulling) return;
    await _pull(route);
  }

  void _retryAfterReconnect() {
    final route = _waiting;
    if (route == null || state != NextBatchState.waitingForNetwork) return;
    unawaited(_pull(route));
  }

  Future<void> _pull(RouteSummary route) async {
    state = NextBatchState.pulling;
    _waiting = null;
    final hold = await _outboxHold(route.id);
    if (!ref.mounted) return;
    if (hold == _OutboxHold.blocked) {
      // The blocked-sync banner already asks for action; "connect" would lie.
      state = NextBatchState.idle;
      return;
    }
    if (hold == _OutboxHold.unsent) return _waitForNetwork(route);
    final repository = ref.read(routeRepositoryProvider);
    final (:outcome, :result) = await _allocate(
      (position, now) => repository.nextBatch(
        route.id,
        lat: position.latitude,
        lng: position.longitude,
        capturedAt: now,
      ),
    );
    if (!ref.mounted) return;
    if (outcome == AllocationOutcome.offline) return _waitForNetwork(route);
    state = NextBatchState.idle;
    if (_changesTheDay(route, outcome, result)) ref.invalidate(myDayProvider);
  }

  /// Drains the route's outbox first: the server only hands out the next
  /// batch once it has the last check-out, and asked earlier it would answer
  /// with the current batch, unchanged.
  Future<_OutboxHold> _outboxHold(String routeId) async {
    await ref.read(syncWorkerProvider).syncRoute(routeId);
    if (!ref.mounted) return _OutboxHold.unsent;
    final store = ref.read(localWriteStoreProvider);
    if ((await store.blockedForRoute(routeId)).isNotEmpty) {
      return _OutboxHold.blocked;
    }
    final unsynced = await store.unsyncedForRoute(routeId);
    return unsynced.isEmpty ? _OutboxHold.none : _OutboxHold.unsent;
  }

  /// The day moved on (a new batch, the route paused or done): nothing is
  /// waiting for the network any more.
  void _stopWaiting() {
    if (!ref.mounted || state != NextBatchState.waitingForNetwork) return;
    _waiting = null;
    state = NextBatchState.idle;
  }

  void _waitForNetwork(RouteSummary route) {
    if (!ref.mounted) return;
    _waiting = route;
    state = NextBatchState.waitingForNetwork;
  }

  /// Reload the day only on an answer that moves it on. An unchanged batch
  /// (or a refusal) would reload into the same finished batch and pull again
  /// — a request loop.
  bool _changesTheDay(
    RouteSummary asked,
    AllocationOutcome outcome,
    AllocationResult? result,
  ) => switch (outcome) {
    AllocationOutcome.poolEmpty => true,
    AllocationOutcome.allocated =>
      result!.route.currentBatch != asked.currentBatch ||
          result.route.status != asked.status,
    _ => false,
  };

  static bool _serverAnswered(AllocationOutcome outcome) => switch (outcome) {
    AllocationOutcome.offline ||
    AllocationOutcome.locationUnavailable ||
    AllocationOutcome.failed => false,
    _ => true,
  };

  Future<({AllocationOutcome outcome, AllocationResult? result})> _allocate(
    Future<AllocationResult> Function(Coordinates position, DateTime now)
    request,
  ) async {
    if (!await ref.read(connectivityProvider).isOnline) {
      return (outcome: AllocationOutcome.offline, result: null);
    }
    final position = await _currentPosition();
    if (position == null) {
      return (outcome: AllocationOutcome.locationUnavailable, result: null);
    }
    try {
      final result = await request(position, DateTime.now());
      final outcome = result.poolEmpty
          ? AllocationOutcome.poolEmpty
          : AllocationOutcome.allocated;
      return (outcome: outcome, result: result);
    } on Exception catch (error) {
      final outcome = _outcomeOf(error);
      if (outcome == null) rethrow;
      return (outcome: outcome, result: null);
    }
  }

  static AllocationOutcome? _outcomeOf(Exception error) => switch (error) {
    NotAServiceDayException() => AllocationOutcome.notAServiceDay,
    WorkdayOverException() => AllocationOutcome.workdayOver,
    OutsideCampusException() => AllocationOutcome.outsideCampus,
    RouteDoneException() => AllocationOutcome.poolEmpty,
    OfflineException() => AllocationOutcome.offline,
    DioException() => AllocationOutcome.failed,
    _ => null,
  };

  /// The same single high-accuracy fix a check-in takes; null when there is
  /// none (permission denied, no signal, timeout).
  Future<Coordinates?> _currentPosition() async {
    try {
      return await ref
          .read(locationServiceProvider)
          .getCurrentPosition(purpose: LocationPurpose.checkin);
      // Deliberately broad: GeolocatorLocationService fails with a StateError
      // (permission denied), a platform exception or a timeout — all of them
      // mean "no position" here.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }
}
