import 'dart:io';

import 'package:drift/backends.dart';
import 'package:drift/drift.dart' show OpeningDetails;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/local/app_database.dart';

/// This repo has no `drift/schema/` dumps, so drift's `schema` verification
/// tooling isn't available. The pragmatic path (documented in
/// task-4-report.md, reused here for the 3→4 step): hand-seed a schema-3
/// database on a real file with raw DDL matching the Etapa 6 shape, mark it
/// `user_version = 3`, then open the real [AppDatabase] against that file and
/// let `onUpgrade` run the 3→4 step.

/// Minimal [QueryExecutorUser] for opening a bare [NativeDatabase] just to run
/// seed DDL — no drift migrator involved.
class _SeedUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 3;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

void main() {
  test(
    '3 to 4 migration: form_draft_items is gone once 6 to 7 has run',
    () async {
      final file = File(
        '${Directory.systemTemp.path}/migration_3_to_4_'
        '${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });

      // --- Seed the schema-3 shape, verbatim ---
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
      await seed.runCustom(
        'INSERT INTO pending_operations '
        '(id, kind, route_id, payload_json, created_at, state, attempts, '
        'next_attempt_at) '
        "VALUES ('op-1', 'checkIn', 'route-1', '{}', 1000, 'pending', 0, NULL)",
        const [],
      );
      await seed.runCustom(
        'INSERT INTO stop_progress '
        '(route_stop_id, execution_id, local_status, updated_at) '
        "VALUES ('stop-1', 'exec-1', 'IN_PROGRESS', 2000)",
        const [],
      );
      await seed.runCustom(
        'INSERT INTO sync_meta ("key", value) '
        "VALUES ('last_full_sync', '3000')",
        const [],
      );
      await seed.runCustom('PRAGMA user_version = 3', const []);
      await seed.close();

      // --- Open the real database: onUpgrade(m, 3, 4) fires here ---
      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);

      final pending = await db
          .customSelect(
            'SELECT kind, route_id, payload_json, created_at, state, '
            'attempts, next_attempt_at FROM pending_operations '
            "WHERE id = 'op-1'",
          )
          .getSingle();
      expect(pending.data['kind'], 'checkIn');
      expect(pending.data['route_id'], 'route-1');
      expect(pending.data['state'], 'pending');
      expect(pending.data['attempts'], 0);
      expect(pending.data['next_attempt_at'], isNull);

      final progress = await db
          .customSelect(
            "SELECT * FROM stop_progress WHERE route_stop_id = 'stop-1'",
          )
          .getSingle();
      expect(progress.data['execution_id'], 'exec-1');
      expect(progress.data['local_status'], 'IN_PROGRESS');
      expect(progress.data['updated_at'], 2000);

      final syncMeta = await db
          .customSelect(
            "SELECT value FROM sync_meta WHERE \"key\" = 'last_full_sync'",
          )
          .getSingle();
      expect(syncMeta.data['value'], '3000');

      final formDraftItems = await db
          .customSelect(
            'SELECT name FROM sqlite_master '
            "WHERE type = 'table' AND name = 'form_draft_items'",
          )
          .get();
      // No step creates it any more (6→7's DROP IF EXISTS is a no-op).
      expect(formDraftItems, isEmpty);

      // The current constant: every later step runs right after this one.
      expect(db.schemaVersion, 8);
    },
  );
}
