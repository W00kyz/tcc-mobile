import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
import 'package:route_monitor/sync/connectivity.dart';
import 'package:route_monitor/sync/sync_status.dart';

/// How the worker reacts to a failed dispatch (spec Ruling 6).
enum SyncErrorClass {
  /// Transient — retry with exponential backoff, then block after 5 tries.
  soft,

  /// The server already has this write — treat as a success.
  alreadyApplied,

  /// Permanent for this payload — block the row and halt the route's queue.
  hard,

  /// 401 even after the token refresh: the session must be renewed (a new
  /// login). Nothing is wrong with the row — leave it `pending`, untouched,
  /// and halt the pass; the next sync after login replays it. Classifying
  /// this as [hard] blocked every queued write of a route that outlived the
  /// 15-minute access token.
  awaitingAuth,
}

/// Drains the local outbox ([LocalWriteStore]) to the backend, strictly FIFO
/// per route (spec Ruling 6): rows for a route replay oldest-first, a soft
/// failure defers the rest, a hard failure blocks the whole route's queue,
/// and other routes are unaffected. On every successful dispatch it also
/// records the server-vs-device clock offset (spec Ruling 7).
class SyncWorker {
  SyncWorker(
    this._store,
    this._stopProgress,
    this._syncMeta,
    this._connectivity,
    this._executionApi,
    this._evidenceApi, {
    DateTime Function() now = DateTime.now,
    math.Random? random,
    // A private field can't be an initializing formal with a public param
    // name, and `now` must stay public for callers to inject a fake clock.
    // ignore: prefer_initializing_formals
  }) : _now = now,
       _random = random ?? math.Random();

  final LocalWriteStore _store;
  final StopProgressStore _stopProgress;
  final SyncMetaStore _syncMeta;
  final Connectivity _connectivity;
  final ExecutionApi _executionApi;
  final EvidenceApi _evidenceApi;
  final DateTime Function() _now;
  final math.Random _random;

  /// The drain pass in flight per route — the re-entrancy guard that keeps
  /// two triggers (foreground + regained connectivity) from interleaving.
  final Map<String, Future<void>> _passes = {};

  /// The one pass queued behind a running one, shared by every caller that
  /// arrives while it runs.
  final Map<String, Future<void>> _followUps = {};

  final Map<String, StreamController<RouteSyncStatus>> _statusControllers = {};

  /// One FIFO pass over [routeId]'s due rows; does nothing while the device
  /// is offline. Called while a pass is running, it queues one more pass
  /// behind it and completes with that one — the running pass read its rows
  /// before a write enqueued meanwhile, so awaiting this means every row due
  /// at call time was attempted (the next-batch pull relies on it: the
  /// server must have the last check-out before it is asked for a batch).
  ///
  ///     await worker.syncRoute(routeId);
  Future<void> syncRoute(String routeId) async {
    final running = _passes[routeId];
    if (running == null) return _startPass(routeId);
    return _followUps[routeId] ??= _passAfter(running, routeId);
  }

  Future<void> _passAfter(Future<void> running, String routeId) async {
    try {
      await running;
    } finally {
      // `remove` hands back this very follow-up, already being awaited.
      unawaited(_followUps.remove(routeId));
    }
    // A caller may have started a fresh pass in between; it read the queue
    // after the enqueue too, so join it rather than run two at once.
    await (_passes[routeId] ?? _startPass(routeId));
  }

  Future<void> _startPass(String routeId) {
    final pass = _drainAndRelease(routeId);
    _passes[routeId] = pass;
    return pass;
  }

  Future<void> _drainAndRelease(String routeId) async {
    try {
      await _drain(routeId);
    } finally {
      // `remove` hands back this very pass, already being awaited.
      unawaited(_passes.remove(routeId));
    }
  }

  Future<void> _drain(String routeId) async {
    if (!await _connectivity.isOnline) return;
    await _refresh(routeId, syncing: true);
    try {
      // Ruling 6: a blocked row halts its route on every later pass too —
      // nothing queued behind it may overtake it (a check-out never reaches
      // the server without its check-in). "Tentar de novo" (`unblock`)
      // resets it and the queue moves again.
      if ((await _store.blockedForRoute(routeId)).isNotEmpty) return;
      final rows = await _store.dueForRoute(
        routeId,
        now: _now().millisecondsSinceEpoch,
      );
      for (final row in rows) {
        final advanced = await _dispatch(row);
        // Stop on the first row that did not reach `synced`: the rest stay
        // `pending` so a check-out never precedes its check-in.
        if (!advanced) break;
      }
    } finally {
      await _refresh(routeId);
    }
  }

