import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/evidence_capture.dart';
import 'package:route_monitor/execution/execution_repository.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/day_log_store.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/sync/sync_progress.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/sync/sync_worker.dart';

import '../support/fake_day_log_store.dart';
import '../support/in_memory_database.dart';

/// In-memory stand-in for [DriftLocalWriteStore] — real Drift behavior (and
/// the `insertOrIgnore` semantics reproduced below) is already proven by
/// local_write_store_test.dart. Just enough here to inspect the outbox rows
/// ExecutionRepository writes.
class _FakeLocalWriteStore implements LocalWriteStore {
  @override
  Future<bool> claim(String id, {required int now, required int leaseUntil}) =>
      throw UnimplementedError();

  @override
  Future<void> releaseClaim(PendingOperationRow row) =>
      throw UnimplementedError();

  @override
  Stream<Set<String>> watchImpededStopIds(String routeId) =>
      throw UnimplementedError();

  @override
  Future<bool> deletePendingPhoto(String operationId) =>
      throw UnimplementedError();

  final Map<String, PendingOperationRow> _rows = {};

  @override
  Future<bool> enqueue({
    required String id,
    required PendingOpKind kind,
    required Map<String, dynamic> payload,
    required String routeId,
    PendingOpState initialState = PendingOpState.pending,
  }) async {
    // insertOrIgnore: a re-enqueue with an id already present is a no-op
    // (Etapa 5 behavior — the same-tap room-picker retry reuses the key).
    if (_rows.containsKey(id)) return false;
    _rows[id] = PendingOperationRow(
      id: id,
      kind: kind,
      routeId: routeId,
      payload: payload,
      createdAt: _rows.length,
      state: initialState,
      lastError: null,
      attempts: 0,
      nextAttemptAt: null,
    );
    return true;
  }

  @override
  Future<List<PendingOperationRow>> unsyncedForRoute(String routeId) async =>
      _rows.values
          .where(
            (row) =>
                row.routeId == routeId && row.state != PendingOpState.synced,
          )
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<void> markSynced(String id) => throw UnimplementedError();

  @override
  Future<void> markFailed(String id, String error) =>
      throw UnimplementedError();

  @override
  Future<void> markStopReleased(
    String id, {
    required String routeStopId,
    required String error,
  }) => throw UnimplementedError();

  @override
  Future<void> markBlocked(String id, String error) =>
      throw UnimplementedError();

  @override
  Future<void> markRetryScheduled(
    String id, {
    required int attempts,
    required int nextAttemptAt,
  }) => throw UnimplementedError();

  @override
  Future<List<PendingOperationRow>> blockedForRoute(String routeId) =>
      throw UnimplementedError();

  @override
  Future<List<PendingOperationRow>> dueForRoute(
    String routeId, {
    required int now,
  }) => throw UnimplementedError();

  @override
  Future<List<String>> routeIdsWithWork() => throw UnimplementedError();

  @override
  Future<void> resetToPending(String id) => throw UnimplementedError();

  @override
  Future<int> releaseHeldPhotos(String executionId) =>
      throw UnimplementedError();

  @override
  Future<int> discardHeldPhotos(String executionId) =>
      throw UnimplementedError();

  @override
  Future<int> localPhotoCountFor(String executionId) =>
      throw UnimplementedError();
}

/// In-memory stand-in for [DriftStopProgressStore] — real Drift behavior is
/// proven by stop_progress_store_test.dart; this records calls so the
/// optimistic-UI wiring (spec Ruling 5) can be asserted directly.
class _FakeStopProgressStore implements StopProgressStore {
  final List<String> calls = [];
  final Map<String, StopProgressEntry> _rows = {};

  @override
  Future<void> upsertInProgress(String routeStopId, String executionId) async {
    calls.add('inProgress:$routeStopId:$executionId');
    _rows[routeStopId] = StopProgressEntry(
      updatedAt: DateTime(2026),
      routeStopId: routeStopId,
      executionId: executionId,
      status: StopLocalStatus.inProgress,
    );
  }

  @override
  Future<void> markDone(String routeStopId) async {
    calls.add('done:$routeStopId');
    final existing = _rows[routeStopId];
    if (existing == null) return;
    _rows[routeStopId] = StopProgressEntry(
      updatedAt: DateTime(2026),
      routeStopId: existing.routeStopId,
      executionId: existing.executionId,
      status: StopLocalStatus.done,
    );
  }

  @override
  Future<void> markStamped(String routeStopId, {String? observation}) =>
      throw UnimplementedError();

