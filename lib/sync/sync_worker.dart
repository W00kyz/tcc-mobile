import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/released_stop_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
import 'package:route_monitor/sync/blocked_scope.dart';
import 'package:route_monitor/sync/connectivity.dart';
import 'package:route_monitor/sync/stop_release.dart';
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

/// Where one dispatch left its row.
enum _Dispatched { synced, blocked, deferred }

/// Drains the local outbox ([LocalWriteStore]) to the backend, FIFO per
/// route (spec Ruling 6): rows for a route replay oldest-first, a soft
/// failure defers the rest, a hard failure blocks that row and holds back
/// only the rows that depend on it ([BlockedScope]: same stop, evidence of
/// the same execution), and other routes are unaffected. On every
/// successful dispatch it also records the server-vs-device clock offset
/// (spec Ruling 7). A write that reaches the server after its stop was
/// released is parked for the appeal flow ([ReleasedStopStore]).
class SyncWorker {
  SyncWorker(
    this._store,
    this._stopProgress,
    this._syncMeta,
    this._connectivity,
    this._executionApi,
    this._evidenceApi,
    this._releasedStops, {
    DateTime Function() now = DateTime.now,
    math.Random? random,
    void Function(DateTime scannedAt)? onScanDelivered,
    void Function(StopRelease release)? onStopReleased,
    // A private field can't be an initializing formal with a public param
    // name, and `now` must stay public for callers to inject a fake clock.
    // ignore: prefer_initializing_formals
  }) : _now = now,
       _random = random ?? math.Random(),
       // Same reason as `now` above: the param name stays public.
       // ignore: prefer_initializing_formals
       _onScanDelivered = onScanDelivered,
       // Same reason as `now` above: the param name stays public.
       // ignore: prefer_initializing_formals
       _onStopReleased = onStopReleased;

  final LocalWriteStore _store;
  final StopProgressStore _stopProgress;
  final SyncMetaStore _syncMeta;
  final Connectivity _connectivity;
  final ExecutionApi _executionApi;
  final EvidenceApi _evidenceApi;
  final ReleasedStopStore _releasedStops;
  final DateTime Function() _now;
  final math.Random _random;

  /// A check-in or check-out the server now has, at its device scan time —
  /// the moment the server's silence clock counts (spec
  /// 2026-10-20-alocacao-automatica §7.3). Reported on delivery, never on
  /// the local write: a scan queued offline has not reached that clock yet.
  final void Function(DateTime scannedAt)? _onScanDelivered;

  /// A stop seen released for the first time — the moment the app offers
  /// the appeal (spec 2026-10-20-alocacao-automatica §7.5). Reported once per
  /// stop, however many of its rows come back 409.
  final void Function(StopRelease release)? _onStopReleased;

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
      // Ruling 6, scoped: a blocked row holds back what depends on it, on
      // this pass and every later one — a check-out never reaches the server
      // without its check-in — but never another stop of the route. "Tentar
      // de novo" (`unblock`) resets it and its dependents move again.
      final scope = BlockedScope(await _store.blockedForRoute(routeId));
      final rows = await _store.dueForRoute(
        routeId,
        now: _now().millisecondsSinceEpoch,
      );
      for (final row in rows) {
        if (scope.holds(row)) continue;
        final outcome = await _dispatch(row);
        if (outcome == _Dispatched.blocked) {
          scope.add(row);
          continue;
        }
        // A deferred row (soft failure, awaiting login) stops the pass: the
        // network or the session is the problem, not this row.
        if (outcome == _Dispatched.deferred) break;
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

  /// Dispatches one row and says where it ended. A synced scan is reported
  /// only once the row's state is final, so the report can never change it.
  Future<_Dispatched> _dispatch(PendingOperationRow row) async {
    final outcome = await _attempt(row);
    if (outcome == _Dispatched.synced) _reportScanDelivered(row);
    return outcome;
  }

  Future<_Dispatched> _attempt(PendingOperationRow row) async {
    try {
      final serverDate = await _perform(row);
      await _store.markSynced(row.id);
      await _recordOffset(serverDate);
      return _Dispatched.synced;
      // Deliberately broad: _classify sorts every failure (DioException,
      // AmbiguousRoomException, or anything else) into soft/alreadyApplied/
      // hard — nothing may escape a drain pass unhandled.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      final release = StopRelease.fromError(error);
      if (release != null) return _park(row, release);
      final classification = _classify(error);
      if (classification == SyncErrorClass.alreadyApplied) {
        // The server had it already — and counted its scan then.
        await _store.markSynced(row.id);
        return _Dispatched.synced;
      }
      if (classification == SyncErrorClass.awaitingAuth) {
        return _Dispatched.deferred;
      }
      final message = error.toString();
      if (classification == SyncErrorClass.hard) {
        // Also a 403 WORKER_NOT_APPROVED (permanent; the approval gate owns
        // the UI) — it holds back only its own stop.
        await _store.markBlocked(row.id, message);
        return _Dispatched.blocked;
      }
      await _scheduleSoftRetry(row, message);
      return _Dispatched.deferred;
    }
  }

  /// A `409 STOP_RELEASED`: the row is blocked on the released stop with its
  /// payload kept — replaying it would only get the same 409 — and holds
  /// back just that stop ([BlockedScope]); the rest of the day keeps
  /// flowing. The stop is recorded first, so a crash in between leaves the
  /// row pending and the next pass parks it again, without a second notice.
  Future<_Dispatched> _park(
    PendingOperationRow row,
    StopRelease release,
  ) async {
    final firstTime = await _releasedStops.record(
      routeStopId: release.routeStopId,
      releaseReason: release.releaseReason,
      appealable: release.appealable,
    );
    await _store.markStopReleased(
      row.id,
      routeStopId: release.routeStopId,
      error: release.toString(),
    );
    if (firstTime) _reportStopReleased(release);
    return _Dispatched.blocked;
  }

  /// Best-effort, like [_reportScanDelivered]: the row is parked already.
  void _reportStopReleased(StopRelease release) {
    try {
      _onStopReleased?.call(release);
      // Deliberately broad, for the reason in _reportScanDelivered.
      // ignore: avoid_catches_without_on_clauses
    } catch (error, stack) {
      developer.log(
        jsonEncode({
          'event': 'stop_release_report_failed',
          'route_stop_id': release.routeStopId,
          'error': '$error',
        }),
        name: 'sync_worker',
        stackTrace: stack,
      );
    }
  }

  /// Best-effort: the row is already synced, and a failing listener (e.g. a
  /// disposed Riverpod ref) must neither un-sync it nor stop the pass.
  void _reportScanDelivered(PendingOperationRow row) {
    final isScan =
        row.kind == PendingOpKind.checkIn || row.kind == PendingOpKind.checkOut;
    if (!isScan) return;
    try {
      _onScanDelivered?.call(
        DateTime.parse(row.payload['scanned_at'] as String),
      );
      // Deliberately broad, for the reason above.
      // ignore: avoid_catches_without_on_clauses
    } catch (error, stack) {
      developer.log(
        jsonEncode({
          'event': 'scan_delivery_report_failed',
          'operation_id': row.id,
          'error': '$error',
        }),
        name: 'sync_worker',
        stackTrace: stack,
      );
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
      complaintsSuggestions: payload['complaints_suggestions'] as String?,
      // LEGACY: a row queued by an old build may still carry form fields in
      // its payload; they are deliberately not read, so the server never
      // receives them (forms were removed).
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
