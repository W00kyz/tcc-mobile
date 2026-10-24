import 'dart:io';

import 'package:drift/backends.dart';
import 'package:drift/drift.dart' show OpeningDetails;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';

/// Same approach as migration_3_to_4_test.dart: hand-seed a schema-4 file
/// with raw DDL, mark it `user_version = 4`, then open the real
/// [AppDatabase] so `onUpgrade` runs the 4→5 step.
class _SeedUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 4;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

Future<void> _seedSchema4(File file) async {
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
        next_attempt_at INTEGER NULL
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
  // A queued "Iniciar rota" (the outbox kind this step retires), a blocked
  // one, a check-in that must survive, and the per-route meta it leaves.
  await seed.runCustom(
    'INSERT INTO pending_operations '
    '(id, kind, route_id, payload_json, created_at, state) VALUES '
    "('start-1', 'startRoute', 'route-1', '{}', 1000, 'pending'), "
    "('start-2', 'startRoute', 'route-0', '{}', 500, 'blocked'), "
    "('op-1', 'checkIn', 'route-1', '{}', 2000, 'pending')",
    const [],
  );
  await seed.runCustom(
    'INSERT INTO sync_meta ("key", value) VALUES '
    "('route:route-1:started_at', '2026-10-19T11:00:00.000Z'), "
    "('routes_me_snapshot:u1', '[]'), "
    "('clock_offset_seconds', '1.5')",
    const [],
  );
  await seed.runCustom('PRAGMA user_version = 4', const []);
  await seed.close();
}

void main() {
  late File file;
  late AppDatabase db;

  setUp(() async {
    file = File(
      '${Directory.systemTemp.path}/migration_4_to_5_'
      '${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    await _seedSchema4(file);
    // --- Open the real database: onUpgrade(m, 4, 5) fires here ---
    db = AppDatabase(NativeDatabase(file));
  });

  tearDown(() async {
    await db.close();
    if (file.existsSync()) file.deleteSync();
  });

  test('4 to 5 drops every startRoute row and keeps the rest', () async {
    final kinds = await db
        .customSelect('SELECT id, kind FROM pending_operations ORDER BY id')
        .get();

    expect(kinds.map((row) => row.data['id']), ['op-1']);
    // Every remaining kind still decodes — a leftover 'startRoute' row would
    // make `PendingOpKind.values.byName` throw on the next drain.
    final store = DriftLocalWriteStore(db);
    expect(await store.unsyncedForRoute('route-1'), hasLength(1));
    expect(db.schemaVersion, 5);
  });

  test(
    '4 to 5 drops the old route-start markers and route-list snapshot',
    () async {
      final meta = await db
          .customSelect('SELECT "key" FROM sync_meta ORDER BY "key"')
          .get();

      expect(meta.map((row) => row.data['key']), ['clock_offset_seconds']);
    },
  );
}
