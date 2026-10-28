import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/stop_progress_store.dart';

import '../support/in_memory_database.dart';

void main() {
  late DriftStopProgressStore store;

  setUp(() {
    final db = inMemoryDatabase();
    addTearDown(db.close);
    store = DriftStopProgressStore(db);
  });

  test('progressFor returns null for an untouched stop', () async {
    expect(await store.progressFor('stop-1'), isNull);
  });

  test(
    'upsertInProgress then progressFor returns inProgress with the exec id',
    () async {
      await store.upsertInProgress('stop-1', 'exec-1');

      final entry = await store.progressFor('stop-1');
      expect(entry, isNotNull);
      expect(entry!.routeStopId, 'stop-1');
      expect(entry.executionId, 'exec-1');
      expect(entry.status, StopLocalStatus.inProgress);
    },
  );

  test(
    'upsertInProgress overwrites an existing row for the same stop',
    () async {
      await store.upsertInProgress('stop-1', 'exec-1');
      await store.upsertInProgress('stop-1', 'exec-2');

      expect((await store.progressFor('stop-1'))!.executionId, 'exec-2');
    },
  );

  test(
    'markDone flips the status to done and preserves the execution id',
    () async {
      await store.upsertInProgress('stop-1', 'exec-1');

      await store.markDone('stop-1');

      final entry = await store.progressFor('stop-1');
      expect(entry!.status, StopLocalStatus.done);
      expect(entry.executionId, 'exec-1');
    },
  );

  test('markDone on an untouched stop is a no-op, not an error', () async {
    await store.markDone('stop-never-touched');

    expect(await store.progressFor('stop-never-touched'), isNull);
  });

  test('allForRoute returns only the rows for the given stop ids', () async {
    await store.upsertInProgress('stop-1', 'exec-1');
    await store.upsertInProgress('stop-2', 'exec-2');
    await store.upsertInProgress('stop-3', 'exec-3');

    final entries = await store.allForRoute([
      'stop-1',
      'stop-3',
      'stop-absent',
    ]);

    expect(
      entries.map((e) => e.routeStopId).toSet(),
      {'stop-1', 'stop-3'},
    );
  });

  test('allForRoute with no ids returns empty without querying', () async {
    await store.upsertInProgress('stop-1', 'exec-1');

    expect(await store.allForRoute(const []), isEmpty);
  });

  test('rows for different stops are independent', () async {
    await store.upsertInProgress('stop-1', 'exec-1');
    await store.upsertInProgress('stop-2', 'exec-2');

    await store.markDone('stop-1');

    expect((await store.progressFor('stop-1'))!.status, StopLocalStatus.done);
    expect(
      (await store.progressFor('stop-2'))!.status,
      StopLocalStatus.inProgress,
    );
  });

  test('markStamped stores the status and the observation', () async {
    await store.upsertInProgress('s1', 'exec-1');

    await store.markStamped('s1', observation: 'pia');

    final entry = await store.progressFor('s1');
    expect(entry!.status, StopLocalStatus.stamped);
    expect(entry.observation, 'pia');
    expect(entry.executionId, 'exec-1');
  });

  test('markStamped without a note leaves the observation null', () async {
    await store.upsertInProgress('s1', 'exec-1');

    await store.markStamped('s1');

    expect((await store.progressFor('s1'))!.observation, isNull);
  });

  test('markStamped bumps updatedAt', () async {
    await store.upsertInProgress('s1', 'exec-1');
    final before = (await store.progressFor('s1'))!.updatedAt;
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await store.markStamped('s1');

    final after = (await store.progressFor('s1'))!.updatedAt;
    expect(after.isAfter(before), isTrue);
  });

  test('markStamped on an untouched stop is a no-op', () async {
    await store.markStamped('s-never', observation: 'x');

    expect(await store.progressFor('s-never'), isNull);
  });

  test('markDone after markStamped keeps the observation', () async {
    await store.upsertInProgress('s1', 'exec-1');
    await store.markStamped('s1', observation: 'pia');

    await store.markDone('s1');

    final entry = await store.progressFor('s1');
    expect(entry!.status, StopLocalStatus.done);
    expect(entry.observation, 'pia');
  });

  test('a stamped stop and its note survive closing the database', () async {
    final file = File(
      '${Directory.systemTemp.path}/stamped_'
      '${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final first = AppDatabase(NativeDatabase(file));
    final firstStore = DriftStopProgressStore(first);
    await firstStore.upsertInProgress('s1', 'exec-1');
    await firstStore.markStamped('s1', observation: 'pia');
    await first.close();

    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);
    final entry = await DriftStopProgressStore(second).progressFor('s1');

    expect(entry!.status, StopLocalStatus.stamped);
    expect(entry.observation, 'pia');
  });
}
