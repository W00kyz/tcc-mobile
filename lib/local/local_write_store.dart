import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:route_monitor/local/app_database.dart';

/// The kind of execution write buffered in [PendingOperations].
///
/// The `.name` of each value is what lands in the `kind` column, so renaming a
/// value is a schema-visible change.
enum PendingOpKind { checkIn, checkOut, evidencePhoto, evidenceNote }

/// Drain state of a buffered write. `.name` is persisted in the `state` column.
enum PendingOpState { pending, synced, failed }

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
  });

  final String id;
  final PendingOpKind kind;
  final String routeId;
  final Map<String, dynamic> payload;
  final int createdAt;
  final PendingOpState state;
  final String? lastError;
}

/// The write seam: execution actions enqueue here first, then a drain marks
/// each row synced or failed (Ruling 1, Etapa 5 design §4.1 / §6.1).
abstract class LocalWriteStore {
  Future<void> enqueue({
    required String id,
    required PendingOpKind kind,
    required Map<String, dynamic> payload,
    required String routeId,
  });

  Future<void> markSynced(String id);

  Future<void> markFailed(String id, String error);

  /// Rows for [routeId] still owed to the network — `pending` and `failed` —
  /// oldest first, so the drain replays them in the order they were made.
  Future<List<PendingOperationRow>> unsyncedForRoute(String routeId);
}

class DriftLocalWriteStore implements LocalWriteStore {
  DriftLocalWriteStore(this._db);

  final AppDatabase _db;

  @override
  Future<void> enqueue({
    required String id,
    required PendingOpKind kind,
    required Map<String, dynamic> payload,
    required String routeId,
  }) {
    // insertOrIgnore: `id` is the idempotency key, so re-enqueuing the same
    // operation (e.g. the drain retries after a flaky failure) must not throw
    // and must not clobber a row that already reached `synced`.
    return _db
        .into(_db.pendingOperations)
        .insert(
          PendingOperationsCompanion.insert(
            id: id,
            kind: kind.name,
            routeId: routeId,
            payloadJson: jsonEncode(payload),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  @override
  Future<void> markSynced(String id) => _setState(id, PendingOpState.synced);

  @override
  Future<void> markFailed(String id, String error) =>
      _setState(id, PendingOpState.failed, error: error);

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
      ),
    );
  }

  @override
  Future<List<PendingOperationRow>> unsyncedForRoute(String routeId) async {
    final query = _db.select(_db.pendingOperations)
      ..where(
        (row) =>
            row.routeId.equals(routeId) &
            row.state.isIn([
              PendingOpState.pending.name,
              PendingOpState.failed.name,
            ]),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]);
    final rows = await query.get();
    return rows.map(_toRow).toList();
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
    );
  }
}
