import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/local/open_execution_store.dart';

import '../support/in_memory_database.dart';

void main() {
  late DriftOpenExecutionStore store;

  setUp(() {
    final db = inMemoryDatabase();
    addTearDown(db.close);
    store = DriftOpenExecutionStore(db);
  });

  test(
    'openExecutionFor returns null for a stop with no open execution',
    () async {
      expect(await store.openExecutionFor('stop-1'), isNull);
    },
  );

  test(
    'recordOpenExecution then openExecutionFor returns the execution id',
    () async {
      await store.recordOpenExecution('stop-1', 'exec-1');

      expect(await store.openExecutionFor('stop-1'), 'exec-1');
    },
  );

  test(
    'recordOpenExecution overwrites an existing row for the same stop',
    () async {
      await store.recordOpenExecution('stop-1', 'exec-1');
      await store.recordOpenExecution('stop-1', 'exec-2');

      expect(await store.openExecutionFor('stop-1'), 'exec-2');
    },
  );

  test('clearOpenExecution removes the row', () async {
    await store.recordOpenExecution('stop-1', 'exec-1');

    await store.clearOpenExecution('stop-1');

    expect(await store.openExecutionFor('stop-1'), isNull);
  });

  test(
    'clearOpenExecution on a stop with no row is a no-op, not an error',
    () async {
      await store.clearOpenExecution('stop-never-checked-in');

      expect(await store.openExecutionFor('stop-never-checked-in'), isNull);
    },
  );

  test('rows for different stops are independent', () async {
    await store.recordOpenExecution('stop-1', 'exec-1');
    await store.recordOpenExecution('stop-2', 'exec-2');

    expect(await store.openExecutionFor('stop-1'), 'exec-1');
    expect(await store.openExecutionFor('stop-2'), 'exec-2');

    await store.clearOpenExecution('stop-1');

    expect(await store.openExecutionFor('stop-1'), isNull);
    expect(await store.openExecutionFor('stop-2'), 'exec-2');
  });
}
