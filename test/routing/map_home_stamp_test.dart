import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/routing/map_home_screen.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/ui/batch_card.dart';
import 'package:route_monitor/ui/stamp_slot.dart';

import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';

// Final review I-5: the stamp falls on the batch card, so a check-out made
// with a building selected brings the card back first.

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
  testWidgets('a check-out with a building selected shows the card and its '
      'falling stamp', (tester) async {
    await pumpHome(
      tester,
      homeWith(
        repositoryWith(_inProgressInB1()),
        stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('pin-b1')),
        matching: find.textContaining('/'),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MapHomeScreen)),
    );
    expect(container.read(selectedBuildingProvider), 'b1');
    expect(find.byType(BatchCardView), findsNothing);

    await concludeWith(tester, 'v1.floor.1.sig');

    expect(container.read(selectedBuildingProvider), isNull);
    expect(find.byType(BatchCardView), findsOneWidget);
    final animating = tester
        .widgetList<StampSlot>(find.byType(StampSlot))
        .where((slot) => slot.animateStamp);
    expect(animating.map((slot) => slot.slot.stopId), ['s1']);
    expect(find.byType(BatchCardView).hitTestable(), findsOneWidget);
  });
}
