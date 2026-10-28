import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:route_monitor/local/app_database.dart';

/// The kind of execution write buffered in [PendingOperations].
///
/// The `.name` of each value is what lands in the `kind` column, so renaming a
/// value is a schema-visible change.
enum PendingOpKind {
  checkIn,
  checkOut,
  evidencePhoto,
  evidenceNote,
  impediment,
}

/// Drain state of a buffered write. `.name` is persisted in the `state` column.
///
/// `blocked` is a terminal-until-manual state (spec Ruling 6): the sync worker
/// gave up on this row after exhausting its retry budget, and it stays put
/// until the field worker acts on it.
///
/// `sending` is a claim: one sync worker took the row for one send, until
/// the lease in `nextAttemptAt`. The app and the background drain open the
/// file on two connections, and only the claim keeps them from both sending
/// it (redesign §6.9). A lease that expired (a worker killed mid-send) makes
/// the row due again; nothing resets `sending` on startup, since the other
/// isolate may still be mid-send.
enum PendingOpState { pending, synced, failed, blocked, sending }

/// The states still owed to the network.
const List<PendingOpState> _unsentStates = [
  PendingOpState.pending,
  PendingOpState.failed,
  PendingOpState.sending,
];

/// A decoded [PendingOperations] row, free of any Drift type so callers
/// (Task 17's `ExecutionRepository` and up) never import drift.
class PendingOperationRow {
  const PendingOperationRow({
    required this.id,
    required this.kind,
    required this.routeId,
    required this.payload,
    required this.createdAt,
    required this.state,
    required this.lastError,
    required this.attempts,
    required this.nextAttemptAt,
    this.releasedStopId,
  });

  final String id;
  final PendingOpKind kind;
  final String routeId;
  final Map<String, dynamic> payload;
  final int createdAt;
  final PendingOpState state;
  final String? lastError;

  /// How many sync attempts this row has already burned (spec Ruling 6).
  final int attempts;

  /// Epoch milliseconds before which the worker must not retry this row, or
  /// null when it is due immediately.
  final int? nextAttemptAt;

  /// The released stop a `409 STOP_RELEASED` parked this row on, or null.
  /// A parked row is never retried: the appeal flow (or discarding the
  /// stop's local data) is what clears it.
  final String? releasedStopId;
}

/// The write seam: execution actions enqueue here first, then a drain marks
/// each row synced or failed (Ruling 1, Etapa 5 design §4.1 / §6.1).
abstract class LocalWriteStore {
  /// True when the row was written; false when a row with [id] already
  /// existed (the same idempotency key enqueued twice), which changes nothing.
  Future<bool> enqueue({
    required String id,
    required PendingOpKind kind,
    required Map<String, dynamic> payload,
    required String routeId,
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

  /// Rows for [routeId] still owed to the network — `pending`, `failed` and
  /// `sending` — oldest first, so the drain replays them in the order they
  /// were made.
  Future<List<PendingOperationRow>> unsyncedForRoute(String routeId);

  /// How many evidence photos the outbox holds for [executionId], in EVERY
  /// state: `synced` rows stay in SQLite after delivery, and `failed` /
  /// `blocked` ones are still photos the worker took. This is the on-device
  /// truth behind the "Concluir" gate and the photo cap, valid offline.
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

  /// Deletes [operationId] only if it is an `evidencePhoto` row not yet
  /// delivered (`pending` or `failed`); returns whether it did. A synced,
  /// blocked or non-photo row is left untouched and yields `false`.
  Future<bool> deletePendingPhoto(String operationId);
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
            ]),
      );
    return await delete.go() > 0;
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
      row.state.isIn([for (final state in _unsentStates) state.name]) &
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
