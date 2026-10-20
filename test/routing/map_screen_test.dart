import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/campus_map.dart';
import 'package:route_monitor/routing/map_screen.dart';
import 'package:route_monitor/routing/route_repository.dart';

import 'no_tiles_tile_provider.dart';

RouteStopSummary _stop({
  required String id,
  required int order,
  required String status,
  required double lat,
  required double lng,
  List<List<double>>? legGeometry,
}) => RouteStopSummary(
  id: id,
  orderIndex: order,
  status: status,
  servicePointName: 'Ponto $id',
  latitude: lat,
  longitude: lng,
  legGeometry: legGeometry,
);

RouteSummary _routeWith(List<RouteStopSummary> stops) => RouteSummary(
  id: 'r1',
  fieldWorkerName: 'João',
  routeDate: DateTime(2026, 8, 25),
  routeType: 'REGULAR',
  status: 'IN_PROGRESS',
  startedAt: null,
  stops: stops,
);

// s2 has real geometry, s3 has none -> one approximate leg.
final RouteSummary _fakeRoute = _routeWith([
  _stop(id: 's1', order: 1, status: 'DONE', lat: -7.210, lng: -35.910),
  _stop(
    id: 's2',
    order: 2,
    status: 'PENDING',
    lat: -7.213,
    lng: -35.913,
    legGeometry: const [
      [-35.910, -7.210],
      [-35.913, -7.213],
    ],
  ),
  _stop(
    id: 's3',
    order: 3,
    status: 'PENDING',
    lat: -7.216,
    lng: -35.916,
  ),
]);

Widget _harness(RouteSummary route) => MaterialApp(
  home: MapScreen(route: route, tileProviderOverride: NoTilesTileProvider()),
);

void main() {
  testWidgets('renders the campus map with a pin per stop', (tester) async {
    await tester.pumpWidget(_harness(_fakeRoute));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(AppStrings.mapAppBarTitle), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(CampusMap), findsOneWidget);

    final markerLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    expect(markerLayer.markers, hasLength(3));

    // The numbered pins actually painted.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('draws a solid leg for real geometry and a dashed one for the '
      'approximated hop', (tester) async {
    await tester.pumpWidget(_harness(_fakeRoute));
    await tester.pump(const Duration(milliseconds: 100));

    final polylineLayer = tester.widget<PolylineLayer>(
      find.byType(PolylineLayer),
    );
    expect(polylineLayer.polylines, hasLength(2));

    final dashed = polylineLayer.polylines
        .where((p) => p.pattern.segments != null)
        .toList();
    expect(dashed, hasLength(1));
    expect(dashed.single.points, hasLength(2));
  });

  testWidgets('feeds the base layer from the injected provider', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_fakeRoute));
    await tester.pump(const Duration(milliseconds: 100));

    final tileLayer = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(tileLayer.tileProvider, isA<NoTilesTileProvider>());
  });

  testWidgets('shows the "trajeto aproximado" caption when a leg is straight', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_fakeRoute));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(AppStrings.mapApproximateLegLabel), findsOneWidget);
  });

  testWidgets('hides the caption when every leg has real geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        _routeWith([
          _stop(id: 's1', order: 1, status: 'DONE', lat: -7.21, lng: -35.91),
          _stop(
            id: 's2',
            order: 2,
            status: 'PENDING',
            lat: -7.213,
            lng: -35.913,
            legGeometry: const [
              [-35.910, -7.210],
              [-35.913, -7.213],
            ],
          ),
        ]),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(AppStrings.mapApproximateLegLabel), findsNothing);
  });
}
