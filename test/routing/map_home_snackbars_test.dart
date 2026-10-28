import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/home_top_bar.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/sync_status.dart';

import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';

// Final review I-2 and M-1: every map-home snackbar goes through the home's
// lane, so it floats over the sheet (never on "Escanear QR") and a sync
// notice never closes a snackbar it does not own.

RouteSummary _inProgressStopRoute() => routeWith(
  stops: [stopIn(id: 's1', status: 'IN_PROGRESS')],
);

/// Two pending stops: "Escanear QR" stays after the first check-in.
RouteSummary _twoPendingRoute() => routeWith(
  stops: [
    stopIn(id: 's1', latitude: -7.23, longitude: -35.88),
    stopIn(id: 's2', orderIndex: 2, latitude: -7.25, longitude: -35.90),
  ],
);

RouteSyncStatus _status(RouteSyncState state, int pending) => RouteSyncStatus(
  routeId: 'r1',
  state: state,
  pending: pending,
  blocked: 0,
);

/// Pumps [steps] × 100 ms, recording which of [texts] were on screen.
Future<Set<String>> _watch(
  WidgetTester tester,
  List<String> texts, {
  required int steps,
}) async {
  final seen = <String>{};
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    for (final text in texts) {
      if (find.text(text).evaluate().isNotEmpty) seen.add(text);
    }
  }
  return seen;
}

/// The snackbar's visible surface — the [SnackBar] widget itself spans its
/// margin too.
Rect _surfaceOf(WidgetTester tester, Finder snack) => tester.getRect(
  find.descendant(of: snack, matching: find.byType(Material)).first,
);

void _expectApart(Rect snack, Rect other) =>
    expect(snack.overlaps(other), isFalse, reason: '$snack overlaps $other');

void main() {
  testWidgets('online check-out, then Enviando, then Tudo enviado: the '
      'confirmation keeps its time and no stale Enviando is left', (
    tester,
  ) async {
    final status = statusController();
    await pumpHome(
      tester,
      homeWith(
        repositoryWith(_inProgressStopRoute()),
        syncWorker: RecordingSyncWorker(statusStream: status.stream),
      ),
    );

    await concludeWith(tester, 'v1.floor.1.sig');
    expect(find.text(AppStrings.routeCheckOutDone), findsOneWidget);

    status.add(_status(RouteSyncState.syncing, 1));
    await tester.pump();
    await tester.pump();
    status.add(_status(RouteSyncState.idle, 0));
    final texts = [
      AppStrings.routeCheckOutDone,
      AppStrings.syncSending(1),
      AppStrings.routeAllSynced,
    ];
    final early = await _watch(tester, texts, steps: 20);

    expect(tester.takeException(), isNull);
    expect(early, {AppStrings.routeCheckOutDone});
    expect(find.text(AppStrings.routeCheckOutDone), findsOneWidget);

    final later = await _watch(tester, texts, steps: 120);
    expect(later, contains(AppStrings.routeAllSynced));
    expect(later, isNot(contains(AppStrings.syncSending(1))));
    expect(find.text(AppStrings.syncSending(1)), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  for (final size in [0.5, 0.22]) {
    testWidgets('at $size the check-in confirmation stays off Escanear QR', (
      tester,
    ) async {
      await pumpHome(tester, homeWith(repositoryWith(_twoPendingRoute())));
      await snapSheetTo(tester, size);

      await scanWith(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      final snack = find.widgetWithText(SnackBar, AppStrings.routeCheckInDone);
      expect(snack, findsOneWidget);
      _expectApart(_surfaceOf(tester, snack), tester.getRect(scanQrButton()));
      await tester.pumpAndSettle(const Duration(seconds: 6));
    });
  }

  testWidgets('at the open snap a snackbar stays under the top bar and off '
      'Escanear QR (M-1)', (tester) async {
    await pumpHome(tester, homeWith(repositoryWith(_twoPendingRoute())));
    await snapSheetTo(tester, 0.9);

    await scanWith(tester, 'v1.floor.1.sig');
    await tester.pumpAndSettle();

    final snack = find.widgetWithText(SnackBar, AppStrings.routeCheckInDone);
    expect(snack, findsOneWidget);
    final rect = _surfaceOf(tester, snack);
    final topBar = tester.getRect(find.byType(HomeTopBar));
    expect(rect.top, greaterThan(topBar.bottom));
    _expectApart(rect, tester.getRect(scanQrButton()));
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });
}
