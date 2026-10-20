import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/sync/sync_worker.dart';

import '../support/fake_connectivity.dart';

DioException _dio({DioExceptionType? type, int? status, Object? body}) {
  final options = RequestOptions(path: '/x');
  return DioException(
    requestOptions: options,
    type: type ?? DioExceptionType.unknown,
    response: status == null
        ? null
        : Response<dynamic>(
            requestOptions: options,
            statusCode: status,
            data: body,
          ),
  );
}

class _FakeExecutionApi implements ExecutionApi {
  _FakeExecutionApi(this.log);

  final List<String> log;
  Exception? checkInError;
  Exception? checkOutError;
  Exception? impedimentError;
  bool consumeError = true;
  DateTime? serverDate;
  double? lastClientClockOffset;
  String? lastFormVersionId;
  List<Map<String, Object?>>? lastAnswers;
  ({
    String routeId,
    String? routeStopId,
    String scope,
    String reason,
    String? note,
    DateTime reportedAt,
  })?
  lastImpediment;

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
    log.add('checkIn:$idempotencyKey');
    lastClientClockOffset = clientClockOffsetSeconds;
    final error = checkInError;
    if (error != null) {
      if (consumeError) checkInError = null;
      throw error;
    }
    return (
      result: const CheckInResult(
        routeStopId: 'stop-1',
        executionId: 'exec-1',
        geoValidation: 'INSIDE',
        flags: [],
      ),
      serverDate: serverDate,
    );
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
    String? formVersionId,
    List<Map<String, Object?>>? answers,
  }) async {
    log.add('checkOut:$checkoutIdempotencyKey');
    lastFormVersionId = formVersionId;
    lastAnswers = answers;
    final error = checkOutError;
    if (error != null) {
      if (consumeError) checkOutError = null;
      throw error;
    }
    return (
      result: CheckOutResult(
        routeStopId: 'stop-1',
        executionId: 'exec-1',
        checkedOutAt: DateTime.utc(2026),
        flags: const [],
      ),
      serverDate: serverDate,
    );
  }

  @override
  Future<void> reportImpediment({
    required String routeId,
    required String? routeStopId,
    required String scope,
    required String reason,
    required DateTime reportedAt,
    String? note,
  }) async {
    log.add('impediment:$scope:$routeStopId');
    lastImpediment = (
      routeId: routeId,
      routeStopId: routeStopId,
      scope: scope,
      reason: reason,
      note: note,
      reportedAt: reportedAt,
    );
    final error = impedimentError;
    if (error != null) {
      if (consumeError) impedimentError = null;
      throw error;
    }
  }
}

class _FakeEvidenceApi implements EvidenceApi {
  _FakeEvidenceApi(this.log);

  final List<String> log;
  Exception? photoError;
  DateTime? serverDate;

