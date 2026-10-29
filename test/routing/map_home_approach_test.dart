import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/routing/approach_api.dart';
import 'package:route_monitor/routing/route_repository.dart';

import '../support/fake_route_repository.dart';
import 'fake_approach_api.dart';
import 'map_home_harness.dart';

// The live first leg on the home map: from the worker's position (here the
// "Minha posição" read, FakeLocationService at -7.23, -35.88) to the card's
// next stop.

final RouteSummary _route = routeWith(
  stops: [
    stopIn(id: 's1', status: 'DONE'),
    stopIn(
      id: 's2',
      orderIndex: 2,
      buildingId: 'b2',
      latitude: -7.214,
      longitude: -35.906,
    ),
  ],
);

const _street = [
  LatLng(-7.23, -35.88),
  LatLng(-7.22, -35.89),
  LatLng(-7.214, -35.906),
];

Future<void> _locate(WidgetTester tester) async {
  await tester.tap(find.byTooltip(AppStrings.myPositionTooltip));
  await tester.pumpAndSettle();
}

List<Polyline> _lines(WidgetTester tester) =>
    tester.widget<PolylineLayer>(find.byType(PolylineLayer)).polylines;

void main() {
  testWidgets('no position: no request, the map draws as before', (
    tester,
  ) async {
    final api = FakeApproachApi();
    await pumpHome(tester, homeWith(repositoryWith(_route), approachApi: api));

    expect(api.calls, isEmpty);
    expect(_lines(tester), hasLength(1));
  });

  testWidgets('a position draws the street path to the next stop', (
    tester,
  ) async {
    final api = FakeApproachApi(
      leg: const ApproachLeg(
        routeStopId: 's2',
        points: _street,
        distanceM: 300,
        durationS: 240,
      ),
    );
    await pumpHome(tester, homeWith(repositoryWith(_route), approachApi: api));

    await _locate(tester);

    expect(api.calls, [(-7.23, -35.88)]);
    // The server leg s1 → s2 gives way to the live one: drawn once.
    expect(_lines(tester).single.points, _street);
    expect(find.text(AppStrings.mapApproximateLegLabel), findsNothing);
  });

  testWidgets('offline: a dashed straight line, captioned', (tester) async {
    final api = FakeApproachApi(
      error: DioException(requestOptions: RequestOptions()),
    );
    await pumpHome(tester, homeWith(repositoryWith(_route), approachApi: api));

    await _locate(tester);

    final line = _lines(tester).single;
    expect(line.points, const [LatLng(-7.23, -35.88), LatLng(-7.214, -35.906)]);
    expect(line.pattern.segments, isNotNull);
    expect(find.text(AppStrings.mapApproximateLegLabel), findsOneWidget);
  });

  testWidgets('the leg heads for the day model next task, past one reported '
      'impossible on this device', (tester) async {
    final store = InMemoryLocalWriteStore();
    // s1 impeded here, not yet synced: the server still has it PENDING.
    await store.enqueue(
      id: 'imp-1',
      kind: PendingOpKind.impediment,
      routeId: 'r1',
      payload: const {'scope': 'STOP', 'route_stop_id': 's1'},
    );
    final route = routeWith(
      stops: [
        stopIn(id: 's1'),
        stopIn(
          id: 's2',
          orderIndex: 2,
          buildingId: 'b2',
          latitude: -7.214,
          longitude: -35.906,
        ),
      ],
    );
    final api = FakeApproachApi(
      error: DioException(requestOptions: RequestOptions()),
    );
    await pumpHome(
      tester,
      homeWith(repositoryWith(route), approachApi: api, localWriteStore: store),
    );

    await _locate(tester);

    expect(
      _lines(tester).map((l) => l.points),
      anyElement(
        equals(const [LatLng(-7.23, -35.88), LatLng(-7.214, -35.906)]),
      ),
    );
  });
}
