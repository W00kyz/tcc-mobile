import 'dart:io';

import 'package:drift/backends.dart';
import 'package:drift/drift.dart' show OpeningDetails;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/released_stop_store.dart';

/// Same approach as migration_4_to_5_test.dart: hand-seed a schema-5 file
/// with raw DDL, mark it `user_version = 5`, then open the real
/// [AppDatabase] so `onUpgrade` runs the 5→6 step.
class _SeedUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 5;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

Future<void> _seedSchema5(File file) async {
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
  // A row M2 parked as blocked (a late STOP_RELEASED, before this schema
  // could say so) and a pending one: both must survive the step.
  await seed.runCustom(
    'INSERT INTO pending_operations '
    '(id, kind, route_id, payload_json, created_at, state, last_error) '
    'VALUES '
    "('op-1', 'checkOut', 'route-1', '{\"route_stop_id\":\"s1\"}', 1000, "
    "'blocked', 'HTTP 409'), "
    "('op-2', 'checkIn', 'route-1', '{\"route_stop_id\":\"s2\"}', 2000, "
    "'pending', NULL)",
    const [],
  );
  await seed.runCustom('PRAGMA user_version = 5', const []);
  await seed.close();
}

void main() {
  late File file;
  late AppDatabase db;

  setUp(() async {
    file = File(
      '${Directory.systemTemp.path}/migration_5_to_6_'
      '${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    await _seedSchema5(file);
    // --- Open the real database: onUpgrade(m, 5, 6) fires here ---
    db = AppDatabase(NativeDatabase(file));
  });

  tearDown(() async {
    await db.close();
    if (file.existsSync()) file.deleteSync();
  });

  test('5 to 6 keeps every outbox row, none of them parked', () async {
    final store = DriftLocalWriteStore(db);

    final blocked = await store.blockedForRoute('route-1');
    final pending = await store.unsyncedForRoute('route-1');

    expect(blocked.single.id, 'op-1');
    expect(blocked.single.releasedStopId, isNull);
    expect(pending.single.id, 'op-2');
    expect(db.schemaVersion, 8);
  });

  test('5 to 6 adds the released-stops table, empty', () async {
    final store = DriftReleasedStopStore(db);

    expect(await store.allNotices(), isEmpty);
    await store.record(
      routeStopId: 's1',
      releaseReason: 'LOCATION_SILENCE',
      appealable: true,
    );
    expect((await store.noticeFor('s1'))?.releaseReason, 'LOCATION_SILENCE');
  });

  test('5 to 6 lets a row be parked on its released stop', () async {
    final store = DriftLocalWriteStore(db);

    await store.markStopReleased('op-2', routeStopId: 's2', error: 'HTTP 409');

    final parked = (await store.blockedForRoute('route-1')).last;
    expect(parked.id, 'op-2');
    expect(parked.releasedStopId, 's2');
  });
}
