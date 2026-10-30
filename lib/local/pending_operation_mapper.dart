import 'dart:convert';

import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/pending_operation.dart';

/// The decoded [PendingOperationRow] of a stored `PendingOperations` row: the
/// `kind` and `state` columns hold `.name`s, the payload is JSON.
///
///     final rows = (await query.get()).map(pendingOperationRowOf);
PendingOperationRow pendingOperationRowOf(PendingOperation row) {
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
