import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/released_stop_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
import 'package:route_monitor/sync/blocked_scope.dart';
import 'package:route_monitor/sync/connectivity.dart';
import 'package:route_monitor/sync/outbox_row_sender.dart';
import 'package:route_monitor/sync/stop_release.dart';
import 'package:route_monitor/sync/sync_error_class.dart';
import 'package:route_monitor/sync/sync_progress.dart';
import 'package:route_monitor/sync/sync_status.dart';

export 'package:route_monitor/sync/sync_error_class.dart' show SyncErrorClass;

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
  final SyncMetaStore _syncMeta;
  final Connectivity _connectivity;
  late final OutboxRowSender _sender = OutboxRowSender(
    executionApi: _executionApi,
    evidenceApi: _evidenceApi,
    stopProgress: _stopProgress,
    syncMeta: _syncMeta,
  );
  final StopProgressStore _stopProgress;
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

  // Sync: every row is heard before `syncAll` returns (background drain).
  final StreamController<SyncProgress> _progress =
      StreamController<SyncProgress>.broadcast(sync: true);

  /// The `syncAll` in flight, if any — what a delivered row advances.
  SyncProgressRun? _run;

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
      final rows = await _store.dueForRoute(
        routeId,
        now: _now().millisecondsSinceEpoch,
      );
      final scope = await _scopeFor(routeId, rows);
      for (final row in rows) {
        if (scope.holds(row)) continue;
        // Not claimed: the other isolate took it a moment ago — it is in
        // flight, so hold what depends on it, like a not-due row.
        if (!await _claim(row)) {
          scope.add(row);
          continue;
        }
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

  /// What this pass must hold back: dependents of `blocked` rows, and of
  /// every unsent row that is not [due] — a `sending` row another worker
  /// holds under a live lease, or a `failed` one still in its backoff. Their
  /// check-out or evidence must not reach the server ahead of them.
  Future<BlockedScope> _scopeFor(
    String routeId,
    List<PendingOperationRow> due,
  ) async {
    final scope = BlockedScope(await _store.blockedForRoute(routeId));
    final dueIds = {for (final row in due) row.id};
    for (final row in await _store.unsyncedForRoute(routeId)) {
      // A `held` photo waits for its stamp, not for a worker: it holds
      // nothing back.
      if (row.state == PendingOpState.held) continue;
      if (!dueIds.contains(row.id)) scope.add(row);
    }
    return scope;
  }

  /// How long a claimed row stays the claimant's (`PendingOpState.sending`).
  /// A send is at most three requests (the call, a token refresh, the retry)
  /// bounded by `api_client.dart`'s timeouts: a photo upload is 20 s connect
  /// + 180 s send + 60 s receive = 260 s, any other request 140 s, so the
  /// worst case (photo, refresh, photo) is 660 s = 11 min. 15 min keeps the
  /// other isolate from re-sending a row still in flight; a worker killed
  /// mid-send frees its row after the lease.
  static const Duration sendLease = Duration(minutes: 15);

  Future<bool> _claim(PendingOperationRow row) {
    final now = _now().millisecondsSinceEpoch;
    return _store.claim(
      row.id,
      now: now,
      leaseUntil: now + sendLease.inMilliseconds,
    );
  }

  /// Drains every route that has queued work. A route that blocks does not
  /// stop the others.
  Future<void> syncAll() async {
    final routeIds = await _store.routeIdsWithWork();
    final now = _now().millisecondsSinceEpoch;
    final total = await countDeliverable(_store, routeIds, now: now);
    final run = SyncProgressRun(total, _emitProgress);
    _run = run;
    run.start();
    try {
      for (final routeId in routeIds) {
        await syncRoute(routeId);
      }
    } finally {
      if (identical(_run, run)) _run = null;
    }
  }

  /// Rows delivered during [syncAll], out of those due when it started
  /// (redesign §6.9); `worker.progress.listen((p) => show(p.done, p.total))`.
  Stream<SyncProgress> get progress => _progress.stream;

  void _emitProgress(SyncProgress progress) {
    if (!_progress.isClosed) _progress.add(progress);
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
    await _progress.close();
  }

  /// Dispatches one row and says where it ended. A synced scan is reported
  /// only once the row's state is final, so the report can never change it.
  Future<_Dispatched> _dispatch(PendingOperationRow row) async {
    final _Dispatched outcome;
    try {
      outcome = await _attempt(row);
      // A store write failed while settling the row: give the claim back so
      // the row is not stranded in `sending` for the whole lease. Rethrown,
      // so catching everything here hides nothing.
    } catch (_) {
      await _releaseClaimQuietly(row);
      rethrow;
    }
    if (outcome != _Dispatched.synced) return outcome;
    _reportScanDelivered(row);
    _run?.advance();
    return outcome;
  }

  Future<_Dispatched> _attempt(PendingOperationRow row) async {
    try {
      final serverDate = await _sender.send(row);
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
      final classification = classifySyncError(error);
      if (classification == SyncErrorClass.alreadyApplied) {
        // The server had it already — and counted its scan then.
        await _store.markSynced(row.id);
        return _Dispatched.synced;
      }
      if (classification == SyncErrorClass.awaitingAuth) {
        await _store.releaseClaim(row);
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

  Future<void> _releaseClaimQuietly(PendingOperationRow row) async {
    try {
      await _store.releaseClaim(row);
      // Deliberately broad: the original failure is what must surface.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      developer.log(
        jsonEncode({
          'event': 'claim_release_failed',
          'operation_id': row.id,
          'error': '$error',
        }),
        name: 'sync_worker',
      );
    }
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

  Future<void> _recordOffset(DateTime? serverDate) async {
    if (serverDate == null) return;
    final offsetSeconds = serverDate.difference(_now()).inMilliseconds / 1000.0;
    await _syncMeta.setClockOffsetSeconds(offsetSeconds);
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
