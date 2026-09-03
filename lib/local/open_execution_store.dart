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
    //
    // Schema 3 (Etapa 6): `OpenExecutions` was folded into `StopProgress`. This
    // store still speaks the Ruling 17 vocabulary; Task 5 replaces it with a
    // `StopProgressStore` that also tracks the `DONE` transition.
    return _db
        .into(_db.stopProgress)
        .insertOnConflictUpdate(
          StopProgressCompanion.insert(
            routeStopId: routeStopId,
            executionId: executionId,
            localStatus: 'IN_PROGRESS',
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  @override
  Future<void> clearOpenExecution(String routeStopId) {
    return (_db.delete(
      _db.stopProgress,
    )..where((row) => row.routeStopId.equals(routeStopId))).go();
  }

  @override
  Future<String?> openExecutionFor(String routeStopId) async {
    final row = await (_db.select(
      _db.stopProgress,
    )..where((row) => row.routeStopId.equals(routeStopId))).getSingleOrNull();
    return row?.executionId;
  }
}