  @override
  Future<StopProgressEntry?> progressFor(String routeStopId) async =>
      _rows[routeStopId];

  @override
  Future<List<StopProgressEntry>> allForRoute(
    Iterable<String> routeStopIds,
  ) async => [
    for (final id in routeStopIds) ?_rows[id],
  ];
}

/// Delegates `recordStopDone` to the real store, then fails — the write
/// lands inside the transaction and must be rolled back with it.
class _WritesThenThrowsDayLog implements DayLogStore {
  _WritesThenThrowsDayLog(this._real);

  final DayLogStore _real;

  @override
  Future<void> recordStopDone(DateTime day) async {
    await _real.recordStopDone(day);
    throw Exception('fails after the day-log write');
  }

  @override
  Future<void> recordDayOpened(DateTime day, {required bool serviceDay}) =>
      throw UnimplementedError();

  @override
  Future<void> recordCardCompleted(DateTime day, {required bool clean}) =>
      throw UnimplementedError();

  @override
  Future<List<DayLogEntry>> all() => throw UnimplementedError();
}

/// Records every `syncRoute` kick and, for each, hands back a future that
/// never completes — so a test can prove the repository fires the kick
/// fire-and-forget and returns without awaiting the drain.
class _FakeSyncWorker implements SyncWorker {
  final List<String> syncedRoutes = [];

  @override
  Future<void> syncRoute(String routeId) {
    syncedRoutes.add(routeId);
    return Completer<void>().future;
  }

  @override
  Future<void> syncAll() => throw UnimplementedError();

  @override
  Stream<RouteSyncStatus> statusFor(String routeId) =>
      throw UnimplementedError();

  @override
  Future<void> unblock(String operationId) => throw UnimplementedError();

  @override
  Stream<SyncProgress> get progress => const Stream.empty();

  @override
  Future<void> dispose() => throw UnimplementedError();
}

