import 'package:route_monitor/local/app_database.dart';

/// Tracks the `execution_id` behind each `IN_PROGRESS` stop (spec §6.3b
/// Ruling 17): `GET /routes/me`'s `RouteStopOut` carries no `execution_id`,
/// and the field worker has no access to the MANAGER/ADMIN-only
/// `GET /executions`, so the app remembers what the check-in/check-out
/// responses already told it. One row per stop, written on check-in success,
/// deleted on check-out success.
abstract class OpenExecutionStore {
  Future<void> recordOpenExecution(String routeStopId, String executionId);

  Future<void> clearOpenExecution(String routeStopId);

  /// Null both for a stop with no open execution and for the accepted
  /// cold-start gap (Ruling 17): a stop that turned `IN_PROGRESS` before
  /// this table existed has no row to find.
  Future<String?> openExecutionFor(String routeStopId);
}

class DriftOpenExecutionStore implements OpenExecutionStore {
  DriftOpenExecutionStore(this._db);

  final AppDatabase _db;

  @override
  Future<void> recordOpenExecution(String routeStopId, String executionId) {
    // insertOnConflictUpdate: a stop only ever has one open execution, but a
    // re-check-in edge case (e.g. a retried attempt after a flaky mark) must
    // overwrite rather than throw on the existing primary key.
    return _db
        .into(_db.openExecutions)
        .insertOnConflictUpdate(
          OpenExecutionsCompanion.insert(
            routeStopId: routeStopId,
            executionId: executionId,
          ),
        );
  }

  @override
  Future<void> clearOpenExecution(String routeStopId) {
    return (_db.delete(
      _db.openExecutions,
    )..where((row) => row.routeStopId.equals(routeStopId))).go();
  }

  @override
  Future<String?> openExecutionFor(String routeStopId) async {
    final row = await (_db.select(
      _db.openExecutions,
    )..where((row) => row.routeStopId.equals(routeStopId))).getSingleOrNull();
    return row?.executionId;
  }
}
