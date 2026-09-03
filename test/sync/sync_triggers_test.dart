import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/sync/sync_triggers.dart';
import 'package:route_monitor/sync/sync_worker.dart';

import '../support/fake_connectivity.dart';

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
