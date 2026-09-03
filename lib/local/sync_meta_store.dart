import 'package:route_monitor/local/app_database.dart';

/// Flat key/value bookkeeping for the sync worker (spec Ruling 9). Values are
/// stored as text in the `SyncMeta.value` column; each accessor owns its own
/// key and its own text<->value coding.
abstract class SyncMetaStore {
  /// The device-vs-server clock skew in seconds (server minus device), or
  /// null before the worker has ever measured it.
  Future<double?> getClockOffsetSeconds();

  Future<void> setClockOffsetSeconds(double seconds);

  /// The tap-time instant "Iniciar rota" was pressed for [routeId], or null
  /// before it has been pressed on this device. The optimistic marker that
  /// lets the UI treat the route as started while the outbox row is still
  /// `pending` (spec Ruling 5).
  Future<DateTime?> getRouteStartedAt(String routeId);

  Future<void> setRouteStartedAt(String routeId, DateTime startedAt);
}

class DriftSyncMetaStore implements SyncMetaStore {
  DriftSyncMetaStore(this._db);

  final AppDatabase _db;

  static const _clockOffsetKey = 'clock_offset_seconds';

  @override
  Future<double?> getClockOffsetSeconds() async {
    final raw = await _get(_clockOffsetKey);
    return raw == null ? null : double.parse(raw);
  }

  @override
  Future<void> setClockOffsetSeconds(double seconds) =>
      _set(_clockOffsetKey, seconds.toString());

  static String _routeStartedAtKey(String routeId) =>
      'route:$routeId:started_at';

  @override
  Future<DateTime?> getRouteStartedAt(String routeId) async {
    final raw = await _get(_routeStartedAtKey(routeId));
    return raw == null ? null : DateTime.parse(raw);
  }

  @override
  Future<void> setRouteStartedAt(String routeId, DateTime startedAt) =>
      _set(_routeStartedAtKey(routeId), startedAt.toIso8601String());

  Future<String?> _get(String key) async {
    final row = await (_db.select(
      _db.syncMeta,
    )..where((row) => row.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _set(String key, String value) {
    return _db
        .into(_db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(key: key, value: value),
        );
  }
}
