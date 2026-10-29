import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/pending_operation.dart';

export 'package:route_monitor/local/pending_operation.dart';

/// The states a sync worker may pick up: `held` is owed to the network but
/// not yet cleared to leave.
const List<PendingOpState> _sendableStates = [
  PendingOpState.pending,
  PendingOpState.failed,
  PendingOpState.sending,
];

/// The states still owed to the network.
const List<PendingOpState> _unsentStates = [
  ..._sendableStates,
  PendingOpState.held,
];

/// The write seam: execution actions enqueue here first, then a drain marks
/// each row synced or failed (Ruling 1, Etapa 5 design §4.1 / §6.1).
abstract class LocalWriteStore {
  /// True when the row was written; false when a row with [id] already
  /// existed (the same idempotency key enqueued twice), which changes nothing.
  /// [initialState] is `held` for a photo that must wait for its stamp.
  Future<bool> enqueue({
    required String id,
    required PendingOpKind kind,
    required Map<String, dynamic> payload,
    required String routeId,
    PendingOpState initialState = PendingOpState.pending,
  });

  Future<void> markSynced(String id);

  Future<void> markFailed(String id, String error);

  /// Retry budget exhausted (spec Ruling 6): move the row to `blocked` so the
  /// worker stops replaying it and the UI can surface it for manual action.
  Future<void> markBlocked(String id, String error);

  /// A `409 STOP_RELEASED`: blocks the row like [markBlocked] and records the
  /// released stop the server named — the row waits for the appeal flow
  /// (spec 2026-10-20-alocacao-automatica §7.5), its payload kept.
  Future<void> markStopReleased(
    String id, {
    required String routeStopId,
    required String error,
  });

  /// Records a scheduled retry: bumps [attempts] and defers the next attempt
  /// until [nextAttemptAt] (epoch millis), leaving the row `failed`/`pending`
  /// so [dueForRoute] picks it up once the clock passes that mark.
  Future<void> markRetryScheduled(
    String id, {
    required int attempts,
    required int nextAttemptAt,
  });

  /// Rows for [routeId] still owed to the network — `pending`, `failed`,
  /// `sending` and `held` — oldest first, so the drain replays them in the
  /// order they were made.
  Future<List<PendingOperationRow>> unsyncedForRoute(String routeId);

  /// How many evidence photos the outbox holds for [executionId], in EVERY
  /// state: `synced` rows stay in SQLite after delivery, and `failed` /
  /// `blocked` ones are still photos the worker took. `held` ones count too:
  /// a photo waiting for its stamp is already part of the evidence. This is
  /// the on-device truth behind the "Concluir" gate and the photo cap, valid
  /// offline.
  Future<int> localPhotoCountFor(String executionId);

  /// `blocked` rows for [routeId], oldest first — the manual-attention list.
  Future<List<PendingOperationRow>> blockedForRoute(String routeId);

  /// Rows for [routeId] the worker may attempt right now: `pending`/`failed`
  /// with `nextAttemptAt` null or `<= now`, or `sending` with an expired
  /// lease, oldest `createdAt` first.
  Future<List<PendingOperationRow>> dueForRoute(
    String routeId, {
    required int now,
  });

  /// Takes due row [id] for one send, until [leaseUntil] (epoch millis):
  /// true only for the one caller whose atomic UPDATE moved it to `sending`.
  /// A `pending`/`failed` row past its backoff, or a `sending` row whose
  /// lease ended by [now], can be claimed.
  Future<bool> claim(String id, {required int now, required int leaseUntil});

  /// Gives back a claim on [row] without an outcome (the session expired):
  /// its state and `nextAttemptAt` return to what [row] held — `pending`
  /// with no backoff if it was a reclaimed `sending` row.
  Future<void> releaseClaim(PendingOperationRow row);

  /// Distinct route ids with any `pending`, `failed`, `sending` or `blocked`
  /// row — the set of routes the sync worker still has work for.
  Future<List<String>> routeIdsWithWork();

  /// Clears a `blocked` (or `failed`) row back to a clean `pending` state —
  /// state `pending`, `attempts` 0, `nextAttemptAt`/`lastError`/
  /// `releasedStopId` null — so the next drain replays it from scratch.
  /// Backs `SyncWorker.unblock` (the "Tentar de novo" button on the
  /// blocked-rows list, spec Ruling 6).
  Future<void> resetToPending(String id);

  /// Moves every `held` photo of [executionId] to `pending`, so the next
  /// drain sends it; returns how many it released.
  Future<int> releaseHeldPhotos(String executionId);

  /// Deletes every `held` photo of [executionId] (the task was abandoned);
  /// returns how many it removed.
  Future<int> discardHeldPhotos(String executionId);

  /// Deletes [operationId] only if it is an `evidencePhoto` row not yet
  /// delivered and not in flight (`pending`, `failed`, `held` or `blocked`);
  /// returns whether it did. A `synced` or `sending` row, or a non-photo one,
  /// is left untouched and yields `false`.
  Future<bool> deletePendingPhoto(String operationId);

