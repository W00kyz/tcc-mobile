import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/routing/campus_map.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/building_pin.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'no_tiles_tile_provider.dart';

RouteStopSummary _stop({
  required String id,
  required int order,
  required String status,
  required double lat,
  required double lng,
  List<List<double>>? legGeometry,
  int batch = 1,
  String building = 'b1',
}) => RouteStopSummary(
  buildingId: building,
  buildingName: 'Prédio',
  floorLabel: 'Térreo',
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

  test('each leg takes its kind from the stop it leads to', () {
    // s1 DONE, s2 the next PENDING, s3 PENDING after it.
    final data = buildRouteMapData(route);

    expect(data.legs.map((leg) => leg.kind), [LegKind.next, LegKind.rest]);
  });

  test("a local check-out walks the leg before the card's next stop", () {
    final card = buildBatchCard(route, {
      's2': LocalStopState(
        status: StopLocalStatus.done,
        updatedAt: DateTime(2026),
      ),
    }, const {});

    final data = buildRouteMapData(route, card: card);

    expect(data.legs.map((leg) => leg.kind), [LegKind.walked, LegKind.next]);
  });

  group('the map widget', () {
    Widget harness(
      RouteSummary route, {
      String? selected,
      LatLng? worker,
      ValueChanged<BuildingGroup>? onPinTap,
    }) {
      final card = buildBatchCard(route, const {}, const {});
      return MaterialApp(
        theme: buildAppTheme(),
        home: CampusMap(
          data: buildRouteMapData(route, card: card),
          groups: card.groups,
          selectedBuildingId: selected,
          workerPosition: worker,
          onPinTap: onPinTap,
          tileProviderOverride: NoTilesTileProvider(),
        ),
      );
    }

    final twoBuildings = _routeWith([
      _stop(id: 's1', order: 1, status: 'DONE', lat: -7.210, lng: -35.910),
      _stop(
        id: 's2',
        order: 2,
        status: 'PENDING',
        lat: -7.213,
        lng: -35.913,
        building: 'b2',
        legGeometry: const [
          [-35.910, -7.210],
          [-35.913, -7.213],
        ],
      ),
      _stop(
        id: 's3',
        order: 3,
        status: 'PENDING',
        lat: -7.2131,
        lng: -35.9131,
        building: 'b2',
      ),
    ]);

    testWidgets('draws one pin per building, not per stop', (tester) async {
      await tester.pumpWidget(harness(twoBuildings));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(BuildingPin), findsNWidgets(2));
      expect(find.text('1/1'), findsOneWidget);
      expect(find.text('0/2'), findsOneWidget);
    });

    testWidgets('a selected building grows and the others dim', (
      tester,
    ) async {
      await tester.pumpWidget(harness(twoBuildings, selected: 'b2'));
      await tester.pump(const Duration(milliseconds: 100));

      final pins = tester
          .widgetList<BuildingPin>(find.byType(BuildingPin))
          .toList();
      final b1 = pins.singleWhere((pin) => pin.group.buildingId == 'b1');
      final b2 = pins.singleWhere((pin) => pin.group.buildingId == 'b2');
      expect(b1.dimmed, isTrue);
      expect(b2.selected, isTrue);
      expect(b2.dimmed, isFalse);
    });

    testWidgets('a pin tap reports its building', (tester) async {
      BuildingGroup? tapped;
      await tester.pumpWidget(
        harness(twoBuildings, onPinTap: (group) => tapped = group),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('0/2'));
      // The map's own double-tap recogniser holds the arena until it times
      // out.
      await tester.pumpAndSettle();

      expect(tapped?.buildingId, 'b2');
    });

    testWidgets('styles legs: next in moss 6px, the rest in ink 3px', (
      tester,
    ) async {
      await tester.pumpWidget(harness(twoBuildings));
      await tester.pump(const Duration(milliseconds: 100));

      const p = FieldPalette.light;
      final lines = tester
          .widget<PolylineLayer>(find.byType(PolylineLayer))
          .polylines;
      expect(lines, hasLength(2));
      expect((lines[0].color, lines[0].strokeWidth), (p.moss, 6));
      expect((lines[1].color, lines[1].strokeWidth), (p.ink, 3));
      // The second leg has no geometry: drawn dashed.
      expect(lines[1].pattern.segments, isNotNull);
      expect(lines[0].pattern.segments, isNull);
    });

    testWidgets("draws the worker's position when known", (tester) async {
      await tester.pumpWidget(
        harness(twoBuildings, worker: const LatLng(-7.211, -35.911)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('worker-position')), findsOneWidget);
    });

    testWidgets('feeds the base layer from the injected provider', (
      tester,
    ) async {
      await tester.pumpWidget(harness(twoBuildings));
      await tester.pump(const Duration(milliseconds: 100));

      final tileLayer = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(tileLayer.tileProvider, isA<NoTilesTileProvider>());
    });

    testWidgets('shows the "trajeto aproximado" caption when a leg is '
        'straight, and hides it otherwise', (tester) async {
      await tester.pumpWidget(harness(twoBuildings));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(AppStrings.mapApproximateLegLabel), findsOneWidget);

      await tester.pumpWidget(
        harness(
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
  });
}
