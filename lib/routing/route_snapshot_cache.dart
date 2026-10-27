import 'package:route_monitor/local/app_database.dart';

/// The last `/routes/me` body the server returned, kept on the device so the
/// day's route still opens without network (RF35, RNF21) — after the app was
/// killed in a basement, or on a pull-to-refresh with no signal. Raw JSON on
/// purpose: it is re-parsed by the same `MyDay.fromJson` as a live
/// response, so the two paths cannot drift apart.
abstract class RouteSnapshotCache {
  Future<String?> load(String userId);
  Future<void> save(String userId, String json);
}

/// Stored in the existing `SyncMeta` key/value table (no schema migration),
/// one row per user so a shared phone never shows one worker another's route.
class DriftRouteSnapshotCache implements RouteSnapshotCache {
  DriftRouteSnapshotCache(this._db);

  final AppDatabase _db;

  static String _key(String userId) => 'routes_me_snapshot:$userId';

  @override
  Future<String?> load(String userId) async {
    final row = await (_db.select(
      _db.syncMeta,
    )..where((row) => row.key.equals(_key(userId)))).getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> save(String userId, String json) {
    return _db
        .into(_db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(key: _key(userId), value: json),
        );
  }
}

class InMemoryRouteSnapshotCache implements RouteSnapshotCache {
  final Map<String, String> snapshots = {};

  @override
  Future<String?> load(String userId) async => snapshots[userId];

  @override
  Future<void> save(String userId, String json) async =>
      snapshots[userId] = json;
}
