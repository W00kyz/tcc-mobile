import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/routing/campus_map.dart';
import 'package:route_monitor/routing/live_approach.dart';
import 'package:route_monitor/routing/map_home_screen.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/ui/map_sheet.dart';

import '../support/fake_connectivity.dart';
import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';

// The per-building sheet (plan Task 6): before the start only "Iniciar
// rota"; while the route is worked, the next (or tapped) building's floor
// card and one scan button gated by proximity and by the floor's stamps.

/// Building b1 at (-7.21, -35.91): s1 on the Térreo, s2 on the 1º andar.
/// Building b2 farther on, one stop on its 2º andar.
RouteSummary _twoBuildings() => routeWith(
  stops: [
    stopIn(id: 's1', buildingName: 'Central de Aulas'),
    stopIn(
      id: 's2',
      orderIndex: 2,
      buildingName: 'Central de Aulas',
      floorLabel: '1º andar',
    ),
    stopIn(
      id: 's3',
      orderIndex: 3,
      buildingId: 'b2',
      buildingName: 'Bloco B',
      floorLabel: '2º andar',
      latitude: -7.214,
      longitude: -35.906,
    ),
  ],
);

/// About [meters] due north of building b1.
LatLng _northOfB1(double meters) => LatLng(-7.21 + meters / 111320, -35.91);

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MapHomeScreen)));

Future<void> _placeWorker(WidgetTester tester, LatLng at) async {
  _container(tester).read(workerPositionProvider.notifier).update(at);
  await tester.pumpAndSettle();
}

List<String> _floorLabelsShown(WidgetTester tester) => [
  for (final floor in shownFloorCard(tester).building.floors) floor.label,
];

