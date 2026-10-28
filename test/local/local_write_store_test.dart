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

  test(
    'enqueue then dueForRoute returns it, attempts 0 and no schedule',
    () async {
      await store.enqueue(
        id: 'op-1',
        kind: PendingOpKind.checkIn,
        payload: const {},
        routeId: 'route-A',
      );

      final due = await store.dueForRoute('route-A', now: 1000);

      expect(due.single.id, 'op-1');
      expect(due.single.attempts, 0);
      expect(due.single.nextAttemptAt, isNull);
    },
  );

  test(
    'markRetryScheduled defers the row until nextAttemptAt and bumps attempts',
    () async {
      await store.enqueue(
        id: 'op-1',
        kind: PendingOpKind.checkIn,
        payload: const {},
        routeId: 'route-A',
      );

      await store.markRetryScheduled('op-1', attempts: 2, nextAttemptAt: 10000);

      expect(await store.dueForRoute('route-A', now: 5000), isEmpty);
      final later = await store.dueForRoute('route-A', now: 20000);
      expect(later.single.id, 'op-1');
      expect(later.single.attempts, 2);
      expect(later.single.nextAttemptAt, 10000);
    },
  );

  test(
    'markBlocked drops the row from dueForRoute, lists it in blockedForRoute',
    () async {
      await store.enqueue(
        id: 'op-1',
        kind: PendingOpKind.checkIn,
        payload: const {},
        routeId: 'route-A',
      );

      await store.markBlocked('op-1', 'gave up after 5 attempts');

      expect(await store.dueForRoute('route-A', now: 9999999), isEmpty);
      expect(await store.unsyncedForRoute('route-A'), isEmpty);
      final blocked = await store.blockedForRoute('route-A');
      expect(blocked.single.id, 'op-1');
      expect(blocked.single.state, PendingOpState.blocked);
      expect(blocked.single.lastError, 'gave up after 5 attempts');
    },
  );

  test('dueForRoute orders by createdAt ascending', () async {
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

    final due = await store.dueForRoute('route-A', now: 9999999);

    expect(due.map((r) => r.id), ['op-old', 'op-new']);
  });

  test(
    'routeIdsWithWork returns distinct routes with pending/failed/blocked rows '
    'and drops an all-synced route',
    () async {
      await store.enqueue(
        id: 'a-1',
        kind: PendingOpKind.checkIn,
        payload: const {},
        routeId: 'route-A',
      );
      await store.enqueue(
        id: 'a-2',
        kind: PendingOpKind.checkOut,
        payload: const {},
        routeId: 'route-A',
      );
      await store.markFailed('a-2', 'boom');
      await store.enqueue(
        id: 'b-1',
        kind: PendingOpKind.checkIn,
        payload: const {},
        routeId: 'route-B',
      );
      await store.markBlocked('b-1', 'stuck');
      await store.enqueue(
        id: 'c-1',
        kind: PendingOpKind.checkIn,
        payload: const {},
        routeId: 'route-C',
      );
      await store.markSynced('c-1');

      final routes = await store.routeIdsWithWork();

      expect(routes.toSet(), {'route-A', 'route-B'});
      expect(routes.length, 2);
    },
  );

  test(
    'markStopReleased parks the row as blocked on its released stop, and '
    'resetToPending un-parks it',
    () async {
      await store.enqueue(
        id: 'photo-1',
        kind: PendingOpKind.evidencePhoto,
        payload: const {'execution_id': 'exec-1'},
        routeId: 'route-A',
      );

      await store.markStopReleased(
        'photo-1',
        routeStopId: 'stop-1',
        error: 'HTTP 409 STOP_RELEASED',
      );

      final parked = (await store.blockedForRoute('route-A')).single;
      expect(parked.state, PendingOpState.blocked);
      expect(parked.releasedStopId, 'stop-1');
      expect(parked.lastError, 'HTTP 409 STOP_RELEASED');

      await store.resetToPending('photo-1');

      final reset = (await store.unsyncedForRoute('route-A')).single;
      expect(reset.releasedStopId, isNull);
    },
  );

  group('localPhotoCountFor', () {
    Future<void> enqueue(
      String id,
      PendingOpKind kind,
      String executionId,
    ) => store.enqueue(
      id: id,
      kind: kind,
      payload: {'execution_id': executionId},
      routeId: 'route-A',
    );

    test(
      'counts the execution photos in every state, and only those',
      () async {
        await enqueue('p-pending', PendingOpKind.evidencePhoto, 'exec-1');
        await enqueue('p-synced', PendingOpKind.evidencePhoto, 'exec-1');
        await enqueue('p-failed', PendingOpKind.evidencePhoto, 'exec-1');
        await enqueue('p-blocked', PendingOpKind.evidencePhoto, 'exec-1');
        await enqueue('p-other', PendingOpKind.evidencePhoto, 'exec-2');
        await enqueue('note', PendingOpKind.evidenceNote, 'exec-1');
        await enqueue('check-in', PendingOpKind.checkIn, 'exec-1');
        await store.markSynced('p-synced');
        await store.markFailed('p-failed', 'boom');
        await store.markBlocked('p-blocked', 'gave up');

        expect(await store.localPhotoCountFor('exec-1'), 4);
        expect(await store.localPhotoCountFor('exec-2'), 1);
        expect(await store.localPhotoCountFor('exec-3'), 0);
      },
    );
  });

  group('deletePendingPhoto', () {
    Future<void> enqueue(String id, PendingOpKind kind) => store.enqueue(
      id: id,
      kind: kind,
      payload: {'execution_id': 'exec-1'},
      routeId: 'route-A',
    );

    test('deletes a pending or failed photo and returns true', () async {
      await enqueue('p-pending', PendingOpKind.evidencePhoto);
      await enqueue('p-failed', PendingOpKind.evidencePhoto);
      await store.markFailed('p-failed', 'boom');

      expect(await store.deletePendingPhoto('p-pending'), isTrue);
      expect(await store.deletePendingPhoto('p-failed'), isTrue);
      expect(await store.unsyncedForRoute('route-A'), isEmpty);
      expect(await store.localPhotoCountFor('exec-1'), 0);
    });

    test('returns false for synced and non-photo rows, leaving them', () async {
      await enqueue('p-synced', PendingOpKind.evidencePhoto);
      await enqueue('note', PendingOpKind.evidenceNote);
      await store.markSynced('p-synced');

      expect(await store.deletePendingPhoto('p-synced'), isFalse);
      expect(await store.deletePendingPhoto('note'), isFalse);
      expect(await store.deletePendingPhoto('missing'), isFalse);
      expect(await store.localPhotoCountFor('exec-1'), 1);
      expect(await store.unsyncedForRoute('route-A'), hasLength(1));
    });
  });
}
