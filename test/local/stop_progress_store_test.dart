import 'package:flutter_test/flutter_test.dart';
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
}
