import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/routing/batch_allocation.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/sync_progress.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/sync/sync_worker.dart';

import '../support/fake_connectivity.dart';
import '../support/fake_route_repository.dart';
import '../support/in_memory_database.dart';

class _FixedLocationService implements LocationService {
  @override
  Future<Coordinates> getCurrentPosition({
    required LocationPurpose purpose,
  }) async => const Coordinates(latitude: -7.215, longitude: -35.91);
}

class _FailingLocationService implements LocationService {
  @override
  Future<Coordinates> getCurrentPosition({
    required LocationPurpose purpose,
  }) async => throw StateError('location permission denied');
}

/// Drains a route's outbox the way the real worker does when the server
/// accepts every row: marks each unsynced row synced, but only while the
/// device is online and [delivers] holds. Logs each pass into [events].
class _DrainingSyncWorker implements SyncWorker {
  _DrainingSyncWorker(this._store, this._connectivity, this.events);

  final LocalWriteStore _store;
  final FakeConnectivity _connectivity;
  final List<String> events;

  /// False = the server is down: every row stays unsynced.
  bool delivers = true;

  final StreamController<RouteSyncStatus> _status =
      StreamController<RouteSyncStatus>.broadcast();

  /// Reports a finished pass with [pending] rows still owed, the way the
  /// real worker's status feed does.
  void reportPending(int pending) => _status.add(
    RouteSyncStatus(
      routeId: 'r1',
      state: RouteSyncState.idle,
      pending: pending,
      blocked: 0,
    ),
  );

  @override
  Future<void> syncRoute(String routeId) async {
    events.add('sync:$routeId');
    if (!_connectivity.isOnlineValue || !delivers) return;
    for (final row in await _store.unsyncedForRoute(routeId)) {
      await _store.markSynced(row.id);
    }
  }

  @override
  Future<void> syncAll() async {}

  @override
  Stream<RouteSyncStatus> statusFor(String routeId) => _status.stream;

  @override
  Future<void> unblock(String operationId) async {}

  @override
  Stream<SyncProgress> get progress => const Stream.empty();

  @override
  Future<void> dispose() => _status.close();
}