  /// The `route_stop_id` of every `STOP`-scope impediment row of [routeId], in
  /// any state (a delivered one included), re-emitted whenever the outbox
  /// changes. An impeded task is drawn as such from the tap on, long before
  /// the server releases the stop.
  Stream<Set<String>> watchImpededStopIds(String routeId);
}

class DriftLocalWriteStore implements LocalWriteStore {
  DriftLocalWriteStore(this._db);

  final AppDatabase _db;

  @override
  Future<bool> enqueue({
    required String id,
    required PendingOpKind kind,
    required Map<String, dynamic> payload,
    required String routeId,
    PendingOpState initialState = PendingOpState.pending,
  }) async {
    // insertOrIgnore: `id` is the idempotency key, so re-enqueuing the same
    // operation (e.g. the drain retries after a flaky failure) must not throw
    // and must not clobber a row that already reached `synced`. The
    // RETURNING row is null exactly when the insert was ignored.
    final inserted = await _db
        .into(_db.pendingOperations)
        .insertReturningOrNull(
          PendingOperationsCompanion.insert(
            id: id,
            kind: kind.name,
            routeId: routeId,
            payloadJson: jsonEncode(payload),
            createdAt: DateTime.now().millisecondsSinceEpoch,
            state: Value(initialState.name),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return inserted != null;
  }

  @override
  Future<void> markSynced(String id) => _setState(id, PendingOpState.synced);

  @override
  Future<void> markFailed(String id, String error) =>
      _setState(id, PendingOpState.failed, error: error);

  @override
  Future<void> markBlocked(String id, String error) =>
      _setState(id, PendingOpState.blocked, error: error);

  @override
  Future<void> markStopReleased(
    String id, {
    required String routeStopId,
    required String error,
  }) {
    final update = _db.update(_db.pendingOperations)
      ..where((row) => row.id.equals(id));
    return update.write(
      PendingOperationsCompanion(
        state: Value(PendingOpState.blocked.name),
        lastError: Value(error),
        releasedStopId: Value(routeStopId),
        nextAttemptAt: const Value(null),
      ),
    );
  }

  @override
  Future<void> markRetryScheduled(
    String id, {
    required int attempts,
    required int nextAttemptAt,
  }) {
    final update = _db.update(_db.pendingOperations)
      ..where((row) => row.id.equals(id));
    return update.write(
      PendingOperationsCompanion(
        attempts: Value(attempts),
        nextAttemptAt: Value(nextAttemptAt),
      ),
    );
  }

  @override
  Future<void> resetToPending(String id) {
    final update = _db.update(_db.pendingOperations)
      ..where((row) => row.id.equals(id));
    return update.write(
      PendingOperationsCompanion(
        state: Value(PendingOpState.pending.name),
        lastError: const Value(null),
        attempts: const Value(0),
        nextAttemptAt: const Value(null),
        releasedStopId: const Value(null),
      ),
    );
  }

  @override
  Future<bool> deletePendingPhoto(String operationId) async {
    final delete = _db.delete(_db.pendingOperations)
      ..where(
        (row) =>
            row.id.equals(operationId) &
            row.kind.equals(PendingOpKind.evidencePhoto.name) &
            row.state.isIn([
              PendingOpState.pending.name,
              PendingOpState.failed.name,
              PendingOpState.held.name,
              // A blocked photo waits for the worker: dropping it is one of
              // the ways out (final review I-1).
              PendingOpState.blocked.name,
            ]),
      );
    return await delete.go() > 0;
  }

  @override
  Future<int> releaseHeldPhotos(String executionId) async {
    final ids = await _heldPhotoIds(executionId);
    if (ids.isEmpty) return 0;
    // Re-checked here: a row that left `held` since the read above (sent,
    // deleted, blocked) must not be flipped back to `pending`.
    final update = _db.update(_db.pendingOperations)
      ..where(
        (row) => row.id.isIn(ids) & row.state.equals(PendingOpState.held.name),
      );
    return update.write(
      PendingOperationsCompanion(state: Value(PendingOpState.pending.name)),
    );
  }

  @override
  Future<int> discardHeldPhotos(String executionId) async {
    final ids = await _heldPhotoIds(executionId);
    if (ids.isEmpty) return 0;
    return (_db.delete(
      _db.pendingOperations,
    )..where((row) => row.id.isIn(ids))).go();
  }

  @override
  Stream<Set<String>> watchImpededStopIds(String routeId) {
    final query = _db.select(_db.pendingOperations)
      ..where(
        (row) =>
            row.routeId.equals(routeId) &
            row.kind.equals(PendingOpKind.impediment.name),
      );
    return query.watch().map(
      (rows) => {
        for (final row in rows.map(_toRow))
          if (row.payload['scope'] == 'STOP')
            if (row.payload['route_stop_id'] case final String stopId) stopId,
      },
    );
  }

  /// The ids of [executionId]'s `held` photos. The execution id lives inside
  /// the JSON payload, so it is matched here rather than in SQL.
  Future<List<String>> _heldPhotoIds(String executionId) async {
    final query = _db.select(_db.pendingOperations)
      ..where(
        (row) =>
            row.kind.equals(PendingOpKind.evidencePhoto.name) &
            row.state.equals(PendingOpState.held.name),
      );
    final rows = await query.get();
    return [
      for (final row in rows.map(_toRow))
        if (row.payload['execution_id'] == executionId) row.id,
    ];
  }

  @override
  Future<bool> claim(
    String id, {
    required int now,
    required int leaseUntil,
  }) async {
    // One UPDATE with the "still due" test in its WHERE: SQLite runs it
    // atomically across connections, so of two workers racing for the same
    // row exactly one sees a row change.
    final update = _db.update(_db.pendingOperations)
      ..where((row) => row.id.equals(id) & _dueAt(row, now));
    final changed = await update.write(
      PendingOperationsCompanion(
        state: Value(PendingOpState.sending.name),
        nextAttemptAt: Value(leaseUntil),
      ),
    );
    return changed == 1;
  }

  @override
  Future<void> releaseClaim(PendingOperationRow row) {
    final wasClaimed = row.state == PendingOpState.sending;
    final update = _db.update(_db.pendingOperations)
      ..where(
        (stored) =>
            stored.id.equals(row.id) &
            stored.state.equals(PendingOpState.sending.name),
      );
    return update.write(
      PendingOperationsCompanion(
        state: Value((wasClaimed ? PendingOpState.pending : row.state).name),
        nextAttemptAt: Value(wasClaimed ? null : row.nextAttemptAt),
      ),
    );
  }

  /// Due at [now]: `pending`/`failed` past its backoff, or `sending` past
  /// its lease (both live in `nextAttemptAt`).
  Expression<bool> _dueAt($PendingOperationsTable row, int now) =>
      row.state.isIn([for (final state in _sendableStates) state.name]) &
      (row.nextAttemptAt.isNull() |
          row.nextAttemptAt.isSmallerOrEqualValue(now));

  Future<void> _setState(
    String id,
    PendingOpState state, {
    String? error,
  }) {
    final update = _db.update(_db.pendingOperations)
      ..where((row) => row.id.equals(id));
    return update.write(
      PendingOperationsCompanion(
        state: Value(state.name),
        lastError: Value(error),
        // A settled row drops the send lease; a `failed` one keeps it until
        // `markRetryScheduled` sets its backoff right after.
        nextAttemptAt: state == PendingOpState.failed
            ? const Value.absent()
            : const Value(null),
      ),
    );
  }

  @override
  Future<List<PendingOperationRow>> unsyncedForRoute(String routeId) async {
    final query = _db.select(_db.pendingOperations)
      ..where(
        (row) =>
            row.routeId.equals(routeId) &
            row.state.isIn([for (final state in _unsentStates) state.name]),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]);
    final rows = await query.get();
    return rows.map(_toRow).toList();
  }

  @override
  Future<int> localPhotoCountFor(String executionId) async {
    final query = _db.select(_db.pendingOperations)
      ..where((row) => row.kind.equals(PendingOpKind.evidencePhoto.name));
    final rows = await query.get();
    // The execution id lives inside the JSON payload, so it is matched here
    // rather than in SQL; photos are few per device and day.
    return rows
        .map(_toRow)
        .where((row) => row.payload['execution_id'] == executionId)
        .length;
  }

  @override
  Future<List<PendingOperationRow>> blockedForRoute(String routeId) async {
    final query = _db.select(_db.pendingOperations)
      ..where(
        (row) =>
            row.routeId.equals(routeId) &
            row.state.equals(PendingOpState.blocked.name),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]);
    final rows = await query.get();
    return rows.map(_toRow).toList();
  }

