import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/execution_providers.dart'
    show appDatabaseProvider;
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
import 'package:route_monitor/sync/background_sync.dart';
import 'package:route_monitor/sync/sync_notifications.dart';
import 'package:route_monitor/sync/sync_progress.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/sync/sync_triggers.dart';
import 'package:route_monitor/sync/sync_worker.dart';

import '../support/fake_connectivity.dart';
import '../support/in_memory_database.dart';

/// Replays a fixed list of progress events on `syncAll`, the way the real
/// worker reports each row it delivers.
class FakeSyncWorker implements SyncWorker {
  FakeSyncWorker([this.steps = const []]);

  final List<SyncProgress> steps;
  int syncAllCount = 0;
  final StreamController<SyncProgress> _progress =
      StreamController<SyncProgress>.broadcast(sync: true);

  @override
  Stream<SyncProgress> get progress => _progress.stream;

  @override
  Future<void> syncAll() async {
    syncAllCount++;
    steps.forEach(_progress.add);
  }

  @override
  Future<void> syncRoute(String routeId) async {}

  @override
  Stream<RouteSyncStatus> statusFor(String routeId) => const Stream.empty();

  @override
  Future<void> unblock(String operationId) async {}

  @override
  Future<void> dispose() => _progress.close();
}

/// Records every call, in order, as a short readable string.
class FakeSyncNotificationPublisher implements SyncNotificationPublisher {
  final List<String> calls = [];

  @override
  Future<void> progress(int done, int total) async =>
      calls.add('progress $done/$total');

  @override
  Future<void> finished(int sent) async => calls.add('finished $sent');

  @override
  Future<void> needsAttention(int blocked) async =>
      calls.add('needsAttention $blocked');

  @override
  Future<void> clear() async => calls.add('clear');
}

class FakeBackgroundSyncScheduler implements BackgroundSyncScheduler {
  int scheduled = 0;

  @override
  Future<void> scheduleDrain() async => scheduled++;
}

const _threeRows = [
  SyncProgress(done: 1, total: 3),
  SyncProgress(done: 2, total: 3),
  SyncProgress(done: 3, total: 3),
];

void main() {
  group('runBackgroundDrain', () {
    test('drains and reports progress then finished', () async {
      final worker = FakeSyncWorker(_threeRows);
      final notifications = FakeSyncNotificationPublisher();

      await runBackgroundDrain(
        worker: worker,
        notifications: notifications,
        appInForeground: () async => false,
        blockedCount: () async => 0,
      );

      expect(worker.syncAllCount, 1);
      expect(notifications.calls, [
        'progress 1/3',
        'progress 2/3',
        'progress 3/3',
        'finished 3',
      ]);
    });

    test('reports needsAttention when rows end blocked', () async {
      final worker = FakeSyncWorker(const [SyncProgress(done: 1, total: 2)]);
      final notifications = FakeSyncNotificationPublisher();

      await runBackgroundDrain(
        worker: worker,
        notifications: notifications,
        appInForeground: () async => false,
        blockedCount: () async => 1,
      );

      expect(notifications.calls, contains('needsAttention 1'));
      expect(
        notifications.calls.any((call) => call.startsWith('finished')),
        isFalse,
      );
    });

    test('no notifications while the app is in the foreground', () async {
      final worker = FakeSyncWorker(_threeRows);
      final notifications = FakeSyncNotificationPublisher();

      await runBackgroundDrain(
        worker: worker,
        notifications: notifications,
        appInForeground: () async => true,
        blockedCount: () async => 1,
      );

      expect(worker.syncAllCount, 1);
      expect(notifications.calls, isEmpty);
    });

    test(
      'a drain that leaves rows unsent clears instead of finishing',
      () async {
        final worker = FakeSyncWorker(const [SyncProgress(done: 1, total: 2)]);
        final notifications = FakeSyncNotificationPublisher();

        await runBackgroundDrain(
          worker: worker,
          notifications: notifications,
          appInForeground: () async => false,
          blockedCount: () async => 0,
        );

        expect(notifications.calls, ['progress 1/2', 'clear']);
      },
    );
  });

  group('SyncTriggers and the background drain', () {
    late AppDatabase db;
    late FakeConnectivity connectivity;
    late FakeBackgroundSyncScheduler scheduler;

    setUp(() {
      db = inMemoryDatabase();
      connectivity = FakeConnectivity();
      scheduler = FakeBackgroundSyncScheduler();
    });

    tearDown(() async {
      await connectivity.dispose();
      await db.close();
    });

    Future<void> pump(WidgetTester tester) {
      return tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            connectivityProvider.overrideWithValue(connectivity),
            syncWorkerProvider.overrideWithValue(FakeSyncWorker()),
            backgroundSyncSchedulerProvider.overrideWithValue(scheduler),
          ],
          child: const SyncTriggers(child: SizedBox.shrink()),
        ),
      );
    }

    Future<void> enqueueCheckIn(WidgetTester tester) {
      return tester.runAsync(
        () => DriftLocalWriteStore(db).enqueue(
          id: 'op-1',
          kind: PendingOpKind.checkIn,
          payload: const {'route_stop_id': 'stop-1'},
          routeId: 'route-R',
        ),
      );
    }

    Future<void> goTo(WidgetTester tester, AppLifecycleState state) async {
      tester.binding.handleAppLifecycleStateChanged(state);
      // The flag and the schedule are real SQLite I/O, off the fake clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    Future<bool?> foregroundFlag(WidgetTester tester) =>
        tester.runAsync(() => DriftSyncMetaStore(db).getAppInForeground());

    testWidgets('paused lifecycle with pending work schedules a drain', (
      tester,
    ) async {
      await pump(tester);
      await enqueueCheckIn(tester);

      await goTo(tester, AppLifecycleState.paused);

      expect(scheduler.scheduled, 1);
    });

    testWidgets('paused with no work does not', (tester) async {
      await pump(tester);

      await goTo(tester, AppLifecycleState.paused);

      expect(scheduler.scheduled, 0);
    });

    testWidgets('writes the foreground flag on pause and on resume', (
      tester,
    ) async {
      await pump(tester);

      await goTo(tester, AppLifecycleState.paused);
      expect(await foregroundFlag(tester), isFalse);

      await goTo(tester, AppLifecycleState.resumed);
      expect(await foregroundFlag(tester), isTrue);
    });
  });
}
