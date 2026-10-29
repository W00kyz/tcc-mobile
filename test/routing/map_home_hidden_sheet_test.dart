import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/campus_map.dart';
import 'package:route_monitor/routing/floor_actions.dart';
import 'package:route_monitor/routing/map_home_screen.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/selected_building.dart';
import 'package:route_monitor/ui/map_sheet.dart';

import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';

// The building sheet is hidden until a pin is tapped, and the worker can hide
// it again by dragging it down: the map then shows whole, with "Minha
// posição" and the snackbars near the bottom edge.

RouteSummary _twoBuildings() => routeWith(
  stops: [
    stopIn(id: 's1', buildingName: 'Central de Aulas'),
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

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MapHomeScreen)));

Finder _myPosition() => find.byTooltip(AppStrings.myPositionTooltip);

/// Drags the open sheet's handle below the closed snap and lets it go.
Future<void> _dragSheetAway(WidgetTester tester) async {
  await snapSheetTo(tester, 0.22);
  await tester.drag(
    find.byKey(const ValueKey('map-sheet-handle')),
    const Offset(0, 250),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a route worked with no building selected shows no sheet', (
    tester,
  ) async {
    await pumpHome(tester, homeWith(repositoryWith(_twoBuildings())));

    expect(_container(tester).read(selectedBuildingProvider), isNull);
    expect(find.byType(MapSheet), findsNothing);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(scanQrButton(), findsNothing);
    expect(find.byType(CampusMap), findsOneWidget);
    expect(find.text(AppStrings.collectionChip), findsOneWidget);
  });

  testWidgets('"Minha posição" sits near the bottom edge with no sheet', (
    tester,
  ) async {
    await pumpHome(tester, homeWith(repositoryWith(_twoBuildings())));

    final button = tester.getRect(_myPosition());
    // 24dp off the system bar (none here) + 16dp of air.
    expect(button.bottom, 1400 - 24 - 16);
    expect(button.right, 420 - 16);
    expect(_myPosition().hitTestable(), findsOneWidget);
  });

  testWidgets('with no sheet the map keeps clear of the bottom edge only', (
    tester,
  ) async {
    await pumpHome(tester, homeWith(repositoryWith(_twoBuildings())));

    final map = tester.widget<CampusMap>(find.byType(CampusMap));
    expect(map.overlayPadding.bottom, 24 + 24);
  });

  testWidgets('a pin tap brings the sheet at half height', (tester) async {
    await pumpHome(tester, homeWith(repositoryWith(_twoBuildings())));

    await tapPin(tester, 'b1');

    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    expect(sheet.controller!.size, closeTo(kMapSheetInitial, 0.001));
    expect(find.text(AppStrings.buildingSheetNext), findsOneWidget);
    final map = tester.widget<CampusMap>(find.byType(CampusMap));
    expect(map.overlayPadding.bottom, 1400 * kMapSheetInitial + 24);
  });

  testWidgets('dragging the sheet below its closed snap hides it and clears '
      'the selection', (tester) async {
    await pumpHome(tester, homeWith(repositoryWith(_twoBuildings())));
    await tapPin(tester, 'b1');
    expect(_container(tester).read(selectedBuildingProvider), 'b1');

    await _dragSheetAway(tester);

    expect(find.byType(MapSheet), findsNothing);
    expect(_container(tester).read(selectedBuildingProvider), isNull);
    expect(
      tester.widget<CampusMap>(find.byType(CampusMap)).selectedBuildingId,
      isNull,
    );
    expect(tester.getRect(_myPosition()).bottom, 1400 - 24 - 16);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a hidden sheet comes back on the next pin tap, at half', (
    tester,
  ) async {
    await pumpHome(tester, homeWith(repositoryWith(_twoBuildings())));
    await tapPin(tester, 'b1');
    await _dragSheetAway(tester);

    await tapPin(tester, 'b1');

    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    expect(sheet.controller!.size, closeTo(kMapSheetInitial, 0.001));
    expect(find.byType(MapSheet), findsOneWidget);
  });

  testWidgets('a tap on the map still hides the sheet', (tester) async {
    await pumpHome(tester, homeWith(repositoryWith(_twoBuildings())));
    await tapPin(tester, 'b1');

    tester.widget<CampusMap>(find.byType(CampusMap)).onMapTap!.call();
    await tester.pumpAndSettle();

    expect(find.byType(MapSheet), findsNothing);
  });

  testWidgets('a snackbar with no sheet floats just above the bottom edge', (
    tester,
  ) async {
    await pumpHome(
      tester,
      homeWith(
        repositoryWith(_twoBuildings()),
        locationService: FailingLocationService(),
      ),
    );

    await tester.tap(_myPosition());
    await tester.pumpAndSettle();

    final snack = find.widgetWithText(
      SnackBar,
      AppStrings.routeLocationUnavailable,
    );
    expect(snack, findsOneWidget);
    final surface = tester.getRect(
      find.descendant(of: snack, matching: find.byType(Material)).first,
    );
    // 24dp reach + the 8dp the lane always leaves: far below the half line.
    expect(1400 - surface.bottom, 24 + 8);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('a stamp from the task dialog keeps the sheet on its building', (
    tester,
  ) async {
    final route = _twoBuildings();
    await pumpHomeWithSheet(
      tester,
      homeWith(
        repositoryWith(route),
        stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
      ),
    );
    final ref = tester.element(find.byType(MapHomeScreen)) as WidgetRef;

    await concludeTask(ref, route, route.stops.first);
    await tester.pumpAndSettle();

    expect(_container(tester).read(selectedBuildingProvider), 'b1');
    expect(shownFloorCard(tester).building.buildingId, 'b1');
    expect(shownFloorCard(tester).animateStopId, 's1');
  });

  testWidgets('a floor check-in keeps the selection and the sheet', (
    tester,
  ) async {
    await pumpHomeWithSheet(tester, homeWith(repositoryWith(_twoBuildings())));

    await scanWith(tester, qrOf('Térreo'));

    expect(_container(tester).read(selectedBuildingProvider), 'b1');
    expect(find.byType(MapSheet), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });
}
