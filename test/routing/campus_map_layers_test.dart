import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/routing/building_card_model.dart';
import 'package:route_monitor/routing/campus_map_layers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/ui/app_theme.dart';

import 'place_fixtures.dart';

// The pin an outdoor place wears on the map: the building's numbered drop.

DayBuilding _place({String status = 'PENDING'}) {
  final route = RouteSummary(
    id: 'r1',
    fieldWorkerName: 'João',
    routeDate: DateTime(2026, 10, 30),
    status: 'IN_PROGRESS',
    startedAt: null,
    currentBatch: 1,
    stops: [placeStopIn(id: 'p1s1', status: status)],
  );
  return buildDayBuildings(route, const {}, const {}, const {}).single;
}

Future<void> _pumpMarker(
  WidgetTester tester,
  DayBuilding place, {
  VoidCallback? onTap,
}) {
  final marker = buildingMarker(
    place,
    selected: false,
    dimmed: false,
    onTap: onTap,
  );
  return tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Center(child: marker.child)),
    ),
  );
}

void main() {
  testWidgets('a place pin shows its number and name, and a tap selects', (
    tester,
  ) async {
    var taps = 0;
    await _pumpMarker(tester, _place(), onTap: () => taps++);

    expect(find.text('1'), findsOneWidget);
    expect(find.text('Praça central'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pin-p1')));
    expect(taps, 1);
  });

  testWidgets('a complete place pin turns to a check, no number', (
    tester,
  ) async {
    await _pumpMarker(tester, _place(status: 'DONE'));

    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });
}