  @override
  Future<DateTime?> uploadPhoto({
    required String executionId,
    required Uint8List bytes,
    required String sha256,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async {
    log.add('photo:$idempotencyKey');
    final error = photoError;
    if (error != null) {
      photoError = null;
      throw error;
    }
    return serverDate;
  }

  @override
  Future<DateTime?> uploadNote({
    required String executionId,
    required String textBody,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async {
    log.add('note:$idempotencyKey');
    return serverDate;
  }

  @override
  Future<List<EvidenceItem>> listEvidence(String executionId) async => const [];
}

class _FakeStopProgressStore implements StopProgressStore {
  final List<String> calls = [];
  final Map<String, StopProgressEntry> rows = {};

  @override
  Future<void> upsertInProgress(String routeStopId, String executionId) async {
    calls.add('inProgress:$routeStopId');
    rows[routeStopId] = StopProgressEntry(
      routeStopId: routeStopId,
      executionId: executionId,
      status: StopLocalStatus.inProgress,
    );
  }

  @override
  Future<void> markDone(String routeStopId) async {
    calls.add('done:$routeStopId');
    final existing = rows[routeStopId];
    if (existing == null) return;
    rows[routeStopId] = StopProgressEntry(
      routeStopId: existing.routeStopId,
      executionId: existing.executionId,
      status: StopLocalStatus.done,
    );
  }

  @override
  Future<StopProgressEntry?> progressFor(String routeStopId) async =>
      rows[routeStopId];

  @override
  Future<List<StopProgressEntry>> allForRoute(
    Iterable<String> routeStopIds,
  ) async => [for (final id in routeStopIds) ?rows[id]];
}

class _FakeSyncMetaStore implements SyncMetaStore {
  double? offset;
  final Map<String, DateTime> routeStartedAt = {};

  @override
  Future<double?> getClockOffsetSeconds() async => offset;

  @override
  Future<void> setClockOffsetSeconds(double seconds) async => offset = seconds;

  @override
  Future<DateTime?> getRouteStartedAt(String routeId) async =>
      routeStartedAt[routeId];

  @override
  Future<void> setRouteStartedAt(String routeId, DateTime startedAt) async =>
      routeStartedAt[routeId] = startedAt;
}

class _FakeRouteRepository implements RouteRepository {
  _FakeRouteRepository(this.log);

  final List<String> log;
  Exception? startError;

  ({String routeId, double latitude, double longitude, DateTime startedAt})?
  lastStart;

  @override
  Future<List<RouteSummary>> fetchMyRoutes({DateTime? date}) async =>
      throw UnimplementedError();

  @override
  Future<RouteSummary> startRoute({
    required String routeId,
    required double latitude,
    required double longitude,
    required DateTime startedAt,
  }) async {
    log.add('start:$routeId');
    lastStart = (
      routeId: routeId,
      latitude: latitude,
      longitude: longitude,
      startedAt: startedAt,
    );
    final error = startError;
    if (error != null) {
      startError = null;
      throw error;
    }
    return RouteSummary(
      id: routeId,
      fieldWorkerName: 'João',
      routeDate: DateTime.utc(2026, 6),
      routeType: 'REGULAR',
      status: 'IN_PROGRESS',
      startedAt: startedAt,
      stops: const [],
    );
  }
}

class _FakeLocalWriteStore implements LocalWriteStore {
  final Map<String, PendingOperationRow> rows = {};

  void seed(
    String id, {
    required PendingOpKind kind,
    required int createdAt,
    Map<String, dynamic>? payload,
    String routeId = 'route-R',
    PendingOpState state = PendingOpState.pending,
  }) {
    rows[id] = PendingOperationRow(
      id: id,
      kind: kind,
      routeId: routeId,
      payload: payload ?? _defaultPayload(id),
      createdAt: createdAt,
      state: state,
      lastError: null,
      attempts: 0,
      nextAttemptAt: null,
    );
  }

  static Map<String, dynamic> _defaultPayload(String id) => {
    'execution_id': 'exec-$id',
    'qr_payload': 'v1.floor.1.sig',
    'scanned_at': DateTime.utc(2026).toIso8601String(),
    'captured_at': DateTime.utc(2026).toIso8601String(),
    'idempotency_key': id,
    'checkout_idempotency_key': id,
    'route_stop_id': 'stop-1',
    'sha256': 'abc',
    'bytes_b64': 'AAAA',
    'text_body': 'nota',
  };

  PendingOperationRow _copy(
    PendingOperationRow row, {
    PendingOpState? state,
    String? lastError,
    int? attempts,
    int? nextAttemptAt,
    bool clearNextAttemptAt = false,
  }) => PendingOperationRow(
    id: row.id,
    kind: row.kind,
    routeId: row.routeId,
    payload: row.payload,
    createdAt: row.createdAt,
    state: state ?? row.state,
    lastError: lastError ?? row.lastError,
    attempts: attempts ?? row.attempts,
    nextAttemptAt: clearNextAttemptAt
        ? null
        : nextAttemptAt ?? row.nextAttemptAt,
  );

  @override
  Future<void> enqueue({
    required String id,
    required PendingOpKind kind,
    required Map<String, dynamic> payload,
    required String routeId,
  }) async => seed(
    id,
    kind: kind,
    createdAt: rows.length,
    payload: payload,
    routeId: routeId,
  );

  @override
  Future<void> markSynced(String id) async =>
      rows[id] = _copy(rows[id]!, state: PendingOpState.synced);

  @override
  Future<void> markFailed(String id, String error) async => rows[id] = _copy(
    rows[id]!,
    state: PendingOpState.failed,
    lastError: error,
  );

  @override
  Future<void> markBlocked(String id, String error) async => rows[id] = _copy(
    rows[id]!,
    state: PendingOpState.blocked,
    lastError: error,
  );

  @override
  Future<void> markRetryScheduled(
    String id, {
    required int attempts,
    required int nextAttemptAt,
  }) async => rows[id] = _copy(
    rows[id]!,
    attempts: attempts,
    nextAttemptAt: nextAttemptAt,
  );

  @override
  Future<void> resetToPending(String id) async => rows[id] = _copy(
    rows[id]!,
    state: PendingOpState.pending,
    attempts: 0,
    clearNextAttemptAt: true,
  );

  List<PendingOperationRow> _sorted(Iterable<PendingOperationRow> it) =>
      it.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<List<PendingOperationRow>> unsyncedForRoute(String routeId) async =>
      _sorted(
        rows.values.where(
          (r) =>
              r.routeId == routeId &&
              (r.state == PendingOpState.pending ||
                  r.state == PendingOpState.failed),
        ),
      );

  @override
  Future<List<PendingOperationRow>> blockedForRoute(String routeId) async =>
      _sorted(
        rows.values.where(
          (r) => r.routeId == routeId && r.state == PendingOpState.blocked,
        ),
      );

  @override
  Future<List<PendingOperationRow>> dueForRoute(
    String routeId, {
    required int now,
  }) async => _sorted(
    rows.values.where(
      (r) =>
          r.routeId == routeId &&
          (r.state == PendingOpState.pending ||
              r.state == PendingOpState.failed) &&
          (r.nextAttemptAt == null || r.nextAttemptAt! <= now),
    ),
  );

  @override
  Future<List<String>> routeIdsWithWork() async => rows.values
      .where((r) => r.state != PendingOpState.synced)
      .map((r) => r.routeId)
      .toSet()
      .toList();
}

class _Harness {
  _Harness() {
    worker = SyncWorker(
      store,
      stopProgress,
      syncMeta,
      connectivity,
      executionApi,
      evidenceApi,
      routeApi,
      now: () => now,
      random: _ZeroRandom(),
    );
  }

  final log = <String>[];
  late final store = _FakeLocalWriteStore();
  final stopProgress = _FakeStopProgressStore();
  final syncMeta = _FakeSyncMetaStore();
  final connectivity = FakeConnectivity(isOnline: true);
  late final executionApi = _FakeExecutionApi(log);
  late final evidenceApi = _FakeEvidenceApi(log);
  late final routeApi = _FakeRouteRepository(log);
  DateTime now = DateTime.utc(2026, 6, 1, 12);
  late final SyncWorker worker;
}

/// Deterministic jitter so the backoff assertions can pin an exact value.
class _ZeroRandom implements math.Random {
  @override
  int nextInt(int max) => 0;

  @override
  double nextDouble() => 0;

  @override
  bool nextBool() => false;
}

void main() {
  test(
    'drains a route FIFO: check-in, photo, check-out in createdAt order',
    () async {
      final h = _Harness();
      h.store
        ..seed('a', kind: PendingOpKind.checkIn, createdAt: 1)
        ..seed('b', kind: PendingOpKind.evidencePhoto, createdAt: 2)
        ..seed('c', kind: PendingOpKind.checkOut, createdAt: 3);

      await h.worker.syncRoute('route-R');

      expect(h.log, ['checkIn:a', 'photo:b', 'checkOut:c']);
      expect(
        h.store.rows.values.map((r) => r.state),
        everyElement(PendingOpState.synced),
      );
      expect(h.stopProgress.rows['stop-1']?.status, StopLocalStatus.done);
    },
  );

  test(
    'a checkOut row with form_version_id + answers in its payload passes '
    'them through to ExecutionApi.checkOut, correctly typed after the '
    'jsonEncode/jsonDecode round-trip',
    () async {
      final h = _Harness();
      h.store.seed(
        'c',
        kind: PendingOpKind.checkOut,
        createdAt: 1,
        payload: {
          ..._FakeLocalWriteStore._defaultPayload('c'),
          'form_version_id': 'v2',
          // A round-trip through jsonEncode/jsonDecode (as the real
          // LocalWriteStore does) leaves this a List<dynamic> of
          // Map<String, dynamic> — reproduced here instead of a literal
          // List<Map<String, Object?>> so the test proves the worker's cast
          // actually copes with that shape.
          'answers': jsonDecode(
            jsonEncode([
              {'stable_key': 'q1', 'value': 'answered'},
            ]),
          ),
        },
      );

      await h.worker.syncRoute('route-R');

      expect(h.store.rows['c']!.state, PendingOpState.synced);
      expect(h.executionApi.lastFormVersionId, 'v2');
      expect(h.executionApi.lastAnswers, [
        {'stable_key': 'q1', 'value': 'answered'},
      ]);
    },
  );

  test(
    'a soft error defers the row and stops the queue, then recovers',
    () async {
      final h = _Harness();
      h.executionApi.checkInError = _dio(
        type: DioExceptionType.connectionError,
      );
      h.store
        ..seed('a', kind: PendingOpKind.checkIn, createdAt: 1)
        ..seed('b', kind: PendingOpKind.checkOut, createdAt: 2);

      await h.worker.syncRoute('route-R');

      final row = h.store.rows['a']!;
      expect(row.state, PendingOpState.failed);
      expect(row.attempts, 1);
      // backoff = min(1<<1, 60) = 2s, zero jitter.
      expect(row.nextAttemptAt, h.now.millisecondsSinceEpoch + 2000);
      expect(h.store.rows['b']!.state, PendingOpState.pending);
      expect(h.log, ['checkIn:a']);

      h.now = h.now.add(const Duration(seconds: 3));
      await h.worker.syncRoute('route-R');

      expect(
        h.store.rows.values.map((r) => r.state),
        everyElement(PendingOpState.synced),
      );
    },
  );

  test(
    'a hard error blocks the row, halts the route, and emits blocked',
    () async {
      final h = _Harness();
      h.executionApi.checkInError = _dio(status: 422);
      h.store
        ..seed('a', kind: PendingOpKind.checkIn, createdAt: 1)
        ..seed('b', kind: PendingOpKind.checkOut, createdAt: 2);

      final statuses = <RouteSyncStatus>[];
      final sub = h.worker.statusFor('route-R').listen(statuses.add);
      await Future<void>.delayed(Duration.zero);

      await h.worker.syncRoute('route-R');
      await Future<void>.delayed(Duration.zero);

      expect(h.store.rows['a']!.state, PendingOpState.blocked);
      expect(h.store.rows['a']!.lastError, contains('DioException'));
      expect(h.store.rows['b']!.state, PendingOpState.pending);
      expect(statuses.last.state, RouteSyncState.blocked);
      expect(statuses.last.blocked, 1);

      await sub.cancel();
    },
  );

  test(
    'a DioException with no response (type: unknown) is soft, not hard',
    () async {
      final h = _Harness();
      h.executionApi.checkInError = _dio(type: DioExceptionType.unknown);
      h.store.seed('a', kind: PendingOpKind.checkIn, createdAt: 1);

      await h.worker.syncRoute('route-R');

      final row = h.store.rows['a']!;
      expect(row.state, PendingOpState.failed);
      expect(row.attempts, 1);
      expect(row.nextAttemptAt, isNotNull);
    },
  );

  test(
    'a DioException with type: badCertificate and no response is soft',
    () async {
      final h = _Harness();
      h.executionApi.checkInError = _dio(
        type: DioExceptionType.badCertificate,
      );
      h.store.seed('a', kind: PendingOpKind.checkIn, createdAt: 1);

      await h.worker.syncRoute('route-R');

      final row = h.store.rows['a']!;
      expect(row.state, PendingOpState.failed);
      expect(row.attempts, 1);
      expect(row.nextAttemptAt, isNotNull);
    },
  );

  test(
    'AmbiguousRoomException blocks the row (RULING P5 — no picker in a drain)',
    () async {
      final h = _Harness();
      h.executionApi.checkInError = const AmbiguousRoomException([
        RoomCandidate(
          routeStopId: 's1',
          servicePointId: 'sp1',
          name: 'Sala 101',
        ),
      ]);
      h.store.seed('a', kind: PendingOpKind.checkIn, createdAt: 1);

      await h.worker.syncRoute('route-R');

      expect(h.store.rows['a']!.state, PendingOpState.blocked);
    },
  );

  test(
    'a 401 leaves the row pending and untouched and halts the pass',
    () async {
      // The token refresh already failed (Dio interceptor): only a new login
      // helps. Blocking here used to strand a whole offline route's writes.
      final h = _Harness();
      h.executionApi.checkInError = _dio(status: 401);
      h.store
        ..seed('a', kind: PendingOpKind.checkIn, createdAt: 1)
        ..seed('b', kind: PendingOpKind.evidencePhoto, createdAt: 2);

      await h.worker.syncRoute('route-R');

      final row = h.store.rows['a']!;
      expect(row.state, PendingOpState.pending);
      expect(row.attempts, 0);
      expect(h.log, ['checkIn:a']);
    },
  );

  test('a non-Dio error blocks the row', () async {
    final h = _Harness();
    h.executionApi.checkInError = const FormatException('boom');
    h.store.seed('a', kind: PendingOpKind.checkIn, createdAt: 1);

    await h.worker.syncRoute('route-R');

    expect(h.store.rows['a']!.state, PendingOpState.blocked);
  });

  test(
    'an "already applied" 409 counts as success and the queue continues',
    () async {
      final h = _Harness();
      h.executionApi.checkInError = _dio(
        status: 409,
        body: {'detail': 'Route already started'},
      );
      h.store
        ..seed('a', kind: PendingOpKind.checkIn, createdAt: 1)
        ..seed('b', kind: PendingOpKind.evidencePhoto, createdAt: 2);

      await h.worker.syncRoute('route-R');

      expect(h.store.rows['a']!.state, PendingOpState.synced);
      expect(h.store.rows['b']!.state, PendingOpState.synced);
      expect(h.log, ['checkIn:a', 'photo:b']);
    },
  );

  test('re-running a fully drained route makes zero API calls', () async {
    final h = _Harness();
    h.store.seed('a', kind: PendingOpKind.checkIn, createdAt: 1);

    await h.worker.syncRoute('route-R');
    h.log.clear();
    await h.worker.syncRoute('route-R');

    expect(h.log, isEmpty);
  });

  test(
    'captures the clock offset from a successful response Date header',
    () async {
      final h = _Harness();
      h.executionApi.serverDate = h.now.add(const Duration(seconds: 30));
      h.store.seed('a', kind: PendingOpKind.checkIn, createdAt: 1);

      await h.worker.syncRoute('route-R');

      expect(h.syncMeta.offset, closeTo(30, 0.001));
    },
  );

  test('sends the stored clock offset on the next check-in', () async {
    final h = _Harness();
    h.syncMeta.offset = -12.5;
    h.store.seed('a', kind: PendingOpKind.checkIn, createdAt: 1);

    await h.worker.syncRoute('route-R');

    expect(h.executionApi.lastClientClockOffset, -12.5);
  });

  test('unblock resets a blocked row to a clean pending state', () async {
    final h = _Harness();
    h.store.seed('a', kind: PendingOpKind.checkIn, createdAt: 1);
    await h.store.markBlocked('a', 'boom');
    await h.store.markRetryScheduled('a', attempts: 4, nextAttemptAt: 999);

    await h.worker.unblock('a');

    final row = h.store.rows['a']!;
    expect(row.state, PendingOpState.pending);
    expect(row.attempts, 0);
    expect(row.nextAttemptAt, isNull);
  });

  test(
    'syncAll still drains an unblocked route when another is blocked',
    () async {
      final h = _Harness();
      h.store
        ..seed(
          'a',
          kind: PendingOpKind.checkIn,
          createdAt: 1,
          state: PendingOpState.blocked,
        )
        ..seed(
          'b',
          kind: PendingOpKind.checkIn,
          createdAt: 2,
          routeId: 'route-S',
        );

      await h.worker.syncAll();

      expect(h.store.rows['a']!.state, PendingOpState.blocked);
      expect(h.store.rows['b']!.state, PendingOpState.synced);
    },
  );

  test(
    'the fifth soft failure blocks the row instead of rescheduling',
    () async {
      final h = _Harness();
      h.executionApi
        ..consumeError = false
        ..checkInError = _dio(status: 503);
      h.store.seed(
        'a',
        kind: PendingOpKind.checkIn,
        createdAt: 1,
        state: PendingOpState.failed,
      );
      h.store.rows['a'] = PendingOperationRow(
        id: 'a',
        kind: PendingOpKind.checkIn,
        routeId: 'route-R',
        payload: _FakeLocalWriteStore._defaultPayload('a'),
        createdAt: 1,
        state: PendingOpState.failed,
        lastError: 'prev',
        attempts: 4,
        nextAttemptAt: null,
      );

      await h.worker.syncRoute('route-R');

      expect(h.store.rows['a']!.state, PendingOpState.blocked);
    },
  );

  Map<String, dynamic> startPayload(DateTime startedAt) => {
    'route_id': 'route-R',
    'latitude': -7.21,
    'longitude': -35.91,
    'started_at': startedAt.toIso8601String(),
  };

  test(
    'a startRoute row dispatches via RouteRepository.startRoute with the '
    'payload values including the exact started_at',
    () async {
      final h = _Harness();
      final startedAt = DateTime.utc(2026, 6, 1, 7, 30);
      h.store.seed(
        's',
        kind: PendingOpKind.startRoute,
        createdAt: 1,
        payload: startPayload(startedAt),
      );

      await h.worker.syncRoute('route-R');

      expect(h.log, ['start:route-R']);
      expect(h.store.rows['s']!.state, PendingOpState.synced);
      expect(h.routeApi.lastStart, isNotNull);
      expect(h.routeApi.lastStart!.latitude, -7.21);
      expect(h.routeApi.lastStart!.longitude, -35.91);
      expect(h.routeApi.lastStart!.startedAt, startedAt);
    },
  );

  test(
    'a 409 "already started" on a startRoute row counts as success',
    () async {
      final h = _Harness();
      h.routeApi.startError = _dio(
        status: 409,
        body: {'detail': 'Route "route-R" was already started at ...'},
      );
      h.store.seed(
        's',
        kind: PendingOpKind.startRoute,
        createdAt: 1,
        payload: startPayload(DateTime.utc(2026, 6, 1, 7, 30)),
      );

      await h.worker.syncRoute('route-R');

      expect(h.store.rows['s']!.state, PendingOpState.synced);
    },
  );

  test(
    'a startRoute row before a check-in row dispatches first (FIFO)',
    () async {
      final h = _Harness();
      h.store
        ..seed(
          's',
          kind: PendingOpKind.startRoute,
          createdAt: 1,
          payload: startPayload(DateTime.utc(2026, 6, 1, 7, 30)),
        )
        ..seed('a', kind: PendingOpKind.checkIn, createdAt: 2);

      await h.worker.syncRoute('route-R');

      expect(h.log, ['start:route-R', 'checkIn:a']);
    },
  );

  Map<String, dynamic> impedimentPayload({
    required DateTime reportedAt,
    String? routeStopId = 'stop-1',
    String scope = 'STOP',
  }) => {
    'route_id': 'route-R',
    'route_stop_id': routeStopId,
    'scope': scope,
    'reason': 'ROOM_LOCKED',
    'note': 'Sala trancada.',
    'reported_at': reportedAt.toIso8601String(),
  };

  test(
    'an impediment row dispatches via ExecutionApi.reportImpediment with the '
    'payload values, typed after the jsonEncode/jsonDecode round-trip',
    () async {
      final h = _Harness();
      final reportedAt = DateTime.utc(2026, 6, 1, 9, 15);
      h.store.seed(
        'i',
        kind: PendingOpKind.impediment,
        createdAt: 1,
        payload: impedimentPayload(reportedAt: reportedAt),
      );

      await h.worker.syncRoute('route-R');

      expect(h.log, ['impediment:STOP:stop-1']);
      expect(h.store.rows['i']!.state, PendingOpState.synced);
      expect(h.executionApi.lastImpediment!.routeId, 'route-R');
      expect(h.executionApi.lastImpediment!.routeStopId, 'stop-1');
      expect(h.executionApi.lastImpediment!.scope, 'STOP');
      expect(h.executionApi.lastImpediment!.reason, 'ROOM_LOCKED');
      expect(h.executionApi.lastImpediment!.note, 'Sala trancada.');
      expect(h.executionApi.lastImpediment!.reportedAt, reportedAt);
    },
  );

  test(
    'a ROUTE_REMAINDER impediment row forwards a null route_stop_id',
    () async {
      final h = _Harness();
      h.store.seed(
        'i',
        kind: PendingOpKind.impediment,
        createdAt: 1,
        payload: impedimentPayload(
          routeStopId: null,
          scope: 'ROUTE_REMAINDER',
          reportedAt: DateTime.utc(2026, 6, 1, 9, 15),
        ),
      );

      await h.worker.syncRoute('route-R');

      expect(h.store.rows['i']!.state, PendingOpState.synced);
      expect(h.executionApi.lastImpediment!.routeStopId, isNull);
      expect(h.executionApi.lastImpediment!.scope, 'ROUTE_REMAINDER');
    },
  );

  test(
    'a 409 on an impediment row blocks it and halts the route queue',
    () async {
      final h = _Harness();
      h.executionApi.impedimentError = _dio(
        status: 409,
        body: {'detail': 'Route is not IN_PROGRESS.'},
      );
      h.store
        ..seed(
          'i',
          kind: PendingOpKind.impediment,
          createdAt: 1,
          payload: impedimentPayload(reportedAt: DateTime.utc(2026, 6, 1, 9)),
        )
        ..seed('b', kind: PendingOpKind.checkOut, createdAt: 2);

      await h.worker.syncRoute('route-R');

      expect(h.store.rows['i']!.state, PendingOpState.blocked);
      expect(h.store.rows['b']!.state, PendingOpState.pending);
    },
  );
}