  /// Drains every route that has queued work. A route that blocks does not
  /// stop the others.
  Future<void> syncAll() async {
    for (final routeId in await _store.routeIdsWithWork()) {
      await syncRoute(routeId);
    }
  }

  /// The drain status for [routeId], re-emitted after every pass and every
  /// state change. Broadcast, so multiple widgets can listen.
  Stream<RouteSyncStatus> statusFor(String routeId) {
    final controller = _statusControllers.putIfAbsent(
      routeId,
      () => StreamController<RouteSyncStatus>.broadcast(
        onListen: () => _refresh(routeId),
      ),
    );
    return controller.stream;
  }

  /// Moves a `blocked` row back to a clean `pending` state so the next drain
  /// replays it (spec Ruling 6 — the "Tentar de novo" button).
  Future<void> unblock(String operationId) async {
    await _store.resetToPending(operationId);
  }

  Future<void> dispose() async {
    for (final controller in _statusControllers.values) {
      await controller.close();
    }
    _statusControllers.clear();
  }

  /// Dispatches one row. Returns true when the row reached `synced` (the
  /// queue may advance), false when it ended `failed`/`blocked`.
  Future<bool> _dispatch(PendingOperationRow row) async {
    try {
      final serverDate = await _perform(row);
      await _store.markSynced(row.id);
      await _recordOffset(serverDate);
      return true;
      // Deliberately broad: _classify sorts every failure (DioException,
      // AmbiguousRoomException, or anything else) into soft/alreadyApplied/
      // hard — nothing may escape a drain pass unhandled.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      final classification = _classify(error);
      if (classification == SyncErrorClass.alreadyApplied) {
        await _store.markSynced(row.id);
        return true;
      }
      if (classification == SyncErrorClass.awaitingAuth) return false;
      final message = error.toString();
      if (classification == SyncErrorClass.hard) {
        await _store.markBlocked(row.id, message);
        return false;
      }
      await _scheduleSoftRetry(row, message);
      return false;
    }
  }

  /// Ruling 5 review carry: `markRetryScheduled` does not set `state=failed`,
  /// so record the error first (which does), then the backoff.
  Future<void> _scheduleSoftRetry(PendingOperationRow row, String error) async {
    final attempts = row.attempts + 1;
    await _store.markFailed(row.id, error);
    if (attempts >= 5) {
      await _store.markBlocked(row.id, error);
      return;
    }
    final backoffSeconds = math.min(1 << attempts, 60);
    final jitterMs = _random.nextInt(1000);
    await _store.markRetryScheduled(
      row.id,
      attempts: attempts,
      nextAttemptAt:
          _now().millisecondsSinceEpoch + backoffSeconds * 1000 + jitterMs,
    );
  }

  Future<DateTime?> _perform(PendingOperationRow row) {
    final payload = row.payload;
    return switch (row.kind) {
      PendingOpKind.checkIn => _performCheckIn(payload),
      PendingOpKind.checkOut => _performCheckOut(payload),
      PendingOpKind.impediment => _performImpediment(payload),
      PendingOpKind.evidencePhoto => _evidenceApi.uploadPhoto(
        executionId: payload['execution_id'] as String,
        bytes: base64Decode(payload['bytes_b64'] as String),
        sha256: payload['sha256'] as String,
        capturedAt: DateTime.parse(payload['captured_at'] as String),
        idempotencyKey: payload['idempotency_key'] as String,
      ),
      PendingOpKind.evidenceNote => _evidenceApi.uploadNote(
        executionId: payload['execution_id'] as String,
        textBody: payload['text_body'] as String,
        capturedAt: DateTime.parse(payload['captured_at'] as String),
        idempotencyKey: payload['idempotency_key'] as String,
      ),
    };
  }

  Future<DateTime?> _performCheckIn(Map<String, dynamic> payload) async {
    final response = await _executionApi.checkIn(
      executionId: payload['execution_id'] as String,
      qrPayload: payload['qr_payload'] as String,
      scannedAt: DateTime.parse(payload['scanned_at'] as String),
      idempotencyKey: payload['idempotency_key'] as String,
      latitude: (payload['latitude'] as num?)?.toDouble(),
      longitude: (payload['longitude'] as num?)?.toDouble(),
      routeStopId: payload['route_stop_id'] as String?,
      clientClockOffsetSeconds: await _syncMeta.getClockOffsetSeconds(),
    );
    await _stopProgress.upsertInProgress(
      response.result.routeStopId,
      response.result.executionId,
    );
    return response.serverDate;
  }

