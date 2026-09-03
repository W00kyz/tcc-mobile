import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/evidence_capture.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/execution/execution_repository.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';

/// Records enqueue/API/mark calls in the order they happen, tagged with the
/// idempotency key — the four invariants below are all about ordering, so a
/// single shared log (rather than separate call counters) is what lets a
/// test assert "enqueue happened before the API call" directly.
class _FakeExecutionApi implements ExecutionApi {
  _FakeExecutionApi(this._log, {this._checkInImpl, this._checkOutImpl});

  final List<String> _log;
  final Future<CheckInResult> Function()? _checkInImpl;
  final Future<CheckOutResult> Function()? _checkOutImpl;
  int callCount = 0;
  final List<String> capturedIdempotencyKeys = [];
  final List<String> capturedCheckoutIdempotencyKeys = [];

  @override
  Future<({CheckInResult result, DateTime? serverDate})> checkIn({
    required String executionId,
    required String qrPayload,
    required DateTime scannedAt,
    required String idempotencyKey,
    double? latitude,
    double? longitude,
    String? routeStopId,
    double? clientClockOffsetSeconds,
  }) async {
    callCount++;
    capturedIdempotencyKeys.add(idempotencyKey);
    _log.add('api:$idempotencyKey');
    final impl = _checkInImpl;
    final result = impl != null
        ? await impl()
        : const CheckInResult(
            routeStopId: 'stop-1',
            executionId: 'exec-1',
            geoValidation: 'INSIDE',
            flags: [],
          );
    return (result: result, serverDate: null);
  }

  @override
  Future<({CheckOutResult result, DateTime? serverDate})> checkOut({
    required String executionId,
    required String qrPayload,
    required DateTime scannedAt,
    required String checkoutIdempotencyKey,
    double? latitude,
    double? longitude,
    String? routeStopId,
    double? clientClockOffsetSeconds,
  }) async {
    callCount++;
    capturedCheckoutIdempotencyKeys.add(checkoutIdempotencyKey);
    _log.add('api:$checkoutIdempotencyKey');
    final impl = _checkOutImpl;
    final result = impl != null
        ? await impl()
        : CheckOutResult(
            routeStopId: 'stop-1',
            executionId: 'exec-1',
            checkedOutAt: DateTime.utc(2026, 8, 25, 8, 40),
            flags: const [],
          );
    return (result: result, serverDate: null);
  }
}

/// An in-memory stand-in for [DriftLocalWriteStore] (real Drift behavior is
/// already proven by local_write_store_test.dart) — just enough to prove
/// ExecutionRepository enqueues/marks rows in the right order and state.
class _FakeLocalWriteStore implements LocalWriteStore {
  _FakeLocalWriteStore(this._log);

  final List<String> _log;
  final Map<String, PendingOperationRow> _rows = {};

  @override
  Future<void> enqueue({
    required String id,
    required PendingOpKind kind,
    required Map<String, dynamic> payload,
    required String routeId,
  }) async {
    _log.add('enqueue:$id');
    _rows[id] = PendingOperationRow(
      id: id,
      kind: kind,
      routeId: routeId,
      payload: payload,
      createdAt: _rows.length,
      state: PendingOpState.pending,
      lastError: null,
      attempts: 0,
      nextAttemptAt: null,
    );
  }

  @override
  Future<void> markSynced(String id) async {
    _log.add('markSynced:$id');
    _rows[id] = _rows[id]!.copyWith(state: PendingOpState.synced);
  }

  @override
  Future<void> markFailed(String id, String error) async {
    _log.add('markFailed:$id');
    _rows[id] = _rows[id]!.copyWith(state: PendingOpState.failed, error: error);
  }

