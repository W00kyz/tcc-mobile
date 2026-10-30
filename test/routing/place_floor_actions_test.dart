import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/routing/building_card_model.dart';
import 'package:route_monitor/routing/floor_actions.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/stop_completion.dart';

import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';
import 'place_fixtures.dart';

// A stop completed by location has no QR: the floor flows (entry scan, exit
// scan) must never pick it up.

/// A location stop wearing a floor id, as no real payload does: the guard
/// must hold on the completion, not on the floor id happening to be null.
RouteStopSummary _locationStopWithFloor() => const RouteStopSummary(
  id: 'p1s1',
  orderIndex: 1,
  batchNumber: 1,
  status: 'PENDING',
  servicePointName: 'Bebedouro',
  buildingId: 'b1',
  buildingName: 'Prédio',
  floorLabel: 'Térreo',
  floorId: 'f1',
  completion: StopCompletion.location,
  latitude: -7.2,
  longitude: -35.9,
);

FloorRow _stampedPlaceFloor() => const FloorRow(
  floorId: null,
  label: '',
  slots: [
    CardSlot(
      stopId: 'p1s1',
      state: SlotState.stamped,
      floorLabel: '',
      stampedAt: null,
      pendingSync: false,
      releaseReason: null,
      stampRotationDeg: 0,
    ),
  ],
);

void main() {
  test('check-in candidates leave out a stop completed by location', () {
    final route = routeWith(
      stops: [
        _locationStopWithFloor(),
        stopIn(id: 's1', floorId: 'f1', orderIndex: 2),
      ],
    );

    final ids = checkInCandidates(route, 'f1').map((s) => s.id);

    expect(ids, ['s1']);
  });

  test('a place stop is no check-in candidate of any floor id', () {
    final route = routeWith(stops: [placeStopIn(id: 'p1s1')]);

    expect(checkInCandidates(route, 'p1'), isEmpty);
  });

  test('a place never has an open floor, whatever its slots say', () {
    final route = routeWith(
      stops: [placeStopIn(id: 'p1s1', status: 'IN_PROGRESS')],
    );
    final place = buildDayBuildings(route, const {}, const {}, const {}).single;

    expect(place.floors.single.hasOpenCheckIn, isTrue);
    expect(openFloorOf(place), isNull);
  });

  testWidgets('the exit flow ignores a stamped location stop', (tester) async {
    final route = routeWith(stops: [placeStopIn(id: 'p1s1')]);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () =>
                  checkOutFloor(context, ref, route, _stampedPlaceFloor()),
              child: const Text('exit'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('exit'));
    await tester.pumpAndSettle();

    expect(find.byType(ScanScreen), findsNothing);
  });
}
