import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/execution/execution_providers.dart'
    show localWriteStoreProvider, stopProgressStoreProvider;
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/blocked_scope.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_status.dart';

/// How a request for a batch ended, for the screen to word.
enum AllocationOutcome {
  allocated,

  /// Nothing to hand out right now (the route is DONE until points go back
  /// to the pool — "Verificar de novo" asks again). Also what `ROUTE_DONE`
  /// (a route of a past day) is shown as.
  poolEmpty,
  notAServiceDay,
  workdayOver,
  outsideCampus,
  offline,
  locationUnavailable,

  /// Any other refusal: a 403, a 404, a 5xx. A 403 `CONSENT_REQUIRED` or
  /// `WORKER_NOT_APPROVED` has already flagged the session by the time this
  /// comes back (the interceptors of `buildSessionDio`), so the router moves
  /// to the consent or waiting screen; any other one is just a failure.
  failed,
}

/// The automatic next-batch pull, as the route screen shows it.
enum NextBatchState {
  idle,
  pulling,

  /// The batch is finished here but the server could not be reached (or does
  /// not have the last check-out yet); retried when the network comes back,
  /// when the outbox drains and every [nextBatchRetryInterval].
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

/// How often a finished batch that is waiting for the server is retried
/// when nothing announces the network is back (the interface stayed up while
/// data was down, or the server answered 5xx).
const nextBatchRetryInterval = Duration(seconds: 30);

class BatchAllocation extends Notifier<NextBatchState> {
  /// The route whose finished batch is waiting for the network.
  RouteSummary? _waiting;

  /// While waiting: the periodic retry and the route's sync-status feed.
  Timer? _retryTimer;
  StreamSubscription<RouteSyncStatus>? _syncStatus;
  int? _lastPending;

  @override
  NextBatchState build() {
    ref.listen<AsyncValue<MyDay>>(myDayProvider, (_, next) {
      // Only a settled day: a reload in flight still carries the old route
      // (as refreshing data), and pulling for it would ask twice.
      if (next.isLoading) return;
      if (next case AsyncData(value: MyDay(:final route?))) {
        // Deferred — this can fire while the notifier is still building.
        scheduleMicrotask(() => _guarded(_pullIfBatchClosed(route)));
      }
    }, fireImmediately: true);
    final regained = ref
        .watch(connectivityProvider)
        .onOnlineChanged
        .listen((_) => _retryWhileWaiting());
    ref.onDispose(() {
      unawaited(regained.cancel());
      _stopRetrying();
    });
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

  /// Re-checks today's batch and pulls the next one if it is finished — what
  /// "Sincronizar agora" does once the outbox drained.
  Future<void> retry() async {
    if (!ref.mounted) return;
    final route = ref.read(myDayProvider).value?.route ?? _waiting;
    if (route == null) return;
    await _pullIfBatchClosed(route);
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

  void _retryWhileWaiting() {
    if (state != NextBatchState.waitingForNetwork) return;
    _guarded(retry());
  }

  Future<void> _pull(RouteSummary route) async {
    _stopRetrying();
    state = NextBatchState.pulling;
    var next = NextBatchState.idle;
    try {
      next = await _pullOnce(route);
    } finally {
      // Whatever happens, never stay "pulling": that would block every
      // later trigger.
      if (ref.mounted) {
        state = next;
        if (next == NextBatchState.waitingForNetwork) _retryLater(route);
      }
    }
  }

  /// One attempt; returns the state it leaves the pull in.
  Future<NextBatchState> _pullOnce(RouteSummary route) async {
    if (await _hasUndeliveredWrites(route.id)) {
      return NextBatchState.waitingForNetwork;
    }
    final repository = ref.read(routeRepositoryProvider);
    final (:outcome, :result) = await _allocate(
      (position, now) => repository.nextBatch(
        route.id,
        lat: position.latitude,
        lng: position.longitude,
        capturedAt: now,
      ),
    );
    if (outcome == AllocationOutcome.offline) {
      return NextBatchState.waitingForNetwork;
    }
    if (ref.mounted && _changesTheDay(route, outcome, result)) {
      ref.invalidate(myDayProvider);
    }
    return NextBatchState.idle;
  }

  /// Drains the route's outbox first: the server only hands out the next
  /// batch once it has the last check-out, and asked earlier it would answer
  /// with the current batch, unchanged. Rows held behind a blocked one (a
  /// late STOP_RELEASED parked for the appeal flow, say) do not count: no
  /// network will deliver them, and they must not stall the day.
  Future<bool> _hasUndeliveredWrites(String routeId) async {
    await ref.read(syncWorkerProvider).syncRoute(routeId);
    if (!ref.mounted) return true;
    final store = ref.read(localWriteStoreProvider);
    final scope = BlockedScope(await store.blockedForRoute(routeId));
    final unsynced = await store.unsyncedForRoute(routeId);
    return scope.deliverable(unsynced).isNotEmpty;
  }

  /// Waiting: retry when the route's outbox drains, every
  /// [nextBatchRetryInterval], and when the network comes back (see build).
  void _retryLater(RouteSummary route) {
    _waiting = route;
    _retryTimer = Timer.periodic(
      nextBatchRetryInterval,
      (_) => _retryWhileWaiting(),
    );
    _lastPending = null;
    _syncStatus = ref
        .read(syncWorkerProvider)
        .statusFor(route.id)
        .listen(_onSyncStatus);
  }

  /// Retries once the route becomes fully synced — only on that transition,
  /// so a pass that changes nothing never re-triggers a pull.
  void _onSyncStatus(RouteSyncStatus status) {
    final before = _lastPending;
    _lastPending = status.pending;
    if (status.pending == 0 && before != null && before > 0) {
      _retryWhileWaiting();
    }
  }

  void _stopRetrying() {
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(_syncStatus?.cancel());
    _syncStatus = null;
    _waiting = null;
  }

  /// The day moved on (a new batch, the route paused or done): nothing is
  /// waiting for the network any more.
  void _stopWaiting() {
    if (!ref.mounted || state != NextBatchState.waitingForNetwork) return;
    _stopRetrying();
    state = NextBatchState.idle;
  }

  /// A background pull has no caller to report to: a failure (a store
  /// error, say) is logged and the next trigger tries again — it must never
  /// surface as an unhandled zone error.
  void _guarded(Future<void> pull) {
    unawaited(
      pull.catchError((Object error, StackTrace stack) {
        developer.log(
          jsonEncode({'event': 'next_batch_pull_failed', 'error': '$error'}),
          name: 'batch_allocation',
          stackTrace: stack,
        );
      }),
    );
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
