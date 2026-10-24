import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/monitoring/location_mode.dart';

/// [BackgroundAskStore] as one row of the flat `SyncMeta` key/value table —
/// a device flag, so it outlives a restart and is never asked twice.
class DriftBackgroundAskStore implements BackgroundAskStore {
  DriftBackgroundAskStore(this._db);

  final AppDatabase _db;

  static const _key = 'background_location_asked';

  @override
  Future<bool> wasAsked() async {
    final row = await (_db.select(
      _db.syncMeta,
    )..where((row) => row.key.equals(_key))).getSingleOrNull();
    return row != null;
  }

  @override
  Future<void> markAsked() {
    return _db
        .into(_db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(key: _key, value: 'true'),
        );
  }
}
