import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/local/day_log_store.dart';

import '../support/in_memory_database.dart';

void main() {
  late DriftDayLogStore store;

  setUp(() {
    final db = inMemoryDatabase();
    addTearDown(db.close);
    store = DriftDayLogStore(db);
  });

  test('an empty log reads empty', () async {
    expect(await store.all(), isEmpty);
  });

  test('recordDayOpened creates the day with zero counts', () async {
    await store.recordDayOpened(
      DateTime(2026, 10, 21, 7, 30),
      serviceDay: false,
    );

    final entry = (await store.all()).single;
    expect(entry.day, DateTime(2026, 10, 21));
    expect(entry.serviceDay, isFalse);
    expect(entry.pointsDone, 0);
    expect(entry.cardsCompleted, 0);
    expect(entry.cleanCards, 0);
  });

  test(
    'recordDayOpened again keeps the counts and updates serviceDay',
    () async {
      final day = DateTime(2026, 10, 21, 7);
      await store.recordDayOpened(day, serviceDay: false);
      await store.recordStopDone(day);
      await store.recordDayOpened(day, serviceDay: true);

      final entry = (await store.all()).single;
      expect(entry.serviceDay, isTrue);
      expect(entry.pointsDone, 1);
    },
  );

  test(
    'recordStopDone counts each stop, creating the day if missing',
    () async {
      await store.recordStopDone(DateTime(2026, 10, 21, 9));
      await store.recordStopDone(DateTime(2026, 10, 21, 10));

      final entry = (await store.all()).single;
      expect(entry.serviceDay, isTrue);
      expect(entry.pointsDone, 2);
    },
  );

  test('recordCardCompleted counts cards and only the clean ones as '
      'clean', () async {
    final day = DateTime(2026, 10, 21, 11);
    await store.recordCardCompleted(day, clean: false);
    await store.recordCardCompleted(day, clean: true);

    final entry = (await store.all()).single;
    expect(entry.cardsCompleted, 2);
    expect(entry.cleanCards, 1);
  });

  test('all returns one entry per day, oldest first', () async {
    await store.recordStopDone(DateTime(2026, 10, 22, 8));
    await store.recordStopDone(DateTime(2026, 10, 20, 8));

    final days = (await store.all()).map((e) => e.day).toList();
    expect(days, [DateTime(2026, 10, 20), DateTime(2026, 10, 22)]);
  });
}
