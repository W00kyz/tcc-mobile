import 'package:drift/drift.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/pending_operation.dart';
import 'package:route_monitor/local/pending_operation_mapper.dart';

/// The ids, oldest first, of [executionId]'s outbox rows of [kinds] in
/// [states]. The execution id lives inside the JSON payload, so it is matched
/// here rather than in SQL.
///
///     await evidenceIdsOf(db, 'e1', kinds: [PendingOpKind.evidencePhoto],
///         states: [PendingOpState.held]);
Future<List<String>> evidenceIdsOf(
  AppDatabase db,
  String executionId, {
  required List<PendingOpKind> kinds,
  required List<PendingOpState> states,
}) async {
  final query = db.select(db.pendingOperations)
    ..where(
      (row) =>
          row.kind.isIn([for (final kind in kinds) kind.name]) &
          row.state.isIn([for (final state in states) state.name]),
    )
    ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]);
  final rows = await query.get();
  return [
    for (final row in rows.map(pendingOperationRowOf))
      if (row.payload['execution_id'] == executionId) row.id,
  ];
}

/// The larger of the outbox's newest `createdAt` and the clock: where the
/// next row to join the queue's tail goes.
Future<int> tailCreatedAt(AppDatabase db) async {
  final newest = db.pendingOperations.createdAt.max();
  final query = db.selectOnly(db.pendingOperations)..addColumns([newest]);
  final stored = (await query.getSingle()).read(newest) ?? 0;
  final now = DateTime.now().millisecondsSinceEpoch;
  return stored > now ? stored : now;
}
