import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/monitoring/monitoring_api.dart';
import 'package:route_monitor/monitoring/monitoring_providers.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/sync/sync_triggers.dart';
import 'package:route_monitor/sync/sync_worker.dart';

import '../support/fake_connectivity.dart';
import '../support/fake_route_repository.dart';

/// Counts how often the notification endpoints are hit — invalidation of the
/// monitoring providers only shows up as a re-fetch the next time something
/// reads them (Riverpod invalidation is lazy).
class _FakeMonitoringApi implements MonitoringApi {
  int fetchNotificationsCount = 0;
  int unreadCountCount = 0;

  @override
  Future<List<AppNotification>> fetchNotifications({int limit = 30}) async {
    fetchNotificationsCount++;
    return const [];
  }

  @override
  Future<int> unreadCount() async {
    unreadCountCount++;
    return 0;
  }

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> reportPosition({
    required String routeId,
    required double latitude,
    required double longitude,
    required DateTime reportedAt,
    double? accuracyM,
  }) async => throw UnimplementedError('not exercised in this test');
}

/// Records `syncAll` calls and never drains — the triggers only care that the
/// worker was asked to sync.
class _RecordingSyncWorker implements SyncWorker {
  int syncAllCount = 0;

  @override
  Future<void> syncAll() async => syncAllCount++;

  @override
  Future<void> syncRoute(String routeId) async {}

  @override
  Stream<RouteSyncStatus> statusFor(String routeId) => const Stream.empty();

  @override
  Future<void> unblock(String operationId) async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  late FakeConnectivity connectivity;
  late _RecordingSyncWorker worker;

  setUp(() {
    connectivity = FakeConnectivity();
    worker = _RecordingSyncWorker();
  });

  tearDown(() => connectivity.dispose());

  Future<void> pump(WidgetTester tester, {Widget? child}) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityProvider.overrideWithValue(connectivity),
          syncWorkerProvider.overrideWithValue(worker),
        ],
        child: SyncTriggers(child: child ?? const SizedBox.shrink()),
      ),
    );
  }

  /// Same as [pump] but hands back the `ProviderContainer` behind the tree,
  /// so a test can `read(myDayProvider.future)` directly — invalidation
  /// alone is silent until something re-reads the provider.
  Future<ProviderContainer> pumpWithContainer(
    WidgetTester tester, {
    required RouteRepository routeRepository,
    MonitoringApi? monitoringApi,
  }) async {
    final container = ProviderContainer(
      overrides: [
        connectivityProvider.overrideWithValue(connectivity),
        syncWorkerProvider.overrideWithValue(worker),
        routeRepositoryProvider.overrideWithValue(routeRepository),
        if (monitoringApi != null)
          monitoringApiProvider.overrideWithValue(monitoringApi),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SyncTriggers(child: SizedBox.shrink()),
      ),
    );
    return container;
  }

  testWidgets('renders its child', (tester) async {
    await pump(
      tester,
      child: const Text('child-marker', textDirection: TextDirection.ltr),
    );
    expect(find.text('child-marker'), findsOneWidget);
  });

  testWidgets('regained connectivity triggers a drain', (tester) async {
    await pump(tester);
    expect(worker.syncAllCount, 0);

    connectivity.goOnline();
    await tester.pump();

    expect(worker.syncAllCount, 1);
  });

  testWidgets(
    'regained connectivity also invalidates myDayProvider, so the next '
    'read re-fetches (Task 14 — feeds formReconciliationProvider)',
    (tester) async {
      final routeRepository = FakeRouteRepository();
      final container = await pumpWithContainer(
        tester,
        routeRepository: routeRepository,
      );
      await container.read(myDayProvider.future);
      expect(routeRepository.fetchCount, 1);

      connectivity.goOnline();
      await tester.pump();

      expect((await container.read(myDayProvider.future)).route, isNull);
      expect(routeRepository.fetchCount, 2);
    },
  );

  testWidgets(
    'AppLifecycleState.resumed while online also invalidates '
    'myDayProvider',
    (tester) async {
      connectivity.isOnlineValue = true;
      final routeRepository = FakeRouteRepository();
      final container = await pumpWithContainer(
        tester,
        routeRepository: routeRepository,
      );
      await container.read(myDayProvider.future);
      expect(routeRepository.fetchCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect((await container.read(myDayProvider.future)).route, isNull);
      expect(routeRepository.fetchCount, 2);
    },
  );

  testWidgets(
    'AppLifecycleState.resumed also refreshes the notification providers '
    '(RF49 — a route assigned mid-shift must bump the bell badge)',
    (tester) async {
      connectivity.isOnlineValue = true;
      final routeRepository = FakeRouteRepository();
      final monitoringApi = _FakeMonitoringApi();
      final container = await pumpWithContainer(
        tester,
        routeRepository: routeRepository,
        monitoringApi: monitoringApi,
      );
      await container.read(unreadCountProvider.future);
      await container.read(notificationsProvider.future);
      expect(monitoringApi.unreadCountCount, 1);
      expect(monitoringApi.fetchNotificationsCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(await container.read(unreadCountProvider.future), 0);
      expect(await container.read(notificationsProvider.future), isEmpty);
      expect(monitoringApi.unreadCountCount, 2);
      expect(monitoringApi.fetchNotificationsCount, 2);
    },
  );

  testWidgets(
    'AppLifecycleState.resumed while offline does NOT invalidate '
    'myDayProvider — a re-fetch offline with no device snapshot would blank '
    'a previously-successful day with a generic error (Important-1)',
    (tester) async {
      final routeRepository = FakeRouteRepository();
      final container = await pumpWithContainer(
        tester,
        routeRepository: routeRepository,
      );
      await container.read(myDayProvider.future);
      expect(routeRepository.fetchCount, 1);

      connectivity.goOffline();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // Still the same, previously-fetched (successful) value — no
      // re-fetch attempted, so no `AsyncError` blanking the day.
      expect((await container.read(myDayProvider.future)).route, isNull);
      expect(routeRepository.fetchCount, 1);
    },
  );

  testWidgets('AppLifecycleState.resumed triggers a drain', (tester) async {
    await pump(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(worker.syncAllCount, 1);
  });

  testWidgets('paused / inactive do not trigger a drain', (tester) async {
    await pump(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(worker.syncAllCount, 0);
  });

  testWidgets('dispose removes the observer and cancels the subscription', (
    tester,
  ) async {
    await pump(tester);
    connectivity.goOnline();
    await tester.pump();
    expect(worker.syncAllCount, 1);

    // Drop SyncTriggers from the tree.
    await tester.pumpWidget(const SizedBox.shrink());

    connectivity.goOnline();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(worker.syncAllCount, 1);
  });
}
