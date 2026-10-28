import 'dart:io';

import 'package:drift/backends.dart';
import 'package:drift/drift.dart' show OpeningDetails;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';

/// Same approach as migration_7_to_8_test.dart: hand-seed a schema-8 file
/// with raw DDL, mark it `user_version = 8`, then open the real
/// [AppDatabase] so `onUpgrade` runs the 8→9 step.
class _SeedUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 8;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

const List<String> _schema8 = [
  '''
  CREATE TABLE pending_operations (
    id TEXT NOT NULL PRIMARY KEY,
    kind TEXT NOT NULL,
    route_id TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    state TEXT NOT NULL DEFAULT 'pending',
    last_error TEXT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    next_attempt_at INTEGER NULL,
    released_stop_id TEXT NULL
  )''',
  '''
  CREATE TABLE stop_progress (
    route_stop_id TEXT NOT NULL PRIMARY KEY,
    execution_id TEXT NOT NULL,
    local_status TEXT NOT NULL,
    updated_at INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE sync_meta (
    "key" TEXT NOT NULL PRIMARY KEY,
    value TEXT NOT NULL
  )''',
  '''
  CREATE TABLE released_stops (
    route_stop_id TEXT NOT NULL PRIMARY KEY,
    release_reason TEXT NOT NULL,
    appealable INTEGER NOT NULL,
    local_check_in_at INTEGER NULL,
    local_check_out_at INTEGER NULL,
    created_at INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE day_log (
    day TEXT NOT NULL PRIMARY KEY,
    service_day INTEGER NOT NULL DEFAULT 1,
    points_done INTEGER NOT NULL DEFAULT 0,
    cards_completed INTEGER NOT NULL DEFAULT 0,
    clean_cards INTEGER NOT NULL DEFAULT 0
  )''',
];

Future<void> _seedSchema8(File file) async {
  final seed = NativeDatabase(file);
  await seed.ensureOpen(_SeedUser());
  for (final ddl in _schema8) {
    await seed.runCustom(ddl, const []);
  }
  await seed.runCustom(
    'INSERT INTO pending_operations '
    '(id, kind, route_id, payload_json, created_at, state) '
    'VALUES '
    "('op-1', 'checkIn', 'route-1', '{\"route_stop_id\":\"s1\"}', 1000, "
    "'pending'), "
    "('op-2', 'checkOut', 'route-1', '{\"route_stop_id\":\"s1\"}', 2000, "
    "'pending')",
    const [],
  );
  await seed.runCustom(
    'INSERT INTO stop_progress '
    '(route_stop_id, execution_id, local_status, updated_at) '
    "VALUES ('s1', 'exec-1', 'IN_PROGRESS', 3000)",
    const [],
  );
  await seed.runCustom('PRAGMA user_version = 8', const []);
  await seed.close();
}

void main() {
  late File file;
  late AppDatabase db;

  setUp(() async {
    file = File(
      '${Directory.systemTemp.path}/migration_8_to_9_'
      '${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    await _seedSchema8(file);
    // --- Open the real database: onUpgrade(m, 8, 9) fires here ---
    db = AppDatabase(NativeDatabase(file));
  });

  tearDown(() async {
    await db.close();
    if (file.existsSync()) file.deleteSync();
  });

  test('8 to 9 adds a null observation to an existing stop row', () async {
    final entry = await DriftStopProgressStore(db).progressFor('s1');

    expect(entry!.executionId, 'exec-1');
    expect(entry.status, StopLocalStatus.inProgress);
    expect(entry.observation, isNull);
    expect(db.schemaVersion, 9);
  });

  test('8 to 9 lets the migrated row be stamped with a note', () async {
    final store = DriftStopProgressStore(db);

    await store.markStamped('s1', observation: 'pia');

    expect((await store.progressFor('s1'))!.observation, 'pia');
  });

  test('8 to 9 keeps every outbox row unchanged', () async {
    final rows = await DriftLocalWriteStore(db).unsyncedForRoute('route-1');

    expect(rows.map((r) => r.id), ['op-1', 'op-2']);
    expect(rows.last.kind, PendingOpKind.checkOut);
    expect(rows.last.payload, {'route_stop_id': 's1'});
  });
}