  @override
  Future<List<PendingOperationRow>> dueForRoute(
    String routeId, {
    required int now,
  }) async {
    final query = _db.select(_db.pendingOperations)
      ..where(
        (row) => row.routeId.equals(routeId) & _dueAt(row, now),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]);
    final rows = await query.get();
    return rows.map(_toRow).toList();
  }

  @override
  Future<List<String>> routeIdsWithWork() async {
    final routeId = _db.pendingOperations.routeId;
    final query = _db.selectOnly(_db.pendingOperations, distinct: true)
      ..addColumns([routeId])
      ..where(
        _db.pendingOperations.state.isIn([
          for (final state in _unsentStates) state.name,
          PendingOpState.blocked.name,
        ]),
      );
    final rows = await query.get();
    return rows.map((row) => row.read(routeId)!).toList();
  }

  PendingOperationRow _toRow(PendingOperation row) {
    return PendingOperationRow(
      id: row.id,
      kind: PendingOpKind.values.byName(row.kind),
      routeId: row.routeId,
      payload: jsonDecode(row.payloadJson) as Map<String, dynamic>,
      createdAt: row.createdAt,
      state: PendingOpState.values.byName(row.state),
      lastError: row.lastError,
      attempts: row.attempts,
      nextAttemptAt: row.nextAttemptAt,
      releasedStopId: row.releasedStopId,
    );
  }
}
