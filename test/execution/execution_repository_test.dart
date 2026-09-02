import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/execution/execution_repository.dart';
import 'package:route_monitor/local/local_write_store.dart';

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
  Future<CheckInResult> checkIn({
    required String qrPayload,
    required DateTime scannedAt,
    required String idempotencyKey,
    double? latitude,
    double? longitude,
    String? routeStopId,
  }) async {
    callCount++;
    capturedIdempotencyKeys.add(idempotencyKey);
    _log.add('api:$idempotencyKey');
    if (_checkInImpl != null) return _checkInImpl();
    return const CheckInResult(
      routeStopId: 'stop-1',
      geoValidation: 'INSIDE',
      flags: [],
    );
  }

  @override
  Future<CheckOutResult> checkOut({
    required String qrPayload,
    required DateTime scannedAt,
    required String checkoutIdempotencyKey,
    double? latitude,
    double? longitude,
    String? routeStopId,
  }) async {
    callCount++;
    capturedCheckoutIdempotencyKeys.add(checkoutIdempotencyKey);
    _log.add('api:$checkoutIdempotencyKey');
    if (_checkOutImpl != null) return _checkOutImpl();
    return CheckOutResult(
      routeStopId: 'stop-1',
      checkedOutAt: DateTime.utc(2026, 8, 25, 8, 40),
      flags: const [],
    );
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
      );
}

void main() {
  test(
    'checkIn enqueues the row before calling the API, then marks it synced',
    () async {
      final log = <String>[];
      final store = _FakeLocalWriteStore(log);
      final repository = ExecutionRepository(_FakeExecutionApi(log), store);

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
      final repository = ExecutionRepository(api, store);

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
    'checkIn reuses a caller-supplied idempotencyKey instead of generating '
    'a fresh one',
    () async {
      final log = <String>[];
      final store = _FakeLocalWriteStore(log);
      final api = _FakeExecutionApi(log);
      final repository = ExecutionRepository(api, store);

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
      final repository = ExecutionRepository(api, store);

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
      final repository = ExecutionRepository(_FakeExecutionApi(log), store);

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
      final repository = ExecutionRepository(api, store);

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
      final repository = ExecutionRepository(api, store);

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
}