class _Harness {
  _Harness(MyDay day, {bool online = true, LocationService? location})
    : repository = FakeRouteRepository(day),
      connectivity = FakeConnectivity(isOnline: online) {
    final db = inMemoryDatabase();
    addTearDown(db.close);
    store = DriftLocalWriteStore(db);
    stopProgress = DriftStopProgressStore(db);
    worker = _DrainingSyncWorker(store, connectivity, events);
    container = ProviderContainer(
      overrides: [
        routeRepositoryProvider.overrideWithValue(repository),
        connectivityProvider.overrideWithValue(connectivity),
        locationServiceProvider.overrideWithValue(
          location ?? _FixedLocationService(),
        ),
        localWriteStoreProvider.overrideWithValue(store),
        stopProgressStoreProvider.overrideWithValue(stopProgress),
        syncWorkerProvider.overrideWithValue(worker),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(connectivity.dispose);
  }

  final FakeRouteRepository repository;
  final FakeConnectivity connectivity;
  final List<String> events = [];
  late final LocalWriteStore store;
  late final StopProgressStore stopProgress;
  late final _DrainingSyncWorker worker;
  late final ProviderContainer container;

  BatchAllocation get controller =>
      container.read(batchAllocationProvider.notifier);

  NextBatchState get state => container.read(batchAllocationProvider);

  /// Mounts the controller the way the route screen does and lets the
  /// first `GET /routes/me` and any automatic pull settle.
  Future<void> mount() async {
    container.listen(batchAllocationProvider, (_, _) {});
    await container.read(myDayProvider.future);
    await pumpEventQueue();
  }

  Future<void> markDoneLocally(String routeStopId) async {
    await stopProgress.upsertInProgress(routeStopId, 'exec-$routeStopId');
    await stopProgress.markDone(routeStopId);
  }
}

/// Batch 1 with two stops; the second one is the last open one.
RouteSummary _batchOne({String status = 'IN_PROGRESS'}) => routeWith(
  status: status,
  stops: [
    stopWith(id: 's1', status: 'DONE'),
    stopWith(id: 's2', orderIndex: 2),
  ],
);

RouteSummary _batchTwo() => routeWith(
  currentBatch: 2,
  stops: [
    stopWith(id: 's1', status: 'DONE'),
    stopWith(id: 's2', orderIndex: 2, status: 'DONE'),
    stopWith(id: 's3', orderIndex: 3, batchNumber: 2),
  ],
);

/// The server hands out batch 2 and `GET /routes/me` shows it from then on.
AllocationResult Function() _handsOutBatchTwo(_Harness h) => () {
  h.events.add('nextBatch');
  h.repository.day = myDayWith(_batchTwo());
  return AllocationResult(route: _batchTwo(), poolEmpty: false);
};

void main() {
  group('start', () {
    test('allocates from the current position and reloads the day', () async {
      final h = _Harness(myDayWith(null));
      await h.mount();
      h.repository.allocate = () {
        h.repository.day = myDayWith(_batchOne());
        return AllocationResult(route: _batchOne(), poolEmpty: false);
      };

      final outcome = await h.controller.start();

      expect(outcome, AllocationOutcome.allocated);
      expect(h.repository.allocationCalls, ['start']);
      expect(h.repository.lastPosition, (lat: -7.215, lng: -35.91));
      expect((await h.container.read(myDayProvider.future)).route, isNotNull);
    });

    test('offline: refuses without calling the server', () async {
      final h = _Harness(myDayWith(null), online: false);
      await h.mount();

      expect(await h.controller.start(), AllocationOutcome.offline);
      expect(h.repository.allocationCalls, isEmpty);
    });

    test('no location fix: refuses without calling the server', () async {
      final h = _Harness(myDayWith(null), location: _FailingLocationService());
      await h.mount();

      expect(await h.controller.start(), AllocationOutcome.locationUnavailable);
      expect(h.repository.allocationCalls, isEmpty);
    });

    test('maps every server refusal to its outcome', () async {
      final cases = <Exception, AllocationOutcome>{
        const NotAServiceDayException(): AllocationOutcome.notAServiceDay,
        const WorkdayOverException(): AllocationOutcome.workdayOver,
        const OutsideCampusException(): AllocationOutcome.outsideCampus,
        // A retry after a lost "pool empty" answer (B3 carry-over).
        const RouteDoneException(): AllocationOutcome.poolEmpty,
        const OfflineException('/routes/start'): AllocationOutcome.offline,
        // The consent gate's plain 403: a failure, never a crash.
        DioException(
          requestOptions: RequestOptions(path: '/routes/start'),
          response: Response<Object>(
            requestOptions: RequestOptions(path: '/routes/start'),
            statusCode: 403,
          ),
        ): AllocationOutcome.failed,
      };
      final h = _Harness(myDayWith(null));
      await h.mount();
      for (final MapEntry(key: error, value: expected) in cases.entries) {
        h.repository.allocate = () => throw error;
        expect(await h.controller.start(), expected, reason: '$error');
      }
    });

    test('an empty pool is its own outcome', () async {
      final h = _Harness(myDayWith(null));
      await h.mount();
      final done = _batchOne(status: 'DONE');
      h.repository.allocate = () =>
          AllocationResult(route: done, poolEmpty: true);

      expect(await h.controller.start(), AllocationOutcome.poolEmpty);
    });
  });

  group('next batch', () {
    test(
      'once the last open stop is done here, drains the outbox and then '
      'pulls the next batch',
      () async {
        final h = _Harness(myDayWith(_batchOne()));
        await h.markDoneLocally('s2');
        await h.store.enqueue(
          id: 'checkout-s2',
          kind: PendingOpKind.checkOut,
          payload: const {'route_stop_id': 's2'},
          routeId: 'r1',
        );
        h.repository.allocate = _handsOutBatchTwo(h);

        await h.mount();

        expect(h.events, ['sync:r1', 'nextBatch']);
        expect(h.repository.lastPosition, (lat: -7.215, lng: -35.91));
        expect(
          (await h.container.read(myDayProvider.future)).route!.currentBatch,
          2,
        );
        expect(h.state, NextBatchState.idle);
      },
    );

    test('does nothing while the batch still has an open stop', () async {
      final h = _Harness(myDayWith(_batchOne()));

      await h.mount();

      expect(h.repository.allocationCalls, isEmpty);
    });

    test('does nothing for a paused route', () async {
      final h = _Harness(myDayWith(_batchOne(status: 'PAUSED')));
      await h.markDoneLocally('s2');

      await h.mount();

      expect(h.repository.allocationCalls, isEmpty);
    });

    test(
      'offline: waits for the network, then pulls when it comes back',
      () async {
        final h = _Harness(myDayWith(_batchOne()), online: false);
        await h.markDoneLocally('s2');
        h.repository.allocate = _handsOutBatchTwo(h);

        await h.mount();
        expect(h.state, NextBatchState.waitingForNetwork);
        expect(h.repository.allocationCalls, isEmpty);

        h.connectivity.goOnline();
        await pumpEventQueue();

        expect(h.repository.allocationCalls, ['nextBatch:r1']);
        expect(h.state, NextBatchState.idle);
      },
    );

    test(
      'a check-out the server has not received yet keeps it waiting',
      () async {
        final h = _Harness(myDayWith(_batchOne()));
        await h.markDoneLocally('s2');
        await h.store.enqueue(
          id: 'checkout-s2',
          kind: PendingOpKind.checkOut,
          payload: const {'route_stop_id': 's2'},
          routeId: 'r1',
        );
        h.worker.delivers = false;

        await h.mount();

        expect(h.repository.allocationCalls, isEmpty);
        expect(h.state, NextBatchState.waitingForNetwork);
      },
    );

    test(
      'a blocked write (a late STOP_RELEASED, parked for the appeal) and the '
      'rows held behind it do not stall the pull',
      () async {
        final h = _Harness(myDayWith(_batchOne()));
        await h.markDoneLocally('s2');
        await h.store.enqueue(
          id: 'checkout-s2',
          kind: PendingOpKind.checkOut,
          payload: const {'route_stop_id': 's2'},
          routeId: 'r1',
        );
        await h.store.markBlocked('checkout-s2', 'HTTP 409 STOP_RELEASED');
        // An impediment on the same stop, held behind it for good.
        await h.store.enqueue(
          id: 'impediment-s2',
          kind: PendingOpKind.impediment,
          payload: const {'route_stop_id': 's2'},
          routeId: 'r1',
        );
        h.worker.delivers = false;
        h.repository.allocate = _handsOutBatchTwo(h);

        await h.mount();

        expect(h.repository.allocationCalls, ['nextBatch:r1']);
        expect(h.state, NextBatchState.idle);
      },
    );

    test(
      'a photo held for its stamp is not an undelivered write: it does not '
      'stall the pull',
      () async {
        final h = _Harness(myDayWith(_batchOne()));
        await h.markDoneLocally('s2');
        await h.store.enqueue(
          id: 'photo-s1',
          kind: PendingOpKind.evidencePhoto,
          payload: const {'execution_id': 'exec-s1'},
          routeId: 'r1',
          initialState: PendingOpState.held,
        );
        h.worker.delivers = false;
        h.repository.allocate = _handsOutBatchTwo(h);

        await h.mount();

        expect(h.repository.allocationCalls, ['nextBatch:r1']);
        expect(h.state, NextBatchState.idle);
      },
    );

    test(
      'waiting on an undelivered write, it pulls as soon as the route '
      'becomes fully synced — no connectivity event needed',
      () async {
        final h = _Harness(myDayWith(_batchOne()));
        await h.markDoneLocally('s2');
        await h.store.enqueue(
          id: 'checkout-s2',
          kind: PendingOpKind.checkOut,
          payload: const {'route_stop_id': 's2'},
          routeId: 'r1',
        );
        h.worker.delivers = false;
        h.repository.allocate = _handsOutBatchTwo(h);
        await h.mount();
        expect(h.state, NextBatchState.waitingForNetwork);

        // Data came back: a later pass delivers the check-out.
        h.worker.reportPending(1);
        await pumpEventQueue();
        expect(h.repository.allocationCalls, isEmpty);
        await h.store.markSynced('checkout-s2');
        h.worker.reportPending(0);
        await pumpEventQueue();

        expect(h.repository.allocationCalls, ['nextBatch:r1']);
        expect(h.state, NextBatchState.idle);
      },
    );

    test(
      'waiting with the interface up but no data, it retries every 30 s',
      () {
        fakeAsync((async) {
          final h = _Harness(myDayWith(_batchOne()));
          unawaited(h.markDoneLocally('s2'));
          // The server answers nothing useful: the request never connects.
          h.repository.allocate = () =>
              throw const OfflineException('/routes/r1/next-batch');
          async.flushMicrotasks();
          h.container.listen(batchAllocationProvider, (_, _) {});
          async.flushMicrotasks();
          expect(h.state, NextBatchState.waitingForNetwork);
          expect(h.repository.allocationCalls, ['nextBatch:r1']);

          h.repository.allocate = _handsOutBatchTwo(h);
          async.elapse(const Duration(seconds: 29));
          expect(h.repository.allocationCalls, hasLength(1));
          async.elapse(const Duration(seconds: 1));

          expect(h.repository.allocationCalls, hasLength(2));
          expect(h.state, NextBatchState.idle);
          async.elapse(nextBatchRetryInterval * 3);
          expect(h.repository.allocationCalls, hasLength(2));
        });
      },
    );

    test(
      'a pull that fails unexpectedly does not stay "pulling" and reaches no '
      'zone',
      () async {
        final h = _Harness(myDayWith(_batchOne()));
        await h.markDoneLocally('s2');
        h.repository.allocate = () => throw StateError('store is gone');

        await h.mount();

        expect(h.state, NextBatchState.idle);
      },
    );

    test('a day that moves on (route paused) stops the waiting', () async {
      final h = _Harness(myDayWith(_batchOne()), online: false);
      await h.markDoneLocally('s2');
      await h.mount();
      expect(h.state, NextBatchState.waitingForNetwork);

      h.repository.day = myDayWith(_batchOne(status: 'PAUSED'));
      h.container.invalidate(myDayProvider);
      await h.container.read(myDayProvider.future);
      await pumpEventQueue();
      h.connectivity.goOnline();
      await pumpEventQueue();

      expect(h.state, NextBatchState.idle);
      expect(h.repository.allocationCalls, isEmpty);
    });

    test(
      'the same batch handed back unchanged does not reload the day '
      '(no pull loop)',
      () async {
        final h = _Harness(myDayWith(_batchOne()));
        await h.markDoneLocally('s2');

        await h.mount();

        expect(h.repository.allocationCalls, ['nextBatch:r1']);
        expect(h.repository.fetchCount, 1);
      },
    );

    test(
      'ROUTE_DONE after a lost empty-pool answer reloads the finished day',
      () async {
        final h = _Harness(myDayWith(_batchOne()));
        await h.markDoneLocally('s2');
        h.repository.allocate = () {
          h.repository.day = myDayWith(_batchOne(status: 'DONE'));
          throw const RouteDoneException();
        };

        await h.mount();

        expect(
          (await h.container.read(myDayProvider.future)).route!.status,
          'DONE',
        );
        expect(h.repository.allocationCalls, ['nextBatch:r1']);
      },
    );
  });
}