  @override
  Future<List<PendingOperationRow>> unsyncedForRoute(String routeId) async {
    final rows =
        _rows.values
            .where(
              (row) =>
                  row.routeId == routeId && row.state != PendingOpState.synced,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return rows;
  }

  @override
  Future<void> markBlocked(String id, String error) async {
    _log.add('markBlocked:$id');
    _rows[id] = _rows[id]!.copyWith(
      state: PendingOpState.blocked,
      error: error,
    );
  }

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
}

extension on PendingOperationRow {
  PendingOperationRow copyWith({PendingOpState? state, String? error}) =>
      PendingOperationRow(
        id: id,
        kind: kind,
        routeId: routeId,
        payload: payload,
        createdAt: createdAt,
        state: state ?? this.state,
        lastError: error ?? lastError,
        attempts: attempts,
        nextAttemptAt: nextAttemptAt,
      );
}

/// Records every upload call instead of hitting the network, and throws
/// [uploadPhotoError]/[uploadNoteError] once (then clears it) — same
/// consume-once shape as `_FakeExecutionApi`'s `error` above.
class _FakeEvidenceApi implements EvidenceApi {
  _FakeEvidenceApi({this.uploadPhotoError, this.uploadNoteError});

  Exception? uploadPhotoError;
  Exception? uploadNoteError;
  final List<String> uploadedPhotoExecutionIds = [];
  final List<String> uploadedNoteExecutionIds = [];
  String? lastPhotoSha256;
  String? lastNoteText;