void main() {
  late _FakeLocalWriteStore store;
  late _FakeStopProgressStore stopProgress;
  late _FakeSyncWorker syncWorker;
  late RecordingDayLogStore dayLog;
  late ExecutionRepository repository;

  setUp(() {
    store = _FakeLocalWriteStore();
    stopProgress = _FakeStopProgressStore();
    syncWorker = _FakeSyncWorker();
    dayLog = RecordingDayLogStore();
    final db = inMemoryDatabase();
    addTearDown(db.close);
    repository = ExecutionRepository(
      store,
      stopProgress,
      syncWorker,
      database: db,
      dayLog: dayLog,
    );
  });

  test('checkIn enqueues one pending row, marks the stop IN_PROGRESS and '
      'kicks the sync worker once', () async {
    final executionId = await repository.checkIn(
      routeId: 'route-A',
      routeStopId: 'stop-1',
      qrPayload: 'v1.floor.1.sig',
      latitude: -7.2,
      longitude: -35.9,
      idempotencyKey: 'K',
    );

    final rows = await store.unsyncedForRoute('route-A');
    expect(rows, hasLength(1));
    expect(rows.single.state, PendingOpState.pending);
    expect(rows.single.kind, PendingOpKind.checkIn);
    expect(rows.single.payload['execution_id'], executionId);
    expect(rows.single.payload['route_stop_id'], 'stop-1');
    expect(rows.single.payload['idempotency_key'], 'K');
    expect(rows.single.payload['scanned_at'], isA<String>());
    // A parseable ISO-8601 instant, never a raw DateTime.
    expect(
      () => DateTime.parse(rows.single.payload['scanned_at'] as String),
      returnsNormally,
    );

    expect(stopProgress.calls, ['inProgress:stop-1:$executionId']);
    expect(
      (await stopProgress.progressFor('stop-1'))?.status,
      StopLocalStatus.inProgress,
    );
    expect(syncWorker.syncedRoutes, ['route-A']);
  });

  test('checkIn returns immediately even though the sync kick never '
      'completes (fire-and-forget)', () async {
    final result = await repository
        .checkIn(
          routeId: 'route-A',
          routeStopId: 'stop-1',
          qrPayload: 'q',
        )
        .timeout(const Duration(seconds: 1));

    expect(result, isNotEmpty);
    expect(syncWorker.syncedRoutes, ['route-A']);
  });

  test('checkIn with a null routeStopId enqueues route_stop_id: null and '
      'records no stop-progress row', () async {
    await repository.checkIn(
      routeId: 'route-A',
      qrPayload: 'q',
    );

    final rows = await store.unsyncedForRoute('route-A');
    expect(rows.single.payload.containsKey('route_stop_id'), isTrue);
    expect(rows.single.payload['route_stop_id'], isNull);
    expect(stopProgress.calls, isEmpty);
    expect(syncWorker.syncedRoutes, ['route-A']);
  });

  test('checkIn generates a fresh executionId per call', () async {
    final first = await repository.checkIn(routeId: 'route-A', qrPayload: 'q1');
    final second = await repository.checkIn(
      routeId: 'route-A',
      qrPayload: 'q2',
    );

    expect(first, isNot(second));
  });

  test('checkIn reuses a caller-supplied idempotencyKey, so a same-tap '
      'retry enqueues no second row', () async {
    await repository.checkIn(
      routeId: 'route-A',
      qrPayload: 'q',
      idempotencyKey: 'K',
    );
    await repository.checkIn(
      routeId: 'route-A',
      routeStopId: 'stop-1',
      qrPayload: 'q',
      idempotencyKey: 'K',
    );

    final rows = await store.unsyncedForRoute('route-A');
    expect(rows, hasLength(1));
    expect(rows.single.id, 'K');
    expect(syncWorker.syncedRoutes, ['route-A', 'route-A']);
  });

  test('checkOut enqueues one pending row, marks the stop DONE and kicks '
      'the sync worker once', () async {
    await stopProgress.upsertInProgress('stop-1', 'exec-1');
    stopProgress.calls.clear();

    await repository.checkOut(
      routeId: 'route-A',
      routeStopId: 'stop-1',
      qrPayload: 'v1.floor.1.sig',
      latitude: -7.2,
      longitude: -35.9,
    );

    final rows = await store.unsyncedForRoute('route-A');
    expect(rows, hasLength(1));
    expect(rows.single.state, PendingOpState.pending);
    expect(rows.single.kind, PendingOpKind.checkOut);
    expect(rows.single.payload['execution_id'], isA<String>());
    expect(rows.single.payload['route_stop_id'], 'stop-1');
    expect(rows.single.payload['checkout_idempotency_key'], isA<String>());

    expect(stopProgress.calls, ['done:stop-1']);
    expect(
      (await stopProgress.progressFor('stop-1'))?.status,
      StopLocalStatus.done,
    );
    expect(dayLog.calls, [startsWith('stopDone:')]);
    expect(syncWorker.syncedRoutes, ['route-A']);
  });

  group('against the real database', () {
    late AppDatabase db;
    late DriftLocalWriteStore realStore;
    late DriftStopProgressStore realProgress;

    setUp(() {
      db = inMemoryDatabase();
      addTearDown(db.close);
      realStore = DriftLocalWriteStore(db);
      realProgress = DriftStopProgressStore(db);
    });

    ExecutionRepository repositoryWith(DayLogStore log) => ExecutionRepository(
      realStore,
      realProgress,
      syncWorker,
      database: db,
      dayLog: log,
    );

    test('checkOut writes outbox, progress and day log atomically', () async {
      await realProgress.upsertInProgress('stop-1', 'exec-1');
      final failing = RecordingDayLogStore()
        ..failStopDone = Exception('disk full');

      await expectLater(
        repositoryWith(failing).checkOut(
          routeId: 'route-A',
          routeStopId: 'stop-1',
          qrPayload: 'q',
        ),
        throwsException,
      );

      expect(await realStore.unsyncedForRoute('route-A'), isEmpty);
      expect(
        (await realProgress.progressFor('stop-1'))!.status,
        StopLocalStatus.inProgress,
      );
      expect(syncWorker.syncedRoutes, isEmpty);
    });

    test('checkOut rolls the day-log row back with the rest when a later '
        'step fails', () async {
      await realProgress.upsertInProgress('stop-1', 'exec-1');
      final log = DriftDayLogStore(db);

      await expectLater(
        repositoryWith(_WritesThenThrowsDayLog(log)).checkOut(
          routeId: 'route-A',
          routeStopId: 'stop-1',
          qrPayload: 'q',
        ),
        throwsException,
      );

      // The real point was written inside the transaction, then undone.
      expect(await log.all(), isEmpty);
      expect(await realStore.unsyncedForRoute('route-A'), isEmpty);
      expect(
        (await realProgress.progressFor('stop-1'))!.status,
        StopLocalStatus.inProgress,
      );
    });

    test('a same-key checkOut retry adds no second point', () async {
      await realProgress.upsertInProgress('stop-1', 'exec-1');
      final log = DriftDayLogStore(db);
      final repository = repositoryWith(log);

      for (var i = 0; i < 2; i++) {
        await repository.checkOut(
          routeId: 'route-A',
          routeStopId: 'stop-1',
          qrPayload: 'q',
          checkoutIdempotencyKey: 'CK',
        );
      }

      expect((await log.all()).single.pointsDone, 1);
      expect(await realStore.unsyncedForRoute('route-A'), hasLength(1));
    });

    Future<String> photoFor(ExecutionRepository repo, String executionId) =>
        repo.addPhoto(
          routeId: 'route-A',
          executionId: executionId,
          photo: CapturedPhoto(bytes: Uint8List.fromList([1]), sha256: 'h'),
        );

    test('stampTask stamps the stop with its note and moves the held photo '
        'to pending', () async {
      await realProgress.upsertInProgress('stop-1', 'exec-1');
      final repository = repositoryWith(RecordingDayLogStore());
      final key = await photoFor(repository, 'exec-1');

      await repository.stampTask(
        routeId: 'route-A',
        routeStopId: 'stop-1',
        executionId: 'exec-1',
        observation: 'lampada trocada',
      );

      final entry = (await realProgress.progressFor('stop-1'))!;
      expect(entry.status, StopLocalStatus.stamped);
      expect(entry.observation, 'lampada trocada');
      final rows = await realStore.unsyncedForRoute('route-A');
      expect(rows.single.id, key);
      expect(rows.single.state, PendingOpState.pending);
      // No check-out yet: that waits for the floor's exit scan.
      expect(rows.where((r) => r.kind == PendingOpKind.checkOut), isEmpty);
    });

    test('stampTask releases only the photos of its own execution', () async {
      await realProgress.upsertInProgress('stop-1', 'exec-1');
      final repository = repositoryWith(RecordingDayLogStore());
      await photoFor(repository, 'exec-1');
      await photoFor(repository, 'exec-2');

      await repository.stampTask(
        routeId: 'route-A',
        routeStopId: 'stop-1',
        executionId: 'exec-1',
      );

      final states = [
        for (final row in await realStore.unsyncedForRoute('route-A'))
          (row.payload['execution_id'], row.state),
      ];
      expect(states, [
        ('exec-1', PendingOpState.pending),
        ('exec-2', PendingOpState.held),
      ]);
    });

    test('impedeTask deletes the held photos and enqueues a STOP '
        'impediment', () async {
      await realProgress.upsertInProgress('stop-1', 'exec-1');
      final repository = repositoryWith(RecordingDayLogStore());
      await photoFor(repository, 'exec-1');

      await repository.impedeTask(
        routeId: 'route-A',
        routeStopId: 'stop-1',
        reason: 'ACCESS_BLOCKED',
        note: 'porta trancada',
        executionId: 'exec-1',
      );

      final rows = await realStore.unsyncedForRoute('route-A');
      expect(rows, hasLength(1));
      expect(rows.single.kind, PendingOpKind.impediment);
      expect(rows.single.state, PendingOpState.pending);
      expect(rows.single.payload['scope'], 'STOP');
      expect(rows.single.payload['route_stop_id'], 'stop-1');
      expect(rows.single.payload['reason'], 'ACCESS_BLOCKED');
      expect(rows.single.payload['note'], 'porta trancada');
      expect(syncWorker.syncedRoutes, contains('route-A'));
    });

    test(
      'impedeTask without an execution still enqueues the impediment',
      () async {
        await repositoryWith(RecordingDayLogStore()).impedeTask(
          routeId: 'route-A',
          routeStopId: 'stop-1',
          reason: 'OTHER',
        );

        final rows = await realStore.unsyncedForRoute('route-A');
        expect(rows.single.kind, PendingOpKind.impediment);
      },
    );

    test('checkOut counts the stop in the real day log', () async {
      await realProgress.upsertInProgress('stop-1', 'exec-1');
      final log = DriftDayLogStore(db);

      await repositoryWith(log).checkOut(
        routeId: 'route-A',
        routeStopId: 'stop-1',
        qrPayload: 'q',
      );

      expect((await log.all()).single.pointsDone, 1);
      expect(await realStore.unsyncedForRoute('route-A'), hasLength(1));
    });
  });

  test('checkOut writes complaints_suggestions into the payload only when '
      'given', () async {
    await repository.checkOut(
      routeId: 'route-A',
      routeStopId: 'stop-1',
      qrPayload: 'q',
      checkoutIdempotencyKey: 'with',
      complaintsSuggestions: 'x',
    );
    await repository.checkOut(
      routeId: 'route-A',
      routeStopId: 'stop-2',
      qrPayload: 'q',
      checkoutIdempotencyKey: 'without',
    );

    final rows = {
      for (final row in await store.unsyncedForRoute('route-A')) row.id: row,
    };
    expect(rows['with']!.payload['complaints_suggestions'], 'x');
    expect(
      rows['without']!.payload.containsKey('complaints_suggestions'),
      isFalse,
    );
  });

  test('checkOut reuses a caller-supplied checkoutIdempotencyKey', () async {
    await repository.checkOut(
      routeId: 'route-A',
      routeStopId: 'stop-1',
      qrPayload: 'q',
      checkoutIdempotencyKey: 'CK',
    );
    await repository.checkOut(
      routeId: 'route-A',
      routeStopId: 'stop-1',
      qrPayload: 'q',
      checkoutIdempotencyKey: 'CK',
    );

    final rows = await store.unsyncedForRoute('route-A');
    expect(rows, hasLength(1));
    expect(rows.single.id, 'CK');
    // The retry queued nothing, so it counts no second point.
    expect(dayLog.calls.where((c) => c.startsWith('stopDone')), hasLength(1));
  });

  test('addPhoto enqueues one held evidencePhoto row and kicks the sync '
      'worker once', () async {
    final key = await repository.addPhoto(
      routeId: 'route-A',
      executionId: 'exec-1',
      photo: CapturedPhoto(
        bytes: Uint8List.fromList([1, 2, 3]),
        sha256: 'abc123',
      ),
    );

    final rows = await store.unsyncedForRoute('route-A');
    expect(rows, hasLength(1));
    expect(rows.single.state, PendingOpState.held);
    expect(rows.single.kind, PendingOpKind.evidencePhoto);
    expect(rows.single.payload['execution_id'], 'exec-1');
    expect(rows.single.payload['bytes_b64'], isA<String>());
    expect(rows.single.payload['sha256'], 'abc123');
    // The upload's idempotency key: the one the upload will carry.
    expect(rows.single.payload['idempotency_key'], key);
    expect(syncWorker.syncedRoutes, ['route-A']);
  });

  test(
    'reportImpediment enqueues one pending impediment row for a STOP '
    'scope, does not touch StopProgress and kicks the sync worker once',
    () async {
      await repository.reportImpediment(
        routeId: 'route-A',
        routeStopId: 'stop-1',
        scope: 'STOP',
        reason: 'ROOM_LOCKED',
        note: 'Sala trancada.',
      );

      final rows = await store.unsyncedForRoute('route-A');
      expect(rows, hasLength(1));
      expect(rows.single.state, PendingOpState.pending);
      expect(rows.single.kind, PendingOpKind.impediment);
      expect(rows.single.payload['route_id'], 'route-A');
      expect(rows.single.payload['route_stop_id'], 'stop-1');
      expect(rows.single.payload['scope'], 'STOP');
      expect(rows.single.payload['reason'], 'ROOM_LOCKED');
      expect(rows.single.payload['note'], 'Sala trancada.');
      expect(rows.single.payload['reported_at'], isA<String>());
      expect(
        () => DateTime.parse(rows.single.payload['reported_at'] as String),
        returnsNormally,
      );

      // Signalling never changes the stop's on-device status (unlike checkIn).
      expect(stopProgress.calls, isEmpty);
      expect(syncWorker.syncedRoutes, ['route-A']);
    },
  );

  test('reportImpediment for a ROUTE_REMAINDER scope enqueues '
      'route_stop_id: null', () async {
    await repository.reportImpediment(
      routeId: 'route-A',
      routeStopId: null,
      scope: 'ROUTE_REMAINDER',
      reason: 'VEHICLE_BREAKDOWN',
    );

    final rows = await store.unsyncedForRoute('route-A');
    expect(rows.single.payload.containsKey('route_stop_id'), isTrue);
    expect(rows.single.payload['route_stop_id'], isNull);
    expect(rows.single.payload['note'], isNull);
    expect(syncWorker.syncedRoutes, ['route-A']);
  });

  test('reportImpediment returns immediately even though the sync kick never '
      'completes (fire-and-forget)', () async {
    await repository
        .reportImpediment(
          routeId: 'route-A',
          routeStopId: 'stop-1',
          scope: 'STOP',
          reason: 'ROOM_LOCKED',
        )
        .timeout(const Duration(seconds: 1));

    expect(syncWorker.syncedRoutes, ['route-A']);
  });
}