void main() {
  testWidgets('a route not started shows only "Iniciar rota", no sheet', (
    tester,
  ) async {
    await pumpHome(tester, homeWith(repositoryWith(null)));

    expect(
      find.widgetWithText(FilledButton, AppStrings.routeStartButton),
      findsOneWidget,
    );
    expect(find.byType(MapSheet), findsNothing);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
  });

  testWidgets('the start button is a 56dp pill with a 16dp gutter', (
    tester,
  ) async {
    await pumpHome(tester, homeWith(repositoryWith(null)));

    final button = find.widgetWithText(
      FilledButton,
      AppStrings.routeStartButton,
    );
    final rect = tester.getRect(button);
    final width = MediaQuery.sizeOf(tester.element(button)).width;
    expect(rect.height, 56);
    expect(rect.left, 16);
    expect(rect.right, width - 16);
  });

  testWidgets('a paused route says why just above "Retomar"', (tester) async {
    final paused = routeWith(
      status: 'PAUSED',
      stops: [
        stopIn(id: 's1', status: 'RELEASED', releaseReason: 'LEFT_CAMPUS'),
      ],
    );
    await pumpHome(tester, homeWith(repositoryWith(paused)));

    final reason = find.text(
      AppStrings.routePausedReason(
        AppStrings.releaseReasonLabel('LEFT_CAMPUS'),
      ),
    );
    final resume = find.widgetWithText(
      FilledButton,
      AppStrings.dayResumeButton,
    );
    expect(reason, findsOneWidget);
    expect(
      tester.getBottomLeft(reason).dy,
      lessThan(tester.getTopLeft(resume).dy),
    );
    expect(find.byType(DraggableScrollableSheet), findsNothing);
  });

  testWidgets('with no sheet the map keeps clear of the start bar only', (
    tester,
  ) async {
    await pumpHome(tester, homeWith(repositoryWith(null)));

    final map = tester.widget<CampusMap>(find.byType(CampusMap));
    // 56dp pill + 16dp off the bottom (no system inset) + 24dp air.
    expect(map.overlayPadding.bottom, 56 + 16 + 24);
  });

  testWidgets('with no sheet a snackbar sits just above the start bar', (
    tester,
  ) async {
    await pumpHome(
      tester,
      homeWith(repositoryWith(null), connectivity: FakeConnectivity()),
    );

    await tester.tap(
      find.widgetWithText(FilledButton, AppStrings.routeStartButton),
    );
    await tester.pumpAndSettle();

    final snack = find.widgetWithText(SnackBar, AppStrings.routeStartOffline);
    expect(snack, findsOneWidget);
    final surface = tester.getRect(
      find.descendant(of: snack, matching: find.byType(Material)).first,
    );
    final bar = tester.getRect(
      find.widgetWithText(FilledButton, AppStrings.routeStartButton),
    );
    expect(surface.bottom, lessThanOrEqualTo(bar.top));
    expect(bar.top - surface.bottom, lessThan(24));
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('IN_PROGRESS shows the next building with its floors in order', (
    tester,
  ) async {
    await pumpHome(tester, homeWith(repositoryWith(_twoBuildings())));

    expect(find.text(AppStrings.buildingSheetNext), findsOneWidget);
    expect(
      find.text(AppStrings.buildingFloor('Central de Aulas', 'Térreo')),
      findsOneWidget,
    );
    expect(shownFloorCard(tester).building.buildingId, 'b1');
    expect(_floorLabelsShown(tester), ['Térreo', '1º andar']);
    expect(find.text(AppStrings.floorCardTitle(2)), findsOneWidget);
    expect(slotOf('s1'), findsOneWidget);
    expect(slotOf('s3'), findsNothing);
  });

  testWidgets('tapping pin 2 swaps the card to building 2, "Prédio '
      'selecionado"', (tester) async {
    await pumpHome(tester, homeWith(repositoryWith(_twoBuildings())));

    await tester.tap(pinCircle('b2'));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.buildingSheetSelected), findsOneWidget);
    expect(shownFloorCard(tester).building.buildingId, 'b2');
    expect(_floorLabelsShown(tester), ['2º andar']);
    expect(find.text(AppStrings.floorCardTitle(1)), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.buildingSheetNext), findsOneWidget);
    expect(shownFloorCard(tester).building.buildingId, 'b1');
  });

  testWidgets('the scan button is off 200 m away and on at 10 m', (
    tester,
  ) async {
    await pumpHome(tester, homeWith(repositoryWith(_twoBuildings())));

    await _placeWorker(tester, _northOfB1(200));
    expect(find.text(AppStrings.scanQrButton), findsOneWidget);
    expect(scanFooterEnabled(tester), isFalse);
    expect(find.text(AppStrings.scanNeedsProximity), findsOneWidget);

    await _placeWorker(tester, _northOfB1(10));
    expect(scanFooterEnabled(tester), isTrue);
    expect(find.text(AppStrings.scanNeedsProximity), findsNothing);
  });

  testWidgets('a floor checked in with a task in progress reads "Escanear QR '
      'de saída", off until the task is stamped', (tester) async {
    final progress = FakeStopProgressStore({'s1': 'exec-1'});
    final route = routeWith(
      stops: [
        stopIn(id: 's1', status: 'IN_PROGRESS'),
        stopIn(id: 's2', orderIndex: 2, floorLabel: '1º andar'),
      ],
    );
    await pumpHome(
      tester,
      homeWith(repositoryWith(route), stopProgressStore: progress),
    );
    await _placeWorker(tester, _northOfB1(10));

    expect(find.text(AppStrings.scanExitQrButton), findsOneWidget);
    expect(scanFooterEnabled(tester), isFalse);
    expect(find.text(AppStrings.scanExitNeedsAllTasks), findsOneWidget);

    await progress.markStamped('s1');
    _container(tester).invalidate(stopProgressForProvider('s1'));
    await tester.pumpAndSettle();

    expect(scanFooterEnabled(tester), isTrue);
    expect(find.text(AppStrings.scanExitNeedsAllTasks), findsNothing);
  });

  testWidgets('a floor open in another building blocks the entry scan here', (
    tester,
  ) async {
    final route = routeWith(
      stops: [
        stopIn(
          id: 's1',
          buildingName: 'Central de Aulas',
          status: 'IN_PROGRESS',
        ),
        stopIn(
          id: 's2',
          orderIndex: 2,
          buildingId: 'b2',
          buildingName: 'Bloco B',
          floorLabel: '2º andar',
          latitude: -7.214,
          longitude: -35.906,
        ),
      ],
    );
    await pumpHome(
      tester,
      homeWith(
        repositoryWith(route),
        stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
      ),
    );
    // The sheet stays on the building whose floor is open.
    expect(shownFloorCard(tester).building.buildingId, 'b1');

    await tester.tap(pinCircle('b2'));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.scanQrButton), findsOneWidget);
    expect(scanFooterEnabled(tester), isFalse);
    expect(
      find.text(AppStrings.scanFinishOpenFloor('Central de Aulas', 'Térreo')),
      findsOneWidget,
    );
  });

  testWidgets('a finished building hides the scan button and reads "Prédio '
      'concluído"', (tester) async {
    final route = routeWith(
      stops: [
        stopIn(id: 's1', status: 'DONE'),
        stopIn(
          id: 's2',
          orderIndex: 2,
          buildingId: 'b2',
          buildingName: 'Bloco B',
          latitude: -7.214,
          longitude: -35.906,
        ),
      ],
    );
    await pumpHome(tester, homeWith(repositoryWith(route)));

    await tester.tap(pinCircle('b1'));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.floorCardDone), findsOneWidget);
    expect(scanFooterButton(), findsNothing);
  });

  testWidgets('the entry scan checks in every open task of the floor', (
    tester,
  ) async {
    final store = InMemoryLocalWriteStore();
    await pumpHome(
      tester,
      homeWith(repositoryWith(_twoBuildings()), localWriteStore: store),
    );

    await scanWith(tester, qrOf('Térreo'));

    final checkIns = (await store.unsyncedForRoute(
      'r1',
    )).where((row) => row.kind == PendingOpKind.checkIn);
    expect(checkIns.map((row) => row.payload['route_stop_id']), ['s1']);
    expect(find.text(AppStrings.floorCheckInDone(1)), findsOneWidget);
  });

  testWidgets('tapping an open task slot opens its task dialog', (
    tester,
  ) async {
    await pumpHome(tester, homeWith(repositoryWith(_twoBuildings())));

    await tapInSheet(tester, slotOf('s2'));

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Sala s2'), findsOneWidget);
  });

  testWidgets('tapping a done task slot opens nothing', (tester) async {
    final route = routeWith(
      stops: [
        stopIn(id: 's1', status: 'DONE'),
        stopIn(id: 's2', orderIndex: 2),
      ],
    );
    await pumpHome(tester, homeWith(repositoryWith(route)));

    await tapInSheet(tester, slotOf('s1'));

    expect(find.byType(Dialog), findsNothing);
  });
}
