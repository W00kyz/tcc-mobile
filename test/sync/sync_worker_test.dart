import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/released_stop_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
import 'package:route_monitor/sync/stop_release.dart';
import 'package:route_monitor/sync/sync_progress.dart';
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

  /// When set, every check-in waits on it — holds a drain pass mid-flight.
  Completer<void>? checkInGate;
  double? lastClientClockOffset;
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
    await checkInGate?.future;
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
    String? complaintsSuggestions,
  }) async {
    log.add('checkOut:$checkoutIdempotencyKey');
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
      updatedAt: DateTime(2026),
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
      updatedAt: DateTime(2026),
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

  @override
  Future<double?> getClockOffsetSeconds() async => offset;

  @override
  Future<void> setClockOffsetSeconds(double seconds) async => offset = seconds;

  bool appInForeground = false;

  @override
  Future<bool> getAppInForeground() async => appInForeground;

  @override
  Future<void> setAppInForeground({required bool inForeground}) async =>
      appInForeground = inForeground;
}

class _FakeLocalWriteStore implements LocalWriteStore {
  @override
  Future<bool> deletePendingPhoto(String operationId) =>
      throw UnimplementedError();

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
    String? releasedStopId,
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
    releasedStopId: releasedStopId ?? row.releasedStopId,
  );

  @override
  Future<bool> enqueue({
    required String id,
    required PendingOpKind kind,
    required Map<String, dynamic> payload,
    required String routeId,
  }) async {
    seed(
      id,
      kind: kind,
      createdAt: rows.length,
      payload: payload,
      routeId: routeId,
    );
    return true;
  }

  @override
  Future<void> markSynced(String id) async => rows[id] = _copy(
    rows[id]!,
    state: PendingOpState.synced,
    clearNextAttemptAt: true,
  );

  /// When set, the next `markFailed` throws it (a store write failing
  /// inside the dispatch's error path).
  Error? markFailedError;

  @override
  Future<void> markFailed(String id, String error) async {
    final failure = markFailedError;
    if (failure != null) {
      markFailedError = null;
      throw failure;
    }
    rows[id] = _copy(rows[id]!, state: PendingOpState.failed, lastError: error);
  }

  @override
  Future<void> markBlocked(String id, String error) async => rows[id] = _copy(
    rows[id]!,
    state: PendingOpState.blocked,
    lastError: error,
    clearNextAttemptAt: true,
  );

  @override
  Future<void> markStopReleased(
    String id, {
    required String routeStopId,
    required String error,
  }) async => rows[id] = _copy(
    rows[id]!,
    state: PendingOpState.blocked,
    lastError: error,
    releasedStopId: routeStopId,
    clearNextAttemptAt: true,
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

  @override
  Future<int> localPhotoCountFor(String executionId) =>
      throw UnimplementedError();

  List<PendingOperationRow> _sorted(Iterable<PendingOperationRow> it) =>
      it.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<List<PendingOperationRow>> unsyncedForRoute(String routeId) async =>
      _sorted(
        rows.values.where(
          (r) =>
              r.routeId == routeId &&
              (r.state == PendingOpState.pending ||
                  r.state == PendingOpState.failed ||
                  r.state == PendingOpState.sending),
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
      (r) => r.routeId == routeId && _isDue(r, now),
    ),
  );

  bool _isDue(PendingOperationRow r, int now) =>
      (r.state == PendingOpState.pending ||
          r.state == PendingOpState.failed ||
          r.state == PendingOpState.sending) &&
      (r.nextAttemptAt == null || r.nextAttemptAt! <= now);

  /// Like the Drift store's conditional UPDATE: only a due row is taken.
  @override
  Future<bool> claim(
    String id, {
    required int now,
    required int leaseUntil,
  }) async {
    final row = rows[id];
    if (row == null || !_isDue(row, now)) return false;
    rows[id] = _copy(
      row,
      state: PendingOpState.sending,
      nextAttemptAt: leaseUntil,
    );
    return true;
  }

  @override
  Future<void> releaseClaim(PendingOperationRow row) async {
    if (rows[row.id]?.state != PendingOpState.sending) return;
    rows[row.id] = row.state == PendingOpState.sending
        ? _copy(row, state: PendingOpState.pending, clearNextAttemptAt: true)
        : row;
  }

  @override
  Future<List<String>> routeIdsWithWork() async => rows.values
      .where((r) => r.state != PendingOpState.synced)
      .map((r) => r.routeId)
      .toSet()
      .toList();
}

