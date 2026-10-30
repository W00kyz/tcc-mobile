import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/building_card_model.dart';
import 'package:route_monitor/routing/building_sheet.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/floor_card.dart';

import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';
import 'place_fixtures.dart';

// The sheet's pieces for a building and for an outdoor place: a place has no
// floor to name and nothing to scan.

RouteSummary _day() => routeWith(
  stops: [
    stopIn(id: 's1', buildingName: 'Central de Aulas'),
    placeStopIn(id: 'p1s1', orderIndex: 2, servicePointName: 'Bebedouro'),
    placeStopIn(id: 'p1s2', orderIndex: 3, servicePointName: 'Lixeira'),
  ],
);

List<DayBuilding> _buildings() =>
    buildDayBuildings(_day(), const {}, const {}, const {});

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  ProviderScope(
    child: MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

void main() {
  group('BuildingSheetHeader', () {
    testWidgets('a place reads as its name alone, no floor', (tester) async {
      final place = _buildings().last;

      await _pump(
        tester,
        BuildingSheetHeader(building: place, selected: true),
      );

      expect(find.text('Praça central'), findsOneWidget);
      expect(find.textContaining('·'), findsNothing);
    });

    testWidgets('a building still reads as "Prédio · Andar"', (tester) async {
      final building = _buildings().first;

      await _pump(
        tester,
        BuildingSheetHeader(building: building, selected: false),
      );

      expect(
        find.text(AppStrings.buildingFloor('Central de Aulas', 'Térreo')),
        findsOneWidget,
      );
    });
  });

  group('scanFooterFor', () {
    test('a place has no scan footer, even with work open', () {
      final buildings = _buildings();

      expect(scanFooterFor(_day(), buildings, buildings.last), isNull);
    });

    test('a building with work open keeps its scan footer', () {
      final buildings = _buildings();

      expect(scanFooterFor(_day(), buildings, buildings.first), isNotNull);
    });
  });

  group('FloorCard of a place', () {
    testWidgets('lists one stamp per service and no floor title', (
      tester,
    ) async {
      final place = _buildings().last;

      await _pump(tester, FloorCard(building: place, onSlotTap: (_, _) {}));

      expect(slotOf('p1s1'), findsOneWidget);
      expect(slotOf('p1s2'), findsOneWidget);
      expect(find.text(AppStrings.floorCardTitle(2)), findsOneWidget);
      expect(find.text(''), findsNothing);
    });
  });
}
