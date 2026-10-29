import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_monitor/routing/building_card_model.dart';
import 'package:route_monitor/routing/campus_map.dart';
import 'package:route_monitor/routing/campus_map_layers.dart';
import 'package:route_monitor/routing/live_approach.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/ui/app_theme.dart';

import 'no_tiles_tile_provider.dart';

// What CampusMap draws over the route (2026-10-28): circles on the line,
// the live first leg, and pin names gated by zoom.

RouteStopSummary _stop(
  String id, {
  required int order,
  required String status,
  required LatLng at,
  required String building,
  List<List<double>>? leg,
}) => RouteStopSummary(
  id: id,
  orderIndex: order,
  batchNumber: 1,
  status: status,
  servicePointName: 'Sala $id',
  buildingId: building,
  buildingName: 'Bloco $building',
  floorLabel: 'Térreo',
  latitude: at.latitude,
  longitude: at.longitude,
  legGeometry: leg,
);

// s1 done in b1; s2 next in b2, reached by a real leg that OSRM snapped to
// the street (its last point is not the stop); s3 pending in b3, no leg.
final RouteSummary _route = RouteSummary(
  id: 'r1',
  fieldWorkerName: 'João',
  routeDate: DateTime(2026, 10, 28),
  status: 'IN_PROGRESS',
  startedAt: null,
  currentBatch: 1,
  stops: [
    _stop(
      's1',
      order: 1,
      status: 'DONE',
      at: const LatLng(-7.210, -35.910),
      building: 'b1',
    ),
    _stop(
      's2',
      order: 2,
      status: 'PENDING',
      at: const LatLng(-7.213, -35.913),
      building: 'b2',
      leg: const [
        [-35.910, -7.210],
        [-35.9129, -7.2129],
      ],
    ),
    _stop(
      's3',
      order: 3,
      status: 'PENDING',
      at: const LatLng(-7.216, -35.916),
      building: 'b3',
    ),
  ],
);

const LiveApproach _approach = LiveApproach(
  points: [LatLng(-7.2115, -35.9115), LatLng(-7.21295, -35.91295)],
  approximate: false,
);

