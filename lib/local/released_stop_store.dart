import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart' show PendingOpKind;

/// A decoded [ReleasedStops] row, free of any Drift type: a stop the server
/// released while this device still had writes for it.
class ReleasedStopNotice {
  const ReleasedStopNotice({
    required this.routeStopId,
    required this.releaseReason,
    required this.appealable,
    required this.localCheckInAt,
    required this.localCheckOutAt,
    required this.createdAt,
  });

  final String routeStopId;

  /// The server's `release_reason` code.
  final String releaseReason;

  /// The server's verdict when the 409 came back: whether the worker may
  /// appeal (spec 2026-10-20-alocacao-automatica §7.5).
  final bool appealable;

  /// The device time of the stop's check-in — what the appeal declares by
  /// default — or null when this device never checked in there.
  final DateTime? localCheckInAt;
  final DateTime? localCheckOutAt;
  final DateTime createdAt;
}

/// The device's record of its released stops and the data parked on them
/// (spec 2026-10-20-alocacao-automatica §7.5): the sync worker records a
/// stop on its first `409 STOP_RELEASED`; sending the appeal, or the worker
/// giving up on the stop, discards everything the device held for it.
///
///     if (await store.record(routeStopId: id, releaseReason: r,
///         appealable: true)) { /* first time: tell the worker */ }
abstract class ReleasedStopStore {
  /// Records [routeStopId] with the local check-in/check-out times its
  /// outbox rows hold. Returns false — writing nothing — when the stop was
  /// already recorded: the first 409 of a stop is the one that counts.
  Future<bool> record({
    required String routeStopId,
    required String releaseReason,
    required bool appealable,
  });

  Future<ReleasedStopNotice?> noticeFor(String routeStopId);

  /// The recorded stops the worker may appeal, oldest first.
  Future<List<ReleasedStopNotice>> appealableNotices();

  /// Deletes everything this device holds for [routeStopId]: its outbox rows
  /// of every state (check-in/out with their answers, impediments, the
  /// evidence of its execution), its form draft, its progress and its
  /// notice. Nothing of another stop is touched.
  Future<void> discardStop(String routeStopId);
}

class DriftReleasedStopStore implements ReleasedStopStore {
  /// [now] stamps `createdAt`; tests pass a fixed clock.
  DriftReleasedStopStore(this._db, {DateTime Function() now = DateTime.now})
    // A private field can't be an initializing formal with a public param
    // name (same idiom as sync_worker.dart).
    // ignore: prefer_initializing_formals
    : _now = now;

  final AppDatabase _db;
  final DateTime Function() _now;

  @override
  Future<bool> record({
    required String routeStopId,
    required String releaseReason,
    required bool appealable,
  }) => _db.transaction(() async {
    if (await noticeFor(routeStopId) != null) return false;
    final scans = await _localScans(routeStopId);
    await _db
        .into(_db.releasedStops)
        .insert(
          ReleasedStopsCompanion.insert(
            routeStopId: routeStopId,
            releaseReason: releaseReason,
            appealable: appealable,
            localCheckInAt: Value(scans[PendingOpKind.checkIn.name]),
            localCheckOutAt: Value(scans[PendingOpKind.checkOut.name]),
            createdAt: _now().millisecondsSinceEpoch,
          ),
        );
    return true;
  });

  /// The `scanned_at` of the stop's check-in and check-out rows, whatever
  /// their state (a check-in delivered before the release still counts), as
  /// epoch milliseconds keyed by kind. JSON1 reads the payload in SQLite: the
  /// photo rows of the table carry their bytes, and loading them all to find
  /// two timestamps would be wasteful.
  Future<Map<String, int>> _localScans(String routeStopId) async {
    final rows = await _db
        .customSelect(
          'SELECT kind, '
          r"json_extract(payload_json, '$.scanned_at') AS scanned_at "
          'FROM pending_operations '
          'WHERE kind IN (?2, ?3) '
          r"AND json_extract(payload_json, '$.route_stop_id') = ?1 "
          'ORDER BY created_at',
          variables: [
            Variable.withString(routeStopId),
            Variable.withString(PendingOpKind.checkIn.name),
            Variable.withString(PendingOpKind.checkOut.name),
          ],
          readsFrom: {_db.pendingOperations},
        )
        .get();
    final scans = <String, int>{};
    for (final row in rows) {
      final scannedAt = row.read<String?>('scanned_at');
      if (scannedAt == null) continue;
      scans.putIfAbsent(
        row.read<String>('kind'),
        () => DateTime.parse(scannedAt).millisecondsSinceEpoch,
      );
    }
    return scans;
  }

