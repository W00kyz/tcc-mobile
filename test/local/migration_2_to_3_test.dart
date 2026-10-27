import 'dart:io';

import 'package:drift/backends.dart';
import 'package:drift/drift.dart' show OpeningDetails;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/local/app_database.dart';

/// This repo has no `drift/schema/` dumps, so drift's `schema` verification
/// tooling isn't available. The pragmatic path (documented in
/// task-4-report.md): hand-seed a schema-2 database on a real file with raw
/// DDL matching the Etapa 5 shape, mark it `user_version = 2`, then open the
/// real [AppDatabase] against that file and let `onUpgrade` run the 2→3 step.

/// Minimal [QueryExecutorUser] for opening a bare [NativeDatabase] just to run
/// seed DDL — no drift migrator involved.
class _SeedUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 2;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

void main() {
  test(
    '2 to 3 migration: outbox columns, StopProgress carry-over, table drop',
    () async {
      final file = File(
        '${Directory.systemTemp.path}/migration_2_to_3_'
        '${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });

      // --- Seed the schema-2 shape, verbatim ---
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
          last_error TEXT NULL
        )
      ''', const []);
      await seed.runCustom('''
        CREATE TABLE open_executions (
          route_stop_id TEXT NOT NULL PRIMARY KEY,
          execution_id TEXT NOT NULL
        )
      ''', const []);
      await seed.runCustom(
        'INSERT INTO pending_operations '
        '(id, kind, route_id, payload_json, created_at, state) '
        "VALUES ('op-1', 'checkIn', 'route-1', '{}', 1000, 'pending')",
        const [],
      );
      await seed.runCustom(
        'INSERT INTO open_executions (route_stop_id, execution_id) '
        "VALUES ('stop-1', 'exec-1')",
        const [],
      );
      await seed.runCustom('PRAGMA user_version = 2', const []);
      await seed.close();

      // --- Open the real database: onUpgrade(m, 2, 3) fires here ---
      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);

      final pending = await db
          .customSelect(
            'SELECT attempts, next_attempt_at FROM pending_operations '
            "WHERE id = 'op-1'",
          )
          .getSingle();
      expect(pending.data['attempts'], 0);
      expect(pending.data['next_attempt_at'], isNull);

      final progress = await db
          .customSelect(
            "SELECT * FROM stop_progress WHERE route_stop_id = 'stop-1'",
          )
          .getSingle();
      expect(progress.data['execution_id'], 'exec-1');
      expect(progress.data['local_status'], 'IN_PROGRESS');
      expect(progress.data['updated_at'], isA<int>());

      // sync_meta exists (empty is fine)
      final syncMeta = await db
          .customSelect('SELECT key, value FROM sync_meta')
          .get();
      expect(syncMeta, isEmpty);

      final openExecutions = await db
          .customSelect(
            'SELECT name FROM sqlite_master '
            "WHERE type = 'table' AND name = 'open_executions'",
          )
          .get();
      expect(openExecutions, isEmpty);

      // AppDatabase.schemaVersion is the class's current constant (6 as of
      // the 5→6 migration), not "whatever `to` was for this run" — opening
      // this schema-2 seed runs every later onUpgrade block in sequence,
      // landing on the current version.
      expect(db.schemaVersion, 6);
    },
  );
}
