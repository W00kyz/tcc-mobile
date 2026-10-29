import 'dart:io';

import 'package:drift/backends.dart';
import 'package:drift/drift.dart' show OpeningDetails;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';

/// Same approach as migration_5_to_6_test.dart: hand-seed a schema-6 file
/// with raw DDL, mark it `user_version = 6`, then open the real
/// [AppDatabase] so `onUpgrade` runs the 6→7 step.
class _SeedUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 6;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

const _legacyPayload =
    '{"route_stop_id":"s1","form_version_id":"v1",'
    '"answers":[{"stable_key":"q1","value":"sim"}]}';

Future<void> _seedSchema6(File file) async {
  final seed = NativeDatabase(file);
  await seed.ensureOpen(_SeedUser());
  await seed.runCustom('''
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
      )
    ''', const []);
  await seed.runCustom('''
      CREATE TABLE stop_progress (
        route_stop_id TEXT NOT NULL PRIMARY KEY,
        execution_id TEXT NOT NULL,
        local_status TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''', const []);
  await seed.runCustom('''
      CREATE TABLE sync_meta (
        "key" TEXT NOT NULL PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''', const []);
  await seed.runCustom('''
      CREATE TABLE released_stops (
        route_stop_id TEXT NOT NULL PRIMARY KEY,
        release_reason TEXT NOT NULL,
        appealable INTEGER NOT NULL,
        local_check_in_at INTEGER NULL,
        local_check_out_at INTEGER NULL,
        created_at INTEGER NOT NULL
      )
    ''', const []);
  await seed.runCustom('''
      CREATE TABLE form_draft_items (
        execution_id TEXT NOT NULL,
        stable_key TEXT NOT NULL,
        route_stop_id TEXT NOT NULL,
        form_version_id TEXT NOT NULL,
        order_index INTEGER NOT NULL,
        prompt TEXT NOT NULL,
        question_type TEXT NOT NULL,
        required INTEGER NOT NULL,
        options_json TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        value_json TEXT NULL,
        needs_reanswer INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (execution_id, stable_key)
      )
    ''', const []);
  await seed.runCustom(
    'INSERT INTO form_draft_items '
    '(execution_id, stable_key, route_stop_id, form_version_id, order_index, '
    'prompt, question_type, required, options_json, content_hash, value_json) '
    "VALUES ('exec-1', 'q1', 's1', 'v1', 0, 'Limpo?', 'TEXT', 1, '[]', "
    "'h1', '\"sim\"')",
    const [],
  );
  // An old-app check-out still queued with its form fields, and a plain
  // pending one: both must survive the step untouched.
  await seed.runCustom(
    'INSERT INTO pending_operations '
    '(id, kind, route_id, payload_json, created_at, state) '
    'VALUES '
    "('op-1', 'checkOut', 'route-1', '$_legacyPayload', 1000, 'pending'), "
    "('op-2', 'checkIn', 'route-1', '{\"route_stop_id\":\"s2\"}', 2000, "
    "'pending')",
    const [],
  );
  await seed.runCustom('PRAGMA user_version = 6', const []);
  await seed.close();
}

void main() {
  late File file;
  late AppDatabase db;

  setUp(() async {
    file = File(
      '${Directory.systemTemp.path}/migration_6_to_7_'
      '${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    await _seedSchema6(file);
    // --- Open the real database: onUpgrade(m, 6, 7) fires here ---
    db = AppDatabase(NativeDatabase(file));
  });

  tearDown(() async {
    await db.close();
    if (file.existsSync()) file.deleteSync();
  });

  test('6 to 7 drops the form draft table', () async {
    final tables = await db
        .customSelect(
          'SELECT name FROM sqlite_master '
          "WHERE type = 'table' AND name = 'form_draft_items'",
        )
        .get();

    expect(tables, isEmpty);
    expect(db.schemaVersion, 9);
  });

  test('6 to 7 keeps every outbox row unchanged', () async {
    final store = DriftLocalWriteStore(db);

    final rows = await store.unsyncedForRoute('route-1');

    expect(rows.map((r) => r.id), ['op-1', 'op-2']);
    expect(rows.first.payload['form_version_id'], 'v1');
    expect(rows.first.payload['route_stop_id'], 's1');
    expect(rows.last.payload, {'route_stop_id': 's2'});
  });
}