/// Records each released stop once, like the Drift store's insert-or-ignore.
class _FakeReleasedStopStore implements ReleasedStopStore {
  final Map<String, ({String releaseReason, bool appealable})> notices = {};

  @override
  Future<bool> record({
    required String routeStopId,
    required String releaseReason,
    required bool appealable,
  }) async {
    if (notices.containsKey(routeStopId)) return false;
    notices[routeStopId] = (
      releaseReason: releaseReason,
      appealable: appealable,
    );
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _checkOutResponse = <String, dynamic>{
  'route_stop_id': 'stop-1',
  'execution_id': 'exec-1',
  'checked_out_at': '2026-06-01T12:00:00Z',
  'validation_flags': <String>[],
};

/// A real [Dio] whose adapter records every request and answers 200.
Dio _capturingDio({
  required void Function(RequestOptions) onRequest,
  required Map<String, dynamic> body,
}) =>
    Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _CapturingAdapter(onRequest, body);

class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter(this._onRequest, this._body);

  final void Function(RequestOptions) _onRequest;
  final Map<String, dynamic> _body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _onRequest(options);
    return ResponseBody.fromString(
      jsonEncode(_body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _Harness {
  _Harness({ExecutionApi? api}) {
    worker = SyncWorker(
      store,
      stopProgress,
      syncMeta,
      connectivity,
      api ?? executionApi,
      evidenceApi,
      releasedStops,
      now: () => now,
      random: _ZeroRandom(),
      onScanDelivered: (scannedAt) {
        deliveredScans.add(scannedAt);
        // ignore: only_throw_errors — replays what a disposed ref throws.
        if (scanCallbackError != null) throw scanCallbackError!;
      },
      onStopReleased: announcedReleases.add,
    );
  }

  final log = <String>[];
  final deliveredScans = <DateTime>[];
  final announcedReleases = <StopRelease>[];
  final releasedStops = _FakeReleasedStopStore();

  /// When set, the delivery callback throws it (e.g. a disposed Riverpod ref).
  Object? scanCallbackError;
  late final store = _FakeLocalWriteStore();
  final stopProgress = _FakeStopProgressStore();
  final syncMeta = _FakeSyncMetaStore();
  final connectivity = FakeConnectivity(isOnline: true);
  late final executionApi = _FakeExecutionApi(log);
  late final evidenceApi = _FakeEvidenceApi(log);
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

/// The body of the 409 a scan or upload synced after its stop was released
/// gets (backend `stop_released_conflict`).
DioException _stopReleased(
  String stop, {
  String reason = 'LOCATION_SILENCE',
  bool appealable = true,
}) => _dio(
  status: 409,
  body: {
    'detail': {
      'code': 'STOP_RELEASED',
      'detail': 'Route stop "$stop" was released back to the pool ($reason).',
      'route_stop_id': stop,
      'release_reason': reason,
      'appealable': appealable,
    },
  },
);

/// A row's payload on [stop], its execution named after the stop.
Map<String, dynamic> _stopPayload(String id, String stop) => {
  ..._FakeLocalWriteStore._defaultPayload(id),
  'route_stop_id': stop,
  'execution_id': 'exec-$stop',
};

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

  test('legacy checkOut row with form fields is sent without them', () async {
    // An old build queued this row before forms were removed: the payload
    // still carries `form_version_id` / `answers`. The real DioExecutionApi
    // is used so the assertion is on the wire body, not on a fake signature.
    final sent = <RequestOptions>[];
    final h = _Harness(
      api: DioExecutionApi(
        _capturingDio(onRequest: sent.add, body: _checkOutResponse),
      ),
    );
    h.store.seed(
      'c',
      kind: PendingOpKind.checkOut,
      createdAt: 1,
      payload: {
        ..._FakeLocalWriteStore._defaultPayload('c'),
        'form_version_id': 'v2',
        'answers': jsonDecode(
          jsonEncode([
            {'stable_key': 'q1', 'value': 'answered'},
          ]),
        ),
      },
    );

    await h.worker.syncRoute('route-R');

    expect(h.store.rows['c']!.state, PendingOpState.synced);
    final body = sent.single.data as Map;
    expect(body.containsKey('form_version_id'), isFalse);
    expect(body.containsKey('answers'), isFalse);
    expect(body['checkout_idempotency_key'], 'c');
  });

  test(
    'a checkOut row with complaints_suggestions sends it to the API',
    () async {
      final sent = <RequestOptions>[];
      final h = _Harness(
        api: DioExecutionApi(
          _capturingDio(onRequest: sent.add, body: _checkOutResponse),
        ),
      );
      h.store
        ..seed(
          'c',
          kind: PendingOpKind.checkOut,
          createdAt: 1,
          payload: {
            ..._FakeLocalWriteStore._defaultPayload('c'),
            'complaints_suggestions': 'Falta papel',
          },
        )
        ..seed('d', kind: PendingOpKind.checkOut, createdAt: 2);

      await h.worker.syncRoute('route-R');

      expect(sent, hasLength(2));
      expect((sent[0].data as Map)['complaints_suggestions'], 'Falta papel');
      expect(
        (sent[1].data as Map).containsKey('complaints_suggestions'),
        isFalse,
      );
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
      // The send claim is given back: due again at once after a login.
      expect(row.nextAttemptAt, isNull);
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
    'a 403 WORKER_NOT_APPROVED blocks the row at once, with no retry '
    'scheduled — the approval gate owns the UI from there',
    () async {
      final h = _Harness();
      h.executionApi.checkInError = _dio(
        status: 403,
        body: {
          'detail': {'code': 'WORKER_NOT_APPROVED', 'detail': 'deactivated'},
        },
      );
      h.executionApi.consumeError = false;
      h.store
        ..seed('a', kind: PendingOpKind.checkIn, createdAt: 1)
        ..seed(
          'b',
          kind: PendingOpKind.checkIn,
          createdAt: 2,
          payload: _stopPayload('b', 'stop-2'),
        );

      await h.worker.syncRoute('route-R');
      await h.worker.syncRoute('route-R');

      final row = h.store.rows['a']!;
      expect(row.state, PendingOpState.blocked);
      expect(row.attempts, 0);
      expect(row.nextAttemptAt, isNull);
      // Each stop is tried once and blocked — never retried, never jammed
      // behind another stop.
      expect(h.log, ['checkIn:a', 'checkIn:b']);
      expect(h.store.rows['b']!.state, PendingOpState.blocked);
    },
  );

  test(
    'syncRoute during a running pass waits for it and drains a row '
    'enqueued meanwhile, so awaiting it means the server has the row',
    () async {
      final h = _Harness();
      final gate = Completer<void>();
      h.executionApi.checkInGate = gate;
      h.store.seed('a', kind: PendingOpKind.checkIn, createdAt: 1);

      final first = h.worker.syncRoute('route-R');
      await Future<void>.delayed(Duration.zero);
      h.store.seed('c', kind: PendingOpKind.checkOut, createdAt: 2);
      var joinedDone = false;
      final joined = h.worker
          .syncRoute('route-R')
          .then((_) => joinedDone = true);
      await Future<void>.delayed(Duration.zero);
      expect(joinedDone, isFalse);

      gate.complete();
      await Future.wait([first, joined]);

      expect(h.log, ['checkIn:a', 'checkOut:c']);
      expect(h.store.rows['c']!.state, PendingOpState.synced);
    },
  );

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

  group('the silence clock (spec 2026-10-20-alocacao-automatica §7.3)', () {
    Map<String, dynamic> scannedAt(String id, DateTime at) => {
      ..._FakeLocalWriteStore._defaultPayload(id),
      'scanned_at': at.toIso8601String(),
    };

    test('a delivered check-in or check-out reports its scan time', () async {
      final h = _Harness();
      h.store
        ..seed(
          'a',
          kind: PendingOpKind.checkIn,
          createdAt: 1,
          payload: scannedAt('a', DateTime.utc(2026, 6, 1, 8, 20)),
        )
        ..seed('b', kind: PendingOpKind.evidencePhoto, createdAt: 2)
        ..seed(
          'c',
          kind: PendingOpKind.checkOut,
          createdAt: 3,
          payload: scannedAt('c', DateTime.utc(2026, 6, 1, 8, 40)),
        );

      await h.worker.syncRoute('route-R');

      // The device time of the scan, the one the server counts — not the
      // time it was delivered, and nothing for the photo.
      expect(h.deliveredScans, [
        DateTime.utc(2026, 6, 1, 8, 20),
        DateTime.utc(2026, 6, 1, 8, 40),
      ]);
    });

    test('a scan the server did not take reports nothing', () async {
      final h = _Harness();
      h.executionApi.checkInError = _dio(status: 503, body: {'detail': 'x'});
      h.store.seed('a', kind: PendingOpKind.checkIn, createdAt: 1);

      await h.worker.syncRoute('route-R');

      expect(h.deliveredScans, isEmpty);
    });

    test(
      'a throwing callback never un-syncs the row or stops the pass',
      () async {
        final h = _Harness()..scanCallbackError = StateError('ref unmounted');
        h.store
          ..seed('a', kind: PendingOpKind.checkIn, createdAt: 1)
          ..seed('b', kind: PendingOpKind.evidencePhoto, createdAt: 2);

        await h.worker.syncRoute('route-R');

        expect(h.store.rows['a']!.state, PendingOpState.synced);
        expect(h.store.rows['b']!.state, PendingOpState.synced);
        expect(h.log, ['checkIn:a', 'photo:b']);
      },
    );

    test('…nor on the "already applied" path', () async {
      final h = _Harness()..scanCallbackError = StateError('ref unmounted');
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
    });

    test('a scan the server already had still counts', () async {
      final h = _Harness();
      h.executionApi.checkInError = _dio(
        status: 409,
        body: {'detail': 'Route already started'},
      );
      h.store.seed('a', kind: PendingOpKind.checkIn, createdAt: 1);

      await h.worker.syncRoute('route-R');

      expect(h.deliveredScans, [DateTime.utc(2026)]);
    });
  });

  group('claims and ordering across two workers', () {
    const farFuture = 1 << 50;

    test("a row another worker has claimed is not sent, nor its stop's "
        'later rows; another stop still goes', () async {
      final h = _Harness();
      h.store
        ..seed('a', kind: PendingOpKind.checkIn, createdAt: 1)
        ..seed('b', kind: PendingOpKind.checkOut, createdAt: 2)
        ..seed(
          'c',
          kind: PendingOpKind.checkIn,
          createdAt: 3,
          payload: _stopPayload('c', 'stop-2'),
        );
      await h.store.claim('a', now: 0, leaseUntil: farFuture);

      await h.worker.syncRoute('route-R');

      expect(h.log, ['checkIn:c']);
    });

    test(
      'a failed check-in still in backoff holds back its check-out',
      () async {
        final h = _Harness();
        h.store
          ..seed('a', kind: PendingOpKind.checkIn, createdAt: 1)
          ..seed('b', kind: PendingOpKind.checkOut, createdAt: 2)
          ..seed(
            'c',
            kind: PendingOpKind.checkIn,
            createdAt: 3,
            payload: _stopPayload('c', 'stop-2'),
          );
        await h.store.markFailed('a', 'timeout');
        await h.store.markRetryScheduled(
          'a',
          attempts: 1,
          nextAttemptAt: farFuture,
        );

        await h.worker.syncRoute('route-R');

        expect(h.log, ['checkIn:c']);
      },
    );

    test('the sent row is claimed for the send lease, then settled', () async {
      final h = _Harness();
      h.store.seed('a', kind: PendingOpKind.checkIn, createdAt: 1);
      h.executionApi.checkInGate = Completer<void>();

      final pass = h.worker.syncRoute('route-R');
      await pumpEventQueue();
      final duringSend = h.store.rows['a']!;
      h.executionApi.checkInGate!.complete();
      await pass;

      expect(duringSend.state, PendingOpState.sending);
      expect(
        duringSend.nextAttemptAt,
        h.now.millisecondsSinceEpoch + SyncWorker.sendLease.inMilliseconds,
      );
      expect(h.store.rows['a']!.state, PendingOpState.synced);
    });

    test(
      'a store write that throws mid-dispatch gives the claim back',
      () async {
        final h = _Harness();
        h.store
          ..seed('a', kind: PendingOpKind.checkIn, createdAt: 1)
          ..markFailedError = StateError('database is locked');
        h.executionApi.checkInError = _dio(status: 503);

        await expectLater(h.worker.syncRoute('route-R'), throwsStateError);

        final row = h.store.rows['a']!;
        expect(row.state, PendingOpState.pending);
        expect(row.nextAttemptAt, isNull);
      },
    );
  });

  test(
    'SyncWorker.progress emits monotonically up to total during syncAll',
    () async {
      final h = _Harness();
      h.store
        ..seed('a', kind: PendingOpKind.checkIn, createdAt: 1)
        ..seed('b', kind: PendingOpKind.evidenceNote, createdAt: 2)
        ..seed(
          'c',
          kind: PendingOpKind.checkIn,
          createdAt: 3,
          routeId: 'route-S',
        );
      final seen = <SyncProgress>[];
      final subscription = h.worker.progress.listen(seen.add);
      addTearDown(subscription.cancel);

      await h.worker.syncAll();

      expect(seen.map((p) => (p.done, p.total)), [
        (0, 3),
        (1, 3),
        (2, 3),
        (3, 3),
      ]);
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
    'a check-out stays behind its own blocked check-in on later passes, '
    'until the check-in is retried by hand',
    () async {
      final h = _Harness();
      h.store
        ..seed(
          'a',
          kind: PendingOpKind.checkIn,
          createdAt: 1,
          state: PendingOpState.blocked,
        )
        ..seed('c', kind: PendingOpKind.checkOut, createdAt: 2);

      await h.worker.syncRoute('route-R');

      expect(h.log, isEmpty);
      expect(h.store.rows['c']!.state, PendingOpState.pending);

      await h.worker.unblock('a');
      await h.worker.syncRoute('route-R');

      expect(h.log, ['checkIn:a', 'checkOut:c']);
    },
  );

  test(
    'a blocked row on stop A (a late STOP_RELEASED) never holds back stop B',
    () async {
      final h = _Harness();
      h.store
        ..seed(
          'outA',
          kind: PendingOpKind.checkOut,
          createdAt: 1,
          state: PendingOpState.blocked,
          payload: _stopPayload('outA', 'stop-A'),
        )
        ..seed(
          'inB',
          kind: PendingOpKind.checkIn,
          createdAt: 2,
          payload: _stopPayload('inB', 'stop-B'),
        );

      await h.worker.syncRoute('route-R');

      expect(h.log, ['checkIn:inB']);
      expect(h.store.rows['inB']!.state, PendingOpState.synced);
    },
  );

  test(
    "evidence of a blocked check-in's execution is held, other stops' "
    'evidence is not',
    () async {
      final h = _Harness();
      h.store
        ..seed(
          'inA',
          kind: PendingOpKind.checkIn,
          createdAt: 1,
          state: PendingOpState.blocked,
          payload: _stopPayload('inA', 'stop-A'),
        )
        ..seed(
          'photoA',
          kind: PendingOpKind.evidencePhoto,
          createdAt: 2,
          payload: _stopPayload('photoA', 'stop-A'),
        )
        ..seed(
          'photoB',
          kind: PendingOpKind.evidencePhoto,
          createdAt: 3,
          payload: _stopPayload('photoB', 'stop-B'),
        );

      await h.worker.syncRoute('route-R');

      expect(h.log, ['photo:photoB']);
      expect(h.store.rows['photoA']!.state, PendingOpState.pending);
    },
  );

  test(
    'a hard failure mid-pass holds back its own stop and the pass goes on '
    'with the next stop',
    () async {
      final h = _Harness();
      h.executionApi.checkInError = _dio(status: 422);
      h.store
        ..seed(
          'inA',
          kind: PendingOpKind.checkIn,
          createdAt: 1,
          payload: _stopPayload('inA', 'stop-A'),
        )
        ..seed(
          'outA',
          kind: PendingOpKind.checkOut,
          createdAt: 2,
          payload: _stopPayload('outA', 'stop-A'),
        )
        ..seed(
          'inB',
          kind: PendingOpKind.checkIn,
          createdAt: 3,
          payload: _stopPayload('inB', 'stop-B'),
        );

      await h.worker.syncRoute('route-R');

      expect(h.log, ['checkIn:inA', 'checkIn:inB']);
      expect(h.store.rows['inA']!.state, PendingOpState.blocked);
      expect(h.store.rows['outA']!.state, PendingOpState.pending);
      expect(h.store.rows['inB']!.state, PendingOpState.synced);
    },
  );

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

  group('a 409 STOP_RELEASED (spec 2026-10-20-alocacao-automatica §7.5)', () {
    test(
      'parks a late check-out on its stop with its data kept, records the '
      'released stop and announces it — the next stop still syncs',
      () async {
        final h = _Harness();
        h.executionApi.checkOutError = _stopReleased('stop-A');
        h.store
          ..seed(
            'outA',
            kind: PendingOpKind.checkOut,
            createdAt: 1,
            payload: _stopPayload('outA', 'stop-A'),
          )
          ..seed(
            'inB',
            kind: PendingOpKind.checkIn,
            createdAt: 2,
            payload: _stopPayload('inB', 'stop-B'),
          );

        await h.worker.syncRoute('route-R');

        final parked = h.store.rows['outA']!;
        expect(parked.state, PendingOpState.blocked);
        expect(parked.releasedStopId, 'stop-A');
        expect(parked.payload, _stopPayload('outA', 'stop-A'));
        expect(h.releasedStops.notices, {
          'stop-A': (releaseReason: 'LOCATION_SILENCE', appealable: true),
        });
        expect(h.announcedReleases.single.routeStopId, 'stop-A');
        expect(h.announcedReleases.single.appealable, isTrue);
        expect(h.store.rows['inB']!.state, PendingOpState.synced);
        // Never delivered: the silence clock must not count it.
        expect(h.deliveredScans, [DateTime.utc(2026)]);
      },
    );

    test(
      'parks a photo on the stop the server names — evidence carries no stop '
      'of its own — and holds back the rest of its execution',
      () async {
        final h = _Harness();
        h.evidenceApi.photoError = _stopReleased('stop-A');
        h.store
          ..seed(
            'photo1',
            kind: PendingOpKind.evidencePhoto,
            createdAt: 1,
            payload: _stopPayload('photo1', 'stop-A'),
          )
          ..seed(
            'note1',
            kind: PendingOpKind.evidenceNote,
            createdAt: 2,
            payload: _stopPayload('note1', 'stop-A'),
          );

        await h.worker.syncRoute('route-R');

        expect(h.store.rows['photo1']!.releasedStopId, 'stop-A');
        expect(h.store.rows['note1']!.state, PendingOpState.pending);
        expect(h.log, ['photo:photo1']);
      },
    );

    test(
      'a second 409 on an already-recorded stop announces nothing',
      () async {
        final h = _Harness();
        await h.releasedStops.record(
          routeStopId: 'stop-A',
          releaseReason: 'LOCATION_SILENCE',
          appealable: true,
        );
        h.executionApi.checkOutError = _stopReleased('stop-A');
        h.store.seed(
          'outA',
          kind: PendingOpKind.checkOut,
          createdAt: 1,
          payload: _stopPayload('outA', 'stop-A'),
        );

        await h.worker.syncRoute('route-R');

        expect(h.store.rows['outA']!.releasedStopId, 'stop-A');
        expect(h.announcedReleases, isEmpty);
      },
    );

    test(
      'a release the worker caused (an impediment) is parked and recorded as '
      'not appealable',
      () async {
        final h = _Harness();
        h.executionApi.checkInError = _stopReleased(
          'stop-A',
          reason: 'IMPEDIMENT',
          appealable: false,
        );
        h.store.seed(
          'inA',
          kind: PendingOpKind.checkIn,
          createdAt: 1,
          payload: _stopPayload('inA', 'stop-A'),
        );

        await h.worker.syncRoute('route-R');

        expect(h.store.rows['inA']!.releasedStopId, 'stop-A');
        expect(h.releasedStops.notices['stop-A']!.appealable, isFalse);
        expect(h.announcedReleases.single.appealable, isFalse);
      },
    );
  });
}
