import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_monitor/routing/campus_map.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

RouteStopSummary _stop({
  required String id,
  required int order,
  required String status,
  required double lat,
  required double lng,
  List<List<double>>? legGeometry,
  int batch = 1,
}) => RouteStopSummary(
  id: id,
  orderIndex: order,
  batchNumber: batch,
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
  status: 'IN_PROGRESS',
  startedAt: null,
  currentBatch: 1,
  stops: stops,
);

void main() {
  // stops[1] has a real [lng, lat] leg geometry; stops[2] has none.
  final route = _routeWith([
    _stop(id: 's1', order: 1, status: 'DONE', lat: -7.210, lng: -35.910),
    _stop(
      id: 's2',
      order: 2,
      status: 'PENDING',
      lat: -7.220,
      lng: -35.920,
      legGeometry: const [
        [-35.910, -7.210],
        [-35.915, -7.215],
        [-35.920, -7.220],
      ],
    ),
    _stop(
      id: 's3',
      order: 3,
      status: 'PENDING',
      lat: -7.230,
      lng: -35.930,
    ),
  ]);

  test('a real leg keeps the OSRM geometry, flipped to LatLng(lat, lng)', () {
    final data = buildRouteMapData(route);

    expect(data.legs[0].approximate, isFalse);
    expect(data.legs[0].points, const [
      LatLng(-7.210, -35.910),
      LatLng(-7.215, -35.915),
      LatLng(-7.220, -35.920),
    ]);
  });

  test('a null leg geometry becomes a straight approximate leg', () {
    final data = buildRouteMapData(route);

    expect(data.legs[1].approximate, isTrue);
    expect(data.legs[1].points, [
      data.stops[1].position,
      data.stops[2].position,
    ]);
    expect(data.legs[1].points, const [
      LatLng(-7.220, -35.920),
      LatLng(-7.230, -35.930),
    ]);
  });

  test('there is exactly one leg per stop after the first', () {
    final data = buildRouteMapData(route);

    expect(data.legs, hasLength(data.stops.length - 1));
  });

  test('stops carry the order index and position', () {
    final data = buildRouteMapData(route);

    expect(data.stops.map((s) => s.order), [1, 2, 3]);
    expect(data.stops[0].position, const LatLng(-7.210, -35.910));
  });

  test('pending is derived from status', () {
    final data = buildRouteMapData(route);

    expect(data.stops[0].pending, isFalse); // DONE
    expect(data.stops[1].pending, isTrue); // PENDING
  });

  test('a single-stop route has no legs', () {
    final data = buildRouteMapData(
      _routeWith([
        _stop(id: 's1', order: 1, status: 'PENDING', lat: -7.2, lng: -35.9),
      ]),
    );

    expect(data.stops, hasLength(1));
    expect(data.legs, isEmpty);
  });

  test('only the current batch is drawn, without released stops', () {
    final data = buildRouteMapData(
      RouteSummary(
        id: 'r1',
        fieldWorkerName: 'João',
        routeDate: DateTime(2026, 8, 25),
        status: 'IN_PROGRESS',
        startedAt: null,
        currentBatch: 2,
        stops: [
          _stop(id: 's1', order: 1, status: 'DONE', lat: -7.21, lng: -35.91),
          _stop(
            id: 's2',
            order: 2,
            status: 'RELEASED',
            lat: -7.22,
            lng: -35.92,
            batch: 2,
          ),
          _stop(
            id: 's3',
            order: 3,
            status: 'PENDING',
            lat: -7.23,
            lng: -35.93,
            batch: 2,
          ),
        ],
      ),
    );

    expect(data.stops.map((s) => s.order), [3]);
    expect(data.legs, isEmpty);
  });

  test('an empty leg geometry is treated as missing', () {
    final data = buildRouteMapData(
      _routeWith([
        _stop(id: 's1', order: 1, status: 'DONE', lat: -7.21, lng: -35.91),
        _stop(
          id: 's2',
          order: 2,
          status: 'PENDING',
          lat: -7.22,
          lng: -35.92,
          legGeometry: const [],
        ),
      ]),
    );

    expect(data.legs.single.approximate, isTrue);
  });

  testWidgets('loadCampusTiles wires the bundled style and PMTiles archive', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final tiles = await loadCampusTiles();

      // The style's single vector source is named `campus`; the theme must
      // reference it or VectorTileLayer's own assert would trip at runtime.
      expect(tiles.theme.tileSources, contains('campus'));
      expect(tiles.provider.type, TileProviderType.vector);
      expect(tiles.provider.maximumZoom, greaterThan(0));
    });
  });
}
