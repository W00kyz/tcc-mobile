import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/sync/sync_triggers.dart';
import 'package:route_monitor/sync/sync_worker.dart';

import '../support/fake_connectivity.dart';

/// Records how many times `fetchMyRoutes` runs — `myRoutesProvider`
/// invalidation only shows up as a re-fetch the next time something reads
/// the provider (Riverpod invalidation is lazy), so the tests below re-read
/// `myRoutesProvider.future` after the trigger fires.
class _FakeRouteRepository implements RouteRepository {
  int fetchCount = 0;

  @override
  Future<List<RouteSummary>> fetchMyRoutes({DateTime? date}) async {
    fetchCount++;
    return const [];
  }

  @override
  Future<RouteSummary> startRoute({
    required String routeId,
    required double latitude,
    required double longitude,
    required DateTime startedAt,
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
  /// so a test can `read(myRoutesProvider.future)` directly — invalidation
  /// alone is silent until something re-reads the provider.
  Future<ProviderContainer> pumpWithContainer(
    WidgetTester tester, {
    required RouteRepository routeRepository,
  }) async {
    final container = ProviderContainer(
      overrides: [
        connectivityProvider.overrideWithValue(connectivity),
        syncWorkerProvider.overrideWithValue(worker),
        routeRepositoryProvider.overrideWithValue(routeRepository),
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
    'regained connectivity also invalidates myRoutesProvider, so the next '
    'read re-fetches (Task 14 — feeds formReconciliationProvider)',
    (tester) async {
      final routeRepository = _FakeRouteRepository();
      final container = await pumpWithContainer(
        tester,
        routeRepository: routeRepository,
      );
      await container.read(myRoutesProvider.future);
      expect(routeRepository.fetchCount, 1);

      connectivity.goOnline();
      await tester.pump();

      expect(await container.read(myRoutesProvider.future), isEmpty);
      expect(routeRepository.fetchCount, 2);
    },
  );

  testWidgets(
    'AppLifecycleState.resumed while online also invalidates '
    'myRoutesProvider',
    (tester) async {
      connectivity.isOnlineValue = true;
      final routeRepository = _FakeRouteRepository();
      final container = await pumpWithContainer(
        tester,
        routeRepository: routeRepository,
      );
      await container.read(myRoutesProvider.future);
      expect(routeRepository.fetchCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(await container.read(myRoutesProvider.future), isEmpty);
      expect(routeRepository.fetchCount, 2);
    },
  );

  testWidgets(
    'AppLifecycleState.resumed while offline does NOT invalidate '
    'myRoutesProvider — myRoutesProvider has no cache-on-error, so '
    'invalidating it offline would blank a previously-successful route list '
    'with a generic error (Important-1)',
    (tester) async {
      final routeRepository = _FakeRouteRepository();
      final container = await pumpWithContainer(
        tester,
        routeRepository: routeRepository,
      );
      await container.read(myRoutesProvider.future);
      expect(routeRepository.fetchCount, 1);

      connectivity.goOffline();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // Still the same, previously-fetched (successful) value — no
      // re-fetch attempted, so no `AsyncError` blanking the route list.
      expect(await container.read(myRoutesProvider.future), isEmpty);
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
