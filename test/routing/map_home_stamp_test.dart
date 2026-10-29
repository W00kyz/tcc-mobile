import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/routing/floor_actions.dart';
import 'package:route_monitor/routing/map_home_screen.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/selected_building.dart';
import 'package:route_monitor/ui/floor_card.dart';
import 'package:route_monitor/ui/map_sheet.dart';
import 'package:route_monitor/ui/stamp_slot.dart';

import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';

// Final review I-5: the stamp falls on the stamped stop's floor card, so a
// stamp made with another building selected (or none, the sheet hidden)
// selects the stop's building and the sheet shows it.

/// s1 in progress in "Central de Aulas" (b1), s2 pending in "Bloco B".
RouteSummary _inProgressInB1() => routeWith(
  stops: [
    stopIn(id: 's1', buildingName: 'Central de Aulas', status: 'IN_PROGRESS'),
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

void main() {
  testWidgets('a stamp with another building selected brings back the '
      "stop's card and its falling stamp", (tester) async {
    final route = _inProgressInB1();
    await pumpHome(
      tester,
      homeWith(
        repositoryWith(route),
        stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
      ),
    );
    await tester.tap(pinCircle('b2'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MapHomeScreen)),
    );
    expect(container.read(selectedBuildingProvider), 'b2');
    expect(shownFloorCard(tester).building.buildingId, 'b2');

    final ref = tester.element(find.byType(MapHomeScreen)) as WidgetRef;
    await concludeTask(ref, route, route.stops.first);
    await tester.pumpAndSettle();

    expect(container.read(selectedBuildingProvider), 'b1');
    expect(shownFloorCard(tester).building.buildingId, 'b1');
    final animating = tester
        .widgetList<StampSlot>(find.byType(StampSlot))
        .where((slot) => slot.animateStamp);
    expect(animating.map((slot) => slot.slot.stopId), ['s1']);
    expect(find.byType(FloorCard).hitTestable(), findsOneWidget);
  });

  testWidgets("a stamp with the sheet hidden opens the stop's building and "
      'keeps it there', (tester) async {
    final route = _inProgressInB1();
    await pumpHome(
      tester,
      homeWith(
        repositoryWith(route),
        stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MapHomeScreen)),
    );
    expect(find.byType(MapSheet), findsNothing);

    final ref = tester.element(find.byType(MapHomeScreen)) as WidgetRef;
    await concludeTask(ref, route, route.stops.first);
    await tester.pumpAndSettle();

    expect(container.read(selectedBuildingProvider), 'b1');
    expect(find.byType(MapSheet), findsOneWidget);
    final animating = tester
        .widgetList<StampSlot>(find.byType(StampSlot))
        .where((slot) => slot.animateStamp);
    expect(animating.map((slot) => slot.slot.stopId), ['s1']);
  });
}
