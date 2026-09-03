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

  test('getRouteStartedAt is null before it is ever set', () async {
    expect(await store.getRouteStartedAt('r1'), isNull);
  });

  test(
    'setRouteStartedAt then getRouteStartedAt round-trips the instant, '
    'keyed per route',
    () async {
      final startedAt = DateTime.utc(2026, 8, 25, 8, 15);
      await store.setRouteStartedAt('r1', startedAt);

      expect(await store.getRouteStartedAt('r1'), startedAt);
      expect(await store.getRouteStartedAt('r2'), isNull);
    },
  );
}