  @override
  Future<ReleasedStopNotice?> noticeFor(String routeStopId) async {
    final row = await (_db.select(
      _db.releasedStops,
    )..where((r) => r.routeStopId.equals(routeStopId))).getSingleOrNull();
    return row == null ? null : _toNotice(row);
  }

  @override
  Future<List<ReleasedStopNotice>> appealableNotices() async {
    final rows =
        await (_db.select(_db.releasedStops)
              ..where((r) => r.appealable.equals(true))
              ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
            .get();
    return rows.map(_toNotice).toList();
  }

  @override
  Future<void> discardStop(String routeStopId) => _db.transaction(() async {
    final executions = await _executionsOf(routeStopId);
    await _deleteOutboxRows(routeStopId, executions);
    await (_db.delete(
      _db.formDraftItems,
    )..where((r) => r.routeStopId.equals(routeStopId))).go();
    await (_db.delete(
      _db.stopProgress,
    )..where((r) => r.routeStopId.equals(routeStopId))).go();
    await (_db.delete(
      _db.releasedStops,
    )..where((r) => r.routeStopId.equals(routeStopId))).go();
  });

  /// The stop's execution ids — the ones its evidence rows carry: from its
  /// check-in rows, and from its progress row for when no check-in row is
  /// left. A check-out's `execution_id` is a throwaway and is not one.
  Future<Set<String>> _executionsOf(String routeStopId) async {
    final checkIns = await _db
        .customSelect(
          r"SELECT json_extract(payload_json, '$.execution_id') AS execution "
          'FROM pending_operations '
          'WHERE kind = ?2 '
          r"AND json_extract(payload_json, '$.route_stop_id') = ?1",
          variables: [
            Variable.withString(routeStopId),
            Variable.withString(PendingOpKind.checkIn.name),
          ],
          readsFrom: {_db.pendingOperations},
        )
        .get();
    final progress = await (_db.select(
      _db.stopProgress,
    )..where((r) => r.routeStopId.equals(routeStopId))).getSingleOrNull();
    return {
      for (final row in checkIns) ?row.read<String?>('execution'),
      ?progress?.executionId,
    };
  }

  Future<void> _deleteOutboxRows(
    String routeStopId,
    Set<String> executions,
  ) => _db.customUpdate(
    'DELETE FROM pending_operations '
    'WHERE released_stop_id = ?1 '
    'OR (kind IN (?2, ?3, ?4) '
    r"AND json_extract(payload_json, '$.route_stop_id') = ?1) "
    'OR (kind IN (?5, ?6) '
    r"AND json_extract(payload_json, '$.execution_id') "
    'IN (SELECT value FROM json_each(?7)))',
    variables: [
      Variable.withString(routeStopId),
      Variable.withString(PendingOpKind.checkIn.name),
      Variable.withString(PendingOpKind.checkOut.name),
      Variable.withString(PendingOpKind.impediment.name),
      Variable.withString(PendingOpKind.evidencePhoto.name),
      Variable.withString(PendingOpKind.evidenceNote.name),
      Variable.withString(jsonEncode(executions.toList())),
    ],
    updates: {_db.pendingOperations},
    updateKind: UpdateKind.delete,
  );

  static ReleasedStopNotice _toNotice(ReleasedStop row) => ReleasedStopNotice(
    routeStopId: row.routeStopId,
    releaseReason: row.releaseReason,
    appealable: row.appealable,
    localCheckInAt: _fromEpochMs(row.localCheckInAt),
    localCheckOutAt: _fromEpochMs(row.localCheckOutAt),
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt, isUtc: true),
  );

  static DateTime? _fromEpochMs(int? ms) =>
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}
