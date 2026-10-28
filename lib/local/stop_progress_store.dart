import 'package:drift/drift.dart';
import 'package:route_monitor/local/app_database.dart';

/// Local lifecycle of a stop the field worker has acted on (spec §6.3b
/// Ruling 17). `GET /routes/me`'s `RouteStopOut` carries no `execution_id`,
/// and the worker has no access to the MANAGER/ADMIN-only `GET /executions`,
/// so the app remembers what the check-in/check-out responses told it.
///
/// `.name` here is NOT what lands in the column — the `local_status` column
/// stores `'IN_PROGRESS'` / `'STAMPED'` / `'DONE'`, so the mapping is explicit
/// in `_statusColumn` / `_statusFromColumn`.
///
/// `stamped` is a task the worker finished on its floor (photos and note
/// taken) whose check-out has not been made yet.
enum StopLocalStatus { inProgress, stamped, done }

/// A decoded `StopProgress` row, free of any Drift type.
class StopProgressEntry {
  const StopProgressEntry({
    required this.routeStopId,
    required this.executionId,
    required this.status,
    required this.updatedAt,
    this.observation,
  });

  final String routeStopId;
  final String executionId;
  final StopLocalStatus status;

  /// Last local change to the row (check-in or check-out time).
  final DateTime updatedAt;

  /// The note left when the task was stamped; null when none.
  final String? observation;
}

/// One row per stop the worker touched: written `inProgress` on check-in
/// success, flipped to `done` on check-out success (spec Ruling 3 — check-out
/// no longer deletes the row, it marks it DONE).
abstract class StopProgressStore {
  Future<void> upsertInProgress(String routeStopId, String executionId);

  /// Flips the stop to `stamped`, keeping [observation] (the worker's note,
  /// possibly null) and bumping `updatedAt`. No-op for an untouched stop.
  Future<void> markStamped(String routeStopId, {String? observation});

  Future<void> markDone(String routeStopId);

  /// Null both for an untouched stop and for the accepted cold-start gap
  /// (Ruling 17): a stop that turned `IN_PROGRESS` before this table existed
  /// has no row to find.
  Future<StopProgressEntry?> progressFor(String routeStopId);

  /// Every stored row whose `routeStopId` is in [routeStopIds].
  Future<List<StopProgressEntry>> allForRoute(Iterable<String> routeStopIds);
}

class DriftStopProgressStore implements StopProgressStore {
  DriftStopProgressStore(this._db);

  final AppDatabase _db;

  @override
  Future<void> upsertInProgress(String routeStopId, String executionId) {
    // insertOnConflictUpdate: a stop only ever has one execution, but a
    // re-check-in edge case (a retried attempt after a flaky mark) must
    // overwrite rather than throw on the existing primary key.
    return _db
        .into(_db.stopProgress)
        .insertOnConflictUpdate(
          StopProgressCompanion.insert(
            routeStopId: routeStopId,
            executionId: executionId,
            localStatus: _statusColumn(StopLocalStatus.inProgress),
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  @override
  Future<void> markStamped(String routeStopId, {String? observation}) {
    final update = _db.update(_db.stopProgress)
      ..where((row) => row.routeStopId.equals(routeStopId));
    return update.write(
      StopProgressCompanion(
        localStatus: Value(_statusColumn(StopLocalStatus.stamped)),
        observation: Value(observation),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  @override
  Future<void> markDone(String routeStopId) {
    final update = _db.update(_db.stopProgress)
      ..where((row) => row.routeStopId.equals(routeStopId));
    return update.write(
      StopProgressCompanion(
        localStatus: Value(_statusColumn(StopLocalStatus.done)),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  @override
  Future<StopProgressEntry?> progressFor(String routeStopId) async {
    final row = await (_db.select(
      _db.stopProgress,
    )..where((row) => row.routeStopId.equals(routeStopId))).getSingleOrNull();
    return row == null ? null : _toEntry(row);
  }

  @override
  Future<List<StopProgressEntry>> allForRoute(
    Iterable<String> routeStopIds,
  ) async {
    final ids = routeStopIds.toList();
    if (ids.isEmpty) return const [];
    final rows = await (_db.select(
      _db.stopProgress,
    )..where((row) => row.routeStopId.isIn(ids))).get();
    return rows.map(_toEntry).toList();
  }

  StopProgressEntry _toEntry(StopProgressData row) {
    return StopProgressEntry(
      routeStopId: row.routeStopId,
      executionId: row.executionId,
      status: _statusFromColumn(row.localStatus),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
      observation: row.observation,
    );
  }

  static String _statusColumn(StopLocalStatus status) {
    return switch (status) {
      StopLocalStatus.inProgress => 'IN_PROGRESS',
      StopLocalStatus.stamped => 'STAMPED',
      StopLocalStatus.done => 'DONE',
    };
  }

  static StopLocalStatus _statusFromColumn(String value) {
    return switch (value) {
      'IN_PROGRESS' => StopLocalStatus.inProgress,
      'STAMPED' => StopLocalStatus.stamped,
      'DONE' => StopLocalStatus.done,
      _ => throw ArgumentError.value(
        value,
        'local_status',
        'expected "IN_PROGRESS", "STAMPED" or "DONE"',
      ),
    };
  }
}
