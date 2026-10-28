import 'dart:io';

import 'package:drift/backends.dart';
import 'package:drift/drift.dart' show OpeningDetails;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/day_log_store.dart';
import 'package:route_monitor/local/local_write_store.dart';

/// Same approach as migration_6_to_7_test.dart: hand-seed a schema-7 file
/// with raw DDL, mark it `user_version = 7`, then open the real
/// [AppDatabase] so `onUpgrade` runs the 7→8 step.
class _SeedUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 7;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

const List<String> _schema7 = [
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
];

Future<void> _seedSchema7(File file) async {
  final seed = NativeDatabase(file);
  await seed.ensureOpen(_SeedUser());
  for (final ddl in _schema7) {
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
  await seed.runCustom('PRAGMA user_version = 7', const []);
  await seed.close();
}

void main() {
  late File file;
  late AppDatabase db;

  setUp(() async {
    file = File(
      '${Directory.systemTemp.path}/migration_7_to_8_'
      '${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    await _seedSchema7(file);
    // --- Open the real database: onUpgrade(m, 7, 8) fires here ---
    db = AppDatabase(NativeDatabase(file));
  });

  tearDown(() async {
    await db.close();
    if (file.existsSync()) file.deleteSync();
  });

  test('7 to 8 creates an empty, writable day log', () async {
    final store = DriftDayLogStore(db);

    expect(await store.all(), isEmpty);
    await store.recordStopDone(DateTime(2026, 10, 21, 9));
    expect((await store.all()).single.pointsDone, 1);
    expect(db.schemaVersion, 8);
  });

  test('7 to 8 keeps every outbox row unchanged', () async {
    final rows = await DriftLocalWriteStore(db).unsyncedForRoute('route-1');

    expect(rows.map((r) => r.id), ['op-1', 'op-2']);
    expect(rows.last.kind, PendingOpKind.checkOut);
    expect(rows.last.payload, {'route_stop_id': 's1'});
  });
}
