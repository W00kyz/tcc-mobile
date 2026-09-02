import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/local/local_write_store.dart';

import '../support/in_memory_database.dart';

void main() {
  late DriftLocalWriteStore store;

  setUp(() {
    final db = inMemoryDatabase();
    addTearDown(db.close);
    store = DriftLocalWriteStore(db);
  });

  test(
    'enqueue then unsyncedForRoute returns it pending with the payload',
    () async {
      await store.enqueue(
        id: 'op-1',
        kind: PendingOpKind.checkIn,
        payload: {
          'qrPayload': 'abc',
          'lat': null,
          'nested': {'k': 1},
        },
        routeId: 'route-A',
      );

      final rows = await store.unsyncedForRoute('route-A');

      expect(rows, hasLength(1));
      expect(rows.single.id, 'op-1');
      expect(rows.single.kind, PendingOpKind.checkIn);
      expect(rows.single.state, PendingOpState.pending);
      expect(rows.single.lastError, isNull);
      expect(rows.single.payload, {
        'qrPayload': 'abc',
        'lat': null,
        'nested': {'k': 1},
      });
    },
  );

  test('markSynced drops the row from unsyncedForRoute', () async {
    await store.enqueue(
      id: 'op-1',
      kind: PendingOpKind.checkOut,
      payload: {'x': 1},
      routeId: 'route-A',
    );

    await store.markSynced('op-1');

    expect(await store.unsyncedForRoute('route-A'), isEmpty);
  });

  test('markFailed keeps the row, sets failed state and the error', () async {
    await store.enqueue(
      id: 'op-1',
      kind: PendingOpKind.evidencePhoto,
      payload: {'path': '/tmp/x.jpg'},
      routeId: 'route-A',
    );

    await store.markFailed('op-1', 'SocketException: connection refused');

    final rows = await store.unsyncedForRoute('route-A');
    expect(rows, hasLength(1));
    expect(rows.single.state, PendingOpState.failed);
    expect(rows.single.lastError, 'SocketException: connection refused');
  });

  test(
    'unsyncedForRoute orders by createdAt ascending and filters by routeId',
    () async {
      await store.enqueue(
        id: 'op-old',
        kind: PendingOpKind.checkIn,
        payload: const {},
        routeId: 'route-A',
      );
      await Future<void>.delayed(const Duration(milliseconds: 3));
      await store.enqueue(
        id: 'op-new',
        kind: PendingOpKind.checkOut,
        payload: const {},
        routeId: 'route-A',
      );
      await store.enqueue(
        id: 'op-other-route',
        kind: PendingOpKind.evidenceNote,
        payload: const {},
        routeId: 'route-B',
      );

      final rows = await store.unsyncedForRoute('route-A');

      expect(rows.map((r) => r.id), ['op-old', 'op-new']);
    },
  );

  test(
    'enqueue twice with the same id is a no-op, never resurrects a synced row',
    () async {
      await store.enqueue(
        id: 'op-1',
        kind: PendingOpKind.checkIn,
        payload: {'attempt': 1},
        routeId: 'route-A',
      );
      await store.markSynced('op-1');

      await store.enqueue(
        id: 'op-1',
        kind: PendingOpKind.checkIn,
        payload: {'attempt': 2},
        routeId: 'route-A',
      );

      // Still synced (so still absent from the unsynced list), not duplicated.
      expect(await store.unsyncedForRoute('route-A'), isEmpty);
    },
  );
}