void main() {
  final buildings = buildDayBuildings(_route, const {}, const {}, const {});

  group('the live first leg', () {
    test('without a position the data is exactly as before', () {
      final data = buildRouteMapData(_route, buildings: buildings);

      expect(data.approach, isNull);
      expect(data.drawnLegs, data.legs);
    });

    test('replaces the server leg into the next stop instead of doubling '
        'it', () {
      final data = buildRouteMapData(
        _route,
        buildings: buildings,
        approach: _approach,
      );

      expect(data.legs, hasLength(2));
      expect(data.drawnLegs, hasLength(2));
      expect(
        data.drawnLegs.where((l) => l.kind == LegKind.next).single,
        same(data.approach),
      );
      expect(data.approach!.points, _approach.points);
      expect(data.approach!.approximate, isFalse);
    });

    test('an approximate approach stays dashed', () {
      const straight = LiveApproach(
        points: [LatLng(-7.2115, -35.9115), LatLng(-7.213, -35.913)],
        approximate: true,
      );
      final data = buildRouteMapData(
        _route,
        buildings: buildings,
        approach: straight,
      );

      expect(data.approach!.approximate, isTrue);
    });
  });

  group('walks bridging the snapped street ends', () {
    // The street path starts ~110 m from the worker and ends ~6 m short of
    // s2, as OSRM snaps both ends to the nearest mapped road.
    const worker = LatLng(-7.2108, -35.9122);
    const stopS2 = LatLng(-7.213, -35.913);
    const snapped = LiveApproach(
      points: [LatLng(-7.2115, -35.9115), LatLng(-7.21295, -35.91295)],
      approximate: false,
      destination: stopS2,
    );

    test('a dashed walk joins the worker to the street start and the '
        'street end to the stop', () {
      final data = buildRouteMapData(
        _route,
        buildings: buildings,
        approach: snapped,
        worker: worker,
      );

      expect(data.walkIn!.points, [worker, snapped.points.first]);
      expect(data.walkOut!.points, [snapped.points.last, stopS2]);
      for (final walk in [data.walkIn!, data.walkOut!]) {
        expect(walk.walk, isTrue);
        expect(walk.approximate, isTrue);
        expect(walk.kind, LegKind.next);
      }
      expect(data.drawnLegs, containsAll([data.walkIn, data.walkOut]));
    });

    test('no walk when the ends are on the spot or unknown', () {
      final data = buildRouteMapData(
        _route,
        buildings: buildings,
        approach: _approach,
        worker: _approach.points.first,
      );

      expect(data.walkIn, isNull);
      expect(data.walkOut, isNull);
    });

    test(
      'the line starts under the worker and its circle sits on the stop',
      () {
        final data = buildRouteMapData(
          _route,
          buildings: buildings,
          approach: snapped,
          worker: worker,
        );
        final points = routeLineCircles(
          data,
          FieldPalette.light,
        ).map((c) => c.point).toList();

        expect(points, contains(stopS2));
        expect(points, isNot(contains(snapped.points.first)));
        expect(points, isNot(contains(snapped.points.last)));
      },
    );

    test('a walk is drawn thinner than the street path, and dashed', () {
      final data = buildRouteMapData(
        _route,
        buildings: buildings,
        approach: snapped,
        worker: worker,
      );
      final line = legPolyline(data.walkIn!, FieldPalette.light);

      expect(line.strokeWidth, 4);
      expect(legPolyline(data.approach!, FieldPalette.light).strokeWidth, 6);
      expect(line.pattern, isNot(const StrokePattern.solid()));
    });
  });

  group('circles on the route line', () {
    const p = FieldPalette.light;

    test('sit at each leg endpoint: next with a thicker ring', () {
      final data = buildRouteMapData(_route, buildings: buildings);
      final circles = routeLineCircles(data, p);

      expect(circles.map((c) => c.point), [
        const LatLng(-7.216, -35.916), // s3, the straight leg's end
        const LatLng(-7.2129, -35.9129), // s2, the snapped line end
      ]);
      expect((circles[0].color, circles[0].borderColor), (p.white, p.ink));
      expect(circles[0].borderStrokeWidth, 2);
      expect(circles[1].borderStrokeWidth, 3);
    });

    test('a done destination fills moss', () {
      final walked = RouteSummary(
        id: 'r1',
        fieldWorkerName: 'João',
        routeDate: DateTime(2026, 10, 28),
        status: 'IN_PROGRESS',
        startedAt: null,
        currentBatch: 1,
        stops: [
          _route.stops[0],
          _stop(
            's2',
            order: 2,
            status: 'DONE',
            at: const LatLng(-7.213, -35.913),
            building: 'b2',
          ),
        ],
      );
      final data = buildRouteMapData(
        walked,
        buildings: buildDayBuildings(walked, const {}, const {}, const {}),
      );

      final circle = routeLineCircles(data, p).single;
      expect((circle.color, circle.borderColor), (p.moss, p.moss));
    });

    test('with a live approach: one at the worker end, one at its stop', () {
      final data = buildRouteMapData(
        _route,
        buildings: buildings,
        approach: _approach,
      );
      final circles = routeLineCircles(data, p);

      expect(circles.map((c) => c.point), [
        _approach.points.first,
        const LatLng(-7.216, -35.916),
        _approach.points.last,
      ]);
      expect(circles.last.borderStrokeWidth, 3);
    });
  });

  group('pin names follow the zoom', () {
    Future<MapController> pumpMap(
      WidgetTester tester, {
      String? selected,
    }) async {
      final controller = MapController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: CampusMap(
            data: buildRouteMapData(_route, buildings: buildings),
            buildings: buildings,
            selectedBuildingId: selected,
            controller: controller,
            tileProviderOverride: NoTilesTileProvider(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      return controller;
    }

    Future<void> zoomTo(
      WidgetTester tester,
      MapController controller,
      double zoom,
    ) async {
      controller.move(const LatLng(-7.213, -35.913), zoom);
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('hidden below 15.5, the number always shown', (
      tester,
    ) async {
      final controller = await pumpMap(tester);

      await zoomTo(tester, controller, 15.4);

      expect(find.text('Bloco b2'), findsNothing);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('shown at 15.5 and above', (tester) async {
      final controller = await pumpMap(tester);

      await zoomTo(tester, controller, kPinLabelMinZoom);
      expect(find.text('Bloco b2'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      // Centred on b2; the other pins fall off-screen this close.
      await zoomTo(tester, controller, 18);
      expect(find.text('Bloco b2'), findsOneWidget);
    });

    testWidgets('a selected pin keeps its name at any zoom', (tester) async {
      final controller = await pumpMap(tester, selected: 'b2');

      await zoomTo(tester, controller, 13);

      expect(find.text('Bloco b2'), findsOneWidget);
      expect(find.text('Bloco b3'), findsNothing);
    });
  });

  testWidgets('the map strokes the approach and draws the line circles', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: CampusMap(
          data: buildRouteMapData(
            _route,
            buildings: buildings,
            approach: _approach,
          ),
          buildings: buildings,
          workerPosition: _approach.points.first,
          tileProviderOverride: NoTilesTileProvider(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    const p = FieldPalette.light;
    final lines = tester
        .widget<PolylineLayer>(find.byType(PolylineLayer))
        .polylines;
    expect(lines.map((l) => l.points), [
      [const LatLng(-7.213, -35.913), const LatLng(-7.216, -35.916)],
      _approach.points,
    ]);
    expect((lines.last.color, lines.last.strokeWidth), (p.moss, 6));
    final circles = tester.widget<CircleLayer>(find.byType(CircleLayer));
    expect(circles.circles, hasLength(3));
    expect(find.byKey(const ValueKey('worker-position')), findsOneWidget);
  });
}
