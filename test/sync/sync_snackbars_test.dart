import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/blocked_sync_screen.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/sync_status.dart';

import '../routing/map_home_harness.dart';
import '../support/fake_connectivity.dart';
import '../support/fake_route_repository.dart';

RouteSyncStatus _status(
  RouteSyncState state, {
  int pending = 0,
  int blocked = 0,
}) => RouteSyncStatus(
  routeId: 'r1',
  state: state,
  pending: pending,
  blocked: blocked,
);

RouteSummary _route() => routeWith(stops: [stopIn(id: 's1')]);

class _Home {
  _Home(this.worker, this.status);
  final RecordingSyncWorker worker;
  final StreamController<RouteSyncStatus> status;
}

Future<_Home> _pump(
  WidgetTester tester, {
  bool online = true,
  FakeSyncNotificationTaps? taps,
}) async {
  final status = statusController();
  addTearDown(status.close);
  final connectivity = FakeConnectivity(isOnline: online);
  addTearDown(connectivity.dispose);
  final worker = RecordingSyncWorker(statusStream: status.stream);
  await pumpHome(
    tester,
    homeWith(
      repositoryWith(_route()),
      syncWorker: worker,
      connectivity: connectivity,
      notificationTaps: taps,
    ),
  );
  return _Home(worker, status);
}

Future<void> _emit(WidgetTester tester, _Home home, RouteSyncStatus s) async {
  home.status.add(s);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('a new notice replaces the visible one', (tester) async {
    final home = await _pump(tester);
    await _emit(tester, home, _status(RouteSyncState.syncing, pending: 3));
    expect(find.text(AppStrings.syncSending(3)), findsOneWidget);

    await _emit(
      tester,
      home,
      _status(RouteSyncState.blocked, pending: 3, blocked: 1),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(AppStrings.syncBlockedNotice(1)), findsOneWidget);
    expect(find.text(AppStrings.syncSending(3)), findsNothing);
  });

  testWidgets('"Tudo enviado" follows a "Enviando"', (tester) async {
    final home = await _pump(tester);
    await _emit(tester, home, _status(RouteSyncState.syncing, pending: 2));
    await _emit(tester, home, _status(RouteSyncState.idle));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(AppStrings.routeAllSynced),
      ),
      findsOneWidget,
    );
  });

  testWidgets('offline "Enviar" syncs everything and retries the pull', (
    tester,
  ) async {
    final home = await _pump(tester, online: false);
    await _emit(tester, home, _status(RouteSyncState.idle, pending: 2));
    expect(find.text(AppStrings.syncWaiting(2)), findsOneWidget);

    await tester.tap(find.text(AppStrings.syncSendAction));
    await tester.pumpAndSettle();
    expect(home.worker.syncAllCount, 1);
  });

  testWidgets('blocked "Ver" opens BlockedSyncScreen', (tester) async {
    final home = await _pump(tester);
    await _emit(
      tester,
      home,
      _status(RouteSyncState.blocked, blocked: 1),
    );
    await tester.tap(find.text(AppStrings.syncSeeAction));
    await tester.pumpAndSettle();
    expect(find.byType(BlockedSyncScreen), findsOneWidget);
  });

  testWidgets('a tap on "needs attention" opens BlockedSyncScreen', (
    tester,
  ) async {
    final taps = FakeSyncNotificationTaps();
    await _pump(tester, taps: taps);

    taps.tap('r1');
    await tester.pumpAndSettle();

    expect(find.byType(BlockedSyncScreen), findsOneWidget);
  });

  testWidgets('a cold start from "needs attention" opens BlockedSyncScreen', (
    tester,
  ) async {
    await _pump(tester, taps: FakeSyncNotificationTaps(launchRoute: 'r1'));
    await tester.pumpAndSettle();

    expect(find.byType(BlockedSyncScreen), findsOneWidget);
  });

  testWidgets('the snackbar never overlaps "Escanear QR"', (tester) async {
    final home = await _pump(tester);
    await selectBuilding(tester, 'b1');
    for (final size in [0.5, 0.22]) {
      await snapSheetTo(tester, size);
      await _emit(tester, home, _status(RouteSyncState.syncing, pending: 1));
      await tester.pumpAndSettle();
      final snack = tester.getRect(
        find
            .descendant(
              of: find.byType(SnackBar),
              matching: find.byType(Material),
            )
            .first,
      );
      final scan = tester.getRect(scanQrButton());
      expect(snack.bottom, lessThanOrEqualTo(scan.top), reason: 'at $size');
      await _emit(tester, home, _status(RouteSyncState.idle));
    }
  });
}
