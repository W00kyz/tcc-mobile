import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/local/sync_meta_store.dart';

import '../support/in_memory_database.dart';

void main() {
  late DriftSyncMetaStore store;

  setUp(() {
    final db = inMemoryDatabase();
    addTearDown(db.close);
    store = DriftSyncMetaStore(db);
  });

  test('getClockOffsetSeconds is null before it is ever set', () async {
    expect(await store.getClockOffsetSeconds(), isNull);
  });

  test(
    'setClockOffsetSeconds then getClockOffsetSeconds round-trips the double',
    () async {
      await store.setClockOffsetSeconds(-12.5);

      expect(await store.getClockOffsetSeconds(), -12.5);
    },
  );

  test('setClockOffsetSeconds overwrites a previous value', () async {
    await store.setClockOffsetSeconds(3.5);
    await store.setClockOffsetSeconds(0.25);

    expect(await store.getClockOffsetSeconds(), 0.25);
  });

  test('the app is not in the foreground before the flag is written', () async {
    expect(await store.getAppInForeground(), isFalse);
  });

  test('setAppInForeground round-trips both ways', () async {
    await store.setAppInForeground(inForeground: true);
    expect(await store.getAppInForeground(), isTrue);

    await store.setAppInForeground(inForeground: false);
    expect(await store.getAppInForeground(), isFalse);
  });
}