  Future<DateTime?> _performCheckOut(Map<String, dynamic> payload) async {
    final response = await _executionApi.checkOut(
      executionId: payload['execution_id'] as String,
      qrPayload: payload['qr_payload'] as String,
      scannedAt: DateTime.parse(payload['scanned_at'] as String),
      checkoutIdempotencyKey: payload['checkout_idempotency_key'] as String,
      latitude: (payload['latitude'] as num?)?.toDouble(),
      longitude: (payload['longitude'] as num?)?.toDouble(),
      routeStopId: payload['route_stop_id'] as String?,
      clientClockOffsetSeconds: await _syncMeta.getClockOffsetSeconds(),
      formVersionId: payload['form_version_id'] as String?,
      // A JSON round-trip through LocalWriteStore's jsonEncode/jsonDecode
      // leaves each list element as `Map<String, dynamic>`, not the
      // `Map<String, Object?>` the API signature promises — cast each one
      // rather than the whole list, which `.cast<Map<String, Object?>>()`
      // cannot do for a `List<dynamic>` of `Map<String, dynamic>` maps.
      answers: (payload['answers'] as List?)
          ?.map((a) => Map<String, Object?>.from(a as Map))
          .toList(),
    );
    await _stopProgress.markDone(response.result.routeStopId);
    return response.serverDate;
  }

  Future<DateTime?> _performImpediment(Map<String, dynamic> payload) async {
    await _executionApi.reportImpediment(
      routeId: payload['route_id'] as String,
      routeStopId: payload['route_stop_id'] as String?,
      scope: payload['scope'] as String,
      reason: payload['reason'] as String,
      note: payload['note'] as String?,
      reportedAt: DateTime.parse(payload['reported_at'] as String),
    );
    // No serverDate to return: the impediment response is just the created
    // row, and check-in/out already measure the clock offset (Ruling 7). A
    // 409 (`RouteNotInProgress`/`StopNotReassignable`) falls through `_classify`
    // to `SyncErrorClass.hard`, blocking this route's queue.
    return null;
  }

  Future<void> _recordOffset(DateTime? serverDate) async {
    if (serverDate == null) return;
    final offsetSeconds = serverDate.difference(_now()).inMilliseconds / 1000.0;
    await _syncMeta.setClockOffsetSeconds(offsetSeconds);
  }

  SyncErrorClass _classify(Object error) {
    // RULING P5: a background drain cannot show a room picker, so an
    // unresolved-room check-in blocks that stop.
    if (error is AmbiguousRoomException) return SyncErrorClass.hard;
    if (error is! DioException) return SyncErrorClass.hard;

    final response = error.response;
    // No HTTP response at all — a pure transport/network failure (timeout,
    // DNS blip, TLS handshake abort wrapped as `type: unknown`, a non-socket
    // IOException mid-request). All recoverable: retry with backoff rather
    // than block the route forever.
    if (response == null) return SyncErrorClass.soft;

    final status = response.statusCode;
    if (status == 401) return SyncErrorClass.awaitingAuth;
    if (status != null && const {500, 502, 503, 504, 429}.contains(status)) {
      return SyncErrorClass.soft;
    }
    if (status == 409 &&
        _bodyText(response.data).toLowerCase().contains('already')) {
      return SyncErrorClass.alreadyApplied;
    }
    // 422 / 403 / 404 and every other non-retryable HTTP status: permanent.
    return SyncErrorClass.hard;
  }

  String _bodyText(Object? data) {
    if (data is String) return data;
    if (data is Map || data is List) return jsonEncode(data);
    return data?.toString() ?? '';
  }

  Future<void> _refresh(String routeId, {bool syncing = false}) async {
    final controller = _statusControllers[routeId];
    if (controller == null || controller.isClosed || !controller.hasListener) {
      return;
    }
    final pending = (await _store.unsyncedForRoute(routeId)).length;
    final blocked = (await _store.blockedForRoute(routeId)).length;
    final state = syncing
        ? RouteSyncState.syncing
        : blocked > 0
        ? RouteSyncState.blocked
        : RouteSyncState.idle;
    if (controller.isClosed) return;
    controller.add(
      RouteSyncStatus(
        routeId: routeId,
        state: state,
        pending: pending,
        blocked: blocked,
      ),
    );
  }
}