  @override
  Future<DateTime?> uploadPhoto({
    required String executionId,
    required Uint8List bytes,
    required String sha256,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async {
    uploadedPhotoExecutionIds.add(executionId);
    lastPhotoSha256 = sha256;
    if (uploadPhotoError != null) {
      final toThrow = uploadPhotoError!;
      uploadPhotoError = null;
      throw toThrow;
    }
    return null;
  }

  @override
  Future<DateTime?> uploadNote({
    required String executionId,
    required String textBody,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async {
    uploadedNoteExecutionIds.add(executionId);
    lastNoteText = textBody;
    if (uploadNoteError != null) {
      final toThrow = uploadNoteError!;
      uploadNoteError = null;
      throw toThrow;
    }
    return null;
  }

  @override
  Future<List<EvidenceItem>> listEvidence(String executionId) async => [];
}

/// In-memory stand-in for [DriftStopProgressStore] — real Drift behavior is
/// proven by stop_progress_store_test.dart; this just records calls so
/// checkIn/checkOut's Ruling 17 wiring can be asserted directly.
class _FakeStopProgressStore implements StopProgressStore {
  final List<String> calls = [];
  final Map<String, StopProgressEntry> _rows = {};

  @override
  Future<void> upsertInProgress(
    String routeStopId,
    String executionId,
  ) async {
    calls.add('inProgress:$routeStopId:$executionId');
    _rows[routeStopId] = StopProgressEntry(
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
      routeStopId: existing.routeStopId,
      executionId: existing.executionId,
      status: StopLocalStatus.done,
    );
  }

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

void main() {
  test(
    'checkIn enqueues the row before calling the API, then marks it synced',
    () async {
      final log = <String>[];
      final store = _FakeLocalWriteStore(log);
      final repository = ExecutionRepository(
        _FakeExecutionApi(log),
        store,
        _FakeEvidenceApi(),
        _FakeStopProgressStore(),
      );

      final result = await repository.checkIn(
        routeId: 'route-A',
        qrPayload: 'v1.floor.1.sig',
        latitude: -7.2,
        longitude: -35.9,
      );

      expect(result.routeStopId, 'stop-1');
      expect(log, hasLength(3));
      expect(log[0], startsWith('enqueue:'));
      expect(log[1], startsWith('api:'));
      expect(log[2], startsWith('markSynced:'));
      expect(log[0].split(':')[1], log[1].split(':')[1]);
      expect(await store.unsyncedForRoute('route-A'), isEmpty);
    },
  );

  test(
    'a network failure marks the row failed with the error and rethrows',
    () async {
      final log = <String>[];
      final store = _FakeLocalWriteStore(log);
      final networkError = DioException(
        requestOptions: RequestOptions(path: '/check-ins'),
      );
      final repository = ExecutionRepository(
        _FakeExecutionApi(log, checkInImpl: () async => throw networkError),
        store,
        _FakeEvidenceApi(),
        _FakeStopProgressStore(),
      );

      await expectLater(
        repository.checkIn(routeId: 'route-A', qrPayload: 'q'),
        throwsA(same(networkError)),
      );

      final rows = await store.unsyncedForRoute('route-A');
      expect(rows, hasLength(1));
      expect(rows.single.state, PendingOpState.failed);
      expect(rows.single.lastError, contains('DioException'));
    },
  );

  test(
    'AmbiguousRoomException marks the row failed and propagates unchanged',
    () async {
      final log = <String>[];
      final store = _FakeLocalWriteStore(log);
      const ambiguous = AmbiguousRoomException([
        RoomCandidate(
          routeStopId: 's1',
          servicePointId: 'sp1',
          name: 'Sala 101',
          distanceM: 3.2,
        ),
      ]);
      final repository = ExecutionRepository(
        _FakeExecutionApi(log, checkInImpl: () async => throw ambiguous),
        store,
        _FakeEvidenceApi(),
        _FakeStopProgressStore(),
      );

      await expectLater(
        repository.checkIn(routeId: 'route-A', qrPayload: 'q'),
        throwsA(same(ambiguous)),
      );

      final rows = await store.unsyncedForRoute('route-A');
      expect(rows, hasLength(1));
      expect(rows.single.state, PendingOpState.failed);
    },
  );

  test(
    'retryFailed re-posts failed rows for the route oldest-first and marks '
    'each synced',
    () async {
      final log = <String>[];
      final store = _FakeLocalWriteStore(log);
      await store.enqueue(
        id: 'op-old',
        kind: PendingOpKind.checkIn,
        routeId: 'route-A',
        payload: {
          'qr_payload': 'q-old',
          'latitude': null,
          'longitude': null,
          'scanned_at': DateTime(2026, 8, 25).toIso8601String(),
          'idempotency_key': 'op-old',
        },
      );
      await store.markFailed('op-old', 'network down');
      await store.enqueue(
        id: 'op-new',
        kind: PendingOpKind.checkIn,
        routeId: 'route-A',
        payload: {
          'qr_payload': 'q-new',
          'latitude': -7.2,
          'longitude': -35.9,
          'scanned_at': DateTime(2026, 8, 25, 1).toIso8601String(),
          'idempotency_key': 'op-new',
        },
      );
      final api = _FakeExecutionApi(log);
      final repository = ExecutionRepository(
        api,
        store,
        _FakeEvidenceApi(),
        _FakeStopProgressStore(),
      );

      await repository.retryFailed('route-A');

      expect(api.callCount, 2);
      expect(
        log.where((entry) => entry.startsWith('api:')).toList(),
        ['api:op-old', 'api:op-new'],
      );
      expect(await store.unsyncedForRoute('route-A'), isEmpty);
    },
  );

  test(
    'retryFailed upserts the stop-progress row for a checkIn that succeeds '
    'on retry (Ruling 17 — a retry success is not the cold-start gap)',
    () async {
      final log = <String>[];
      final store = _FakeLocalWriteStore(log);
      await store.enqueue(
        id: 'op-1',
        kind: PendingOpKind.checkIn,
        routeId: 'route-A',
        payload: {
          'qr_payload': 'q',
          'latitude': null,
          'longitude': null,
          'scanned_at': DateTime(2026, 8, 25).toIso8601String(),
          'idempotency_key': 'op-1',
          'route_stop_id': 'stop-1',
        },
      );
      await store.markFailed('op-1', 'network down');
      final openExecutions = _FakeStopProgressStore();
      final repository = ExecutionRepository(
        _FakeExecutionApi(log),
        store,
        _FakeEvidenceApi(),
        openExecutions,
      );

      await repository.retryFailed('route-A');

      expect(openExecutions.calls, ['inProgress:stop-1:exec-1']);
      expect(
        (await openExecutions.progressFor('stop-1'))?.executionId,
        'exec-1',
      );
    },
  );

  test(
    'checkIn reuses a caller-supplied idempotencyKey instead of generating '
    'a fresh one',
    () async {
      final log = <String>[];
      final store = _FakeLocalWriteStore(log);
      final api = _FakeExecutionApi(log);
      final repository = ExecutionRepository(
        api,
        store,
        _FakeEvidenceApi(),
        _FakeStopProgressStore(),
      );

      await repository.checkIn(
        routeId: 'route-A',
        qrPayload: 'q',
        idempotencyKey: 'retry-key-1',
      );

      expect(api.capturedIdempotencyKeys, ['retry-key-1']);
      expect(log[0], 'enqueue:retry-key-1');
    },
  );

  test(
    'checkIn generates a fresh idempotencyKey per call when omitted',
    () async {
      final log = <String>[];
      final store = _FakeLocalWriteStore(log);
      final api = _FakeExecutionApi(log);
      final repository = ExecutionRepository(
        api,
        store,
        _FakeEvidenceApi(),
        _FakeStopProgressStore(),
      );

      await repository.checkIn(routeId: 'route-A', qrPayload: 'q1');
      await repository.checkIn(routeId: 'route-A', qrPayload: 'q2');

      expect(api.capturedIdempotencyKeys.toSet(), hasLength(2));
    },
  );

  test(
    'checkOut enqueues the row before calling the API, then marks it synced',
    () async {
      final log = <String>[];
      final store = _FakeLocalWriteStore(log);
      final repository = ExecutionRepository(
        _FakeExecutionApi(log),
        store,
        _FakeEvidenceApi(),
        _FakeStopProgressStore(),
      );

      final result = await repository.checkOut(
        routeId: 'route-A',
        routeStopId: 'stop-1',
        qrPayload: 'v1.floor.1.sig',
        latitude: -7.2,
        longitude: -35.9,
      );

      expect(result.routeStopId, 'stop-1');
      expect(log, hasLength(3));
      expect(log[0], startsWith('enqueue:'));
      expect(log[1], startsWith('api:'));
      expect(log[2], startsWith('markSynced:'));
      expect(log[0].split(':')[1], log[1].split(':')[1]);
      expect(await store.unsyncedForRoute('route-A'), isEmpty);
    },
  );

  test(
    'a network failure during checkOut marks the row failed and rethrows',
    () async {
      final log = <String>[];
      final store = _FakeLocalWriteStore(log);
      final networkError = DioException(
        requestOptions: RequestOptions(path: '/check-outs'),
      );
      final repository = ExecutionRepository(
        _FakeExecutionApi(log, checkOutImpl: () async => throw networkError),
        store,
        _FakeEvidenceApi(),
        _FakeStopProgressStore(),
      );

      await expectLater(
        repository.checkOut(
          routeId: 'route-A',
          routeStopId: 'stop-1',
          qrPayload: 'q',
        ),
        throwsA(same(networkError)),
      );

      final rows = await store.unsyncedForRoute('route-A');
      expect(rows, hasLength(1));
      expect(rows.single.state, PendingOpState.failed);
      expect(rows.single.lastError, contains('DioException'));
    },
  );

  test(
    'AmbiguousRoomException from checkOut marks the row failed and '
    'propagates unchanged',
    () async {
      final log = <String>[];
      final store = _FakeLocalWriteStore(log);
      const ambiguous = AmbiguousRoomException([
        RoomCandidate(
          routeStopId: 's1',
          servicePointId: 'sp1',
          name: 'Sala 101',
          distanceM: 3.2,
        ),
      ]);
      final repository = ExecutionRepository(
        _FakeExecutionApi(log, checkOutImpl: () async => throw ambiguous),
        store,
        _FakeEvidenceApi(),
        _FakeStopProgressStore(),
      );

      await expectLater(
        repository.checkOut(
          routeId: 'route-A',
          routeStopId: 'stop-1',
          qrPayload: 'q',
        ),
        throwsA(same(ambiguous)),
      );

      final rows = await store.unsyncedForRoute('route-A');
      expect(rows, hasLength(1));
      expect(rows.single.state, PendingOpState.failed);
    },
  );

  test(
    'checkOut reuses a caller-supplied checkoutIdempotencyKey instead of '
    'generating a fresh one',
    () async {
      final log = <String>[];
      final store = _FakeLocalWriteStore(log);
      final api = _FakeExecutionApi(log);
      final repository = ExecutionRepository(
        api,
        store,
        _FakeEvidenceApi(),
        _FakeStopProgressStore(),
      );

      await repository.checkOut(
        routeId: 'route-A',
        routeStopId: 'stop-1',
        qrPayload: 'q',
        checkoutIdempotencyKey: 'retry-key-1',
      );

      expect(api.capturedCheckoutIdempotencyKeys, ['retry-key-1']);
      expect(log[0], 'enqueue:retry-key-1');
    },
  );

  test(
    'checkOut generates a fresh checkoutIdempotencyKey per call when '
    'omitted',
    () async {
      final log = <String>[];
      final store = _FakeLocalWriteStore(log);
      final api = _FakeExecutionApi(log);
      final repository = ExecutionRepository(
        api,
        store,
        _FakeEvidenceApi(),
        _FakeStopProgressStore(),
      );

      await repository.checkOut(
        routeId: 'route-A',
        routeStopId: 'stop-1',
        qrPayload: 'q1',
      );
      await repository.checkOut(
        routeId: 'route-A',
        routeStopId: 'stop-1',
        qrPayload: 'q2',
      );

      expect(api.capturedCheckoutIdempotencyKeys.toSet(), hasLength(2));
    },
  );

  test(
    'checkIn records the returned execution_id in StopProgressStore, '
    'keyed by the resolved routeStopId (Ruling 17)',
    () async {
      final log = <String>[];
      final store = _FakeLocalWriteStore(log);
      final openExecutions = _FakeStopProgressStore();
      final repository = ExecutionRepository(
        _FakeExecutionApi(log),
        store,
        _FakeEvidenceApi(),
        openExecutions,
      );

      await repository.checkIn(routeId: 'route-A', qrPayload: 'q');

      expect(openExecutions.calls, ['inProgress:stop-1:exec-1']);
      expect(
        (await openExecutions.progressFor('stop-1'))?.executionId,
        'exec-1',
      );
    },
  );

  test(
    'a checkIn failure never records a stop-progress row',
    () async {
      final log = <String>[];
      final store = _FakeLocalWriteStore(log);
      final openExecutions = _FakeStopProgressStore();
      final networkError = DioException(
        requestOptions: RequestOptions(path: '/check-ins'),
      );
      final repository = ExecutionRepository(
        _FakeExecutionApi(log, checkInImpl: () async => throw networkError),
        store,
        _FakeEvidenceApi(),
        openExecutions,
      );

      await expectLater(
        repository.checkIn(routeId: 'route-A', qrPayload: 'q'),
        throwsA(same(networkError)),
      );

      expect(openExecutions.calls, isEmpty);
    },
  );

  test(
    'checkOut marks the stop-progress row done for the checked-out routeStopId '
    '(Ruling 17)',
    () async {
      final log = <String>[];
      final store = _FakeLocalWriteStore(log);
      final openExecutions = _FakeStopProgressStore();
      await openExecutions.upsertInProgress('stop-1', 'exec-1');
      openExecutions.calls.clear();
      final repository = ExecutionRepository(
        _FakeExecutionApi(log),
        store,
        _FakeEvidenceApi(),
        openExecutions,
      );

      await repository.checkOut(
        routeId: 'route-A',
        routeStopId: 'stop-1',
        qrPayload: 'q',
      );

      expect(openExecutions.calls, ['done:stop-1']);
      expect(
        (await openExecutions.progressFor('stop-1'))?.status,
        StopLocalStatus.done,
      );
    },
  );

  test(
    'addPhoto enqueues an evidencePhoto row before uploading, then marks it '
    'synced',
    () async {
      final store = _FakeLocalWriteStore([]);
      final evidenceApi = _FakeEvidenceApi();
      final repository = ExecutionRepository(
        _FakeExecutionApi([]),
        store,
        evidenceApi,
        _FakeStopProgressStore(),
      );

      await repository.addPhoto(
        routeId: 'route-A',
        executionId: 'exec-1',
        photo: CapturedPhoto(
          bytes: Uint8List.fromList([1, 2, 3]),
          sha256: 'abc123',
        ),
      );

      expect(evidenceApi.uploadedPhotoExecutionIds, ['exec-1']);
      expect(evidenceApi.lastPhotoSha256, 'abc123');
      final rows = await store.unsyncedForRoute('route-A');
      expect(rows, isEmpty);
    },
  );

  test('a failed photo upload marks the row failed and rethrows', () async {
    final store = _FakeLocalWriteStore([]);
    final uploadError = DioException(
      requestOptions: RequestOptions(path: '/executions/exec-1/evidence/photo'),
    );
    final repository = ExecutionRepository(
      _FakeExecutionApi([]),
      store,
      _FakeEvidenceApi(uploadPhotoError: uploadError),
      _FakeStopProgressStore(),
    );

    await expectLater(
      repository.addPhoto(
        routeId: 'route-A',
        executionId: 'exec-1',
        photo: CapturedPhoto(
          bytes: Uint8List.fromList([1, 2, 3]),
          sha256: 'abc123',
        ),
      ),
      throwsA(same(uploadError)),
    );

    final rows = await store.unsyncedForRoute('route-A');
    expect(rows, hasLength(1));
    expect(rows.single.kind, PendingOpKind.evidencePhoto);
    expect(rows.single.state, PendingOpState.failed);
    expect(rows.single.payload['execution_id'], 'exec-1');
    expect(rows.single.payload['bytes_b64'], isNotNull);
  });

  test(
    'addNote enqueues an evidenceNote row before uploading, then marks it '
    'synced',
    () async {
      final store = _FakeLocalWriteStore([]);
      final evidenceApi = _FakeEvidenceApi();
      final repository = ExecutionRepository(
        _FakeExecutionApi([]),
        store,
        evidenceApi,
        _FakeStopProgressStore(),
      );

      await repository.addNote(
        routeId: 'route-A',
        executionId: 'exec-1',
        text: 'Sala trancada.',
      );

      expect(evidenceApi.uploadedNoteExecutionIds, ['exec-1']);
      expect(evidenceApi.lastNoteText, 'Sala trancada.');
      final rows = await store.unsyncedForRoute('route-A');
      expect(rows, isEmpty);
    },
  );

  test('a failed note upload marks the row failed and rethrows', () async {
    final store = _FakeLocalWriteStore([]);
    final uploadError = DioException(
      requestOptions: RequestOptions(path: '/executions/exec-1/evidence/note'),
    );
    final repository = ExecutionRepository(
      _FakeExecutionApi([]),
      store,
      _FakeEvidenceApi(uploadNoteError: uploadError),
      _FakeStopProgressStore(),
    );

    await expectLater(
      repository.addNote(
        routeId: 'route-A',
        executionId: 'exec-1',
        text: 'Sala trancada.',
      ),
      throwsA(same(uploadError)),
    );

    final rows = await store.unsyncedForRoute('route-A');
    expect(rows, hasLength(1));
    expect(rows.single.kind, PendingOpKind.evidenceNote);
    expect(rows.single.state, PendingOpState.failed);
    expect(rows.single.payload['text_body'], 'Sala trancada.');
  });
}
