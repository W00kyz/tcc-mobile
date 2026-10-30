import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/map_home_screen.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/selected_building.dart';

import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';
import 'place_fixtures.dart';

// An outdoor place on the map home (spec 2026-10-30 §6): the same pin, the
// same stamp card, and no QR to scan.

/// Building b1 first, then the place p1 with two services.
RouteSummary _buildingThenPlace() => routeWith(
  stops: [
    stopIn(id: 's1', buildingName: 'Central de Aulas'),
    placeStopIn(id: 'p1s1', orderIndex: 2, servicePointName: 'Bebedouro'),
    placeStopIn(id: 'p1s2', orderIndex: 3, servicePointName: 'Lixeira'),
  ],
);

String? _selected(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(MapHomeScreen)),
).read(selectedBuildingProvider);

void main() {
  testWidgets('tapping the numbered pin of a place selects it', (tester) async {
    await pumpHome(tester, homeWith(repositoryWith(_buildingThenPlace())));

    expect(
      find.descendant(of: pinCircle('p1'), matching: find.text('2')),
      findsOneWidget,
    );
    await tapPin(tester, 'p1');

    expect(_selected(tester), 'p1');
    expect(shownFloorCard(tester).building.name, 'Praça central');
  });

  testWidgets('a place sheet names it, stamps each service, offers no scan', (
    tester,
  ) async {
    await pumpHome(tester, homeWith(repositoryWith(_buildingThenPlace())));

    await tapPin(tester, 'p1');

    expect(find.text('Praça central'), findsWidgets);
    expect(slotOf('p1s1'), findsOneWidget);
    expect(slotOf('p1s2'), findsOneWidget);
    expect(scanFooterButton(), findsNothing);
    expect(find.text(AppStrings.scanQrButton), findsNothing);
    expect(find.text(AppStrings.scanExitQrButton), findsNothing);
    expect(find.text(''), findsNothing);
  });

  testWidgets('a building sheet keeps its scan button', (tester) async {
    await pumpHome(tester, homeWith(repositoryWith(_buildingThenPlace())));

    await tapPin(tester, 'b1');

    expect(scanFooterButton(), findsOneWidget);
  });

  testWidgets('a stamp slot of a place opens its task, concluding closed', (
    tester,
  ) async {
    await pumpHome(tester, homeWith(repositoryWith(_buildingThenPlace())));
    await tapPin(tester, 'p1');

    await tester.tap(slotOf('p1s1'));
    await tester.pumpAndSettle();

    expect(find.text('Bebedouro'), findsWidgets);
    final conclude = find.widgetWithText(FilledButton, AppStrings.taskConclude);
    expect(tester.widget<FilledButton>(conclude).onPressed, isNull);
    expect(find.text(AppStrings.taskNeedsFloorCheckIn), findsNothing);
  });
}
