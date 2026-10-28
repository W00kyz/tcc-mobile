import 'dart:convert';

// Theme is hidden from material: vector_tile_renderer exports its own Theme and
// that is the one VectorTileLayer wants. Same choice VectorTileLayer makes.
import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/routing/building_card_model.dart';
import 'package:route_monitor/routing/campus_map_layers.dart';
import 'package:route_monitor/routing/live_approach.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart'
    show Theme, ThemeReader;

/// Everything [CampusMap] needs to draw one route, already projected to
/// screen-space types. Building this is a pure transform ([buildRouteMapData]),
/// kept apart from the widget so it can be unit-tested without `pumpWidget`
/// (Ruling 10 — the map stays a thin seam over flutter_map + vector_map_tiles).
class RouteMapData {
  RouteMapData({required this.stops, required this.legs, this.approach});

  /// The stops in visiting order.
  final List<RouteMapStop> stops;

  /// One leg per stop after the first: `legs[i]` joins `stops[i]` to
  /// `stops[i + 1]`.
  final List<RouteMapLeg> legs;

  /// The live first leg, from the worker to the next stop; null without a
  /// worker position. Kept out of [legs] so the camera does not re-frame
  /// every time the worker moves.
  final RouteMapLeg? approach;

  /// What the map strokes: [legs], then [approach]. While an approach is
  /// live, the server's leg into the next stop (it starts at the previous
  /// stop, not at the worker) is hidden rather than drawn twice.
  List<RouteMapLeg> get drawnLegs => [
    for (final leg in legs)
      if (approach == null || leg.kind != LegKind.next) leg,
    ?approach,
  ];
}

/// A single numbered pin on the map.
class RouteMapStop {
  RouteMapStop({
    required this.position,
    required this.order,
    required this.pending,
  });

  /// Where the pin sits.
  final LatLng position;

  /// The 1-based visiting order shown inside the pin.
  final int order;

  /// `true` while the stop still has to be visited; drives a distinct pin
  /// colour from an already-done stop.
  final bool pending;
}

/// Where a leg sits in the walk (redesign §6.3): already behind the worker,
/// the one to the next stop, or still ahead.
enum LegKind { walked, next, rest }

/// One segment of the drawn trajectory.
class RouteMapLeg {
  RouteMapLeg({
    required this.points,
    required this.approximate,
    this.kind = LegKind.rest,
    this.destinationDone = false,
  });

  /// The polyline vertices, in `LatLng(lat, lng)` order.
  final List<LatLng> points;

  /// `true` when the backend gave no real geometry for this leg and the line
  /// is just a straight hop between the two stops — drawn dashed so the field
  /// worker does not read it as a surveyed path.
  final bool approximate;

  /// Drives the stroke: `rule` walked, moss 6px next, ink 3px rest.
  final LegKind kind;

  /// The stop this leg reaches is done: its circle on the line fills moss.
  final bool destinationDone;
}

/// Pure transform from the API summary to what the map draws: the stops of
/// the whole day, every batch, in route order — the line shows where the day
/// goes, not just the current batch.
///
/// The OSRM leg geometry arrives as `[lng, lat]` pairs; every pair is flipped
/// to `LatLng(lat, lng)`. A stop with no `legGeometry` gets a straight,
/// [RouteMapLeg.approximate] leg between it and its predecessor. Each leg
/// takes its [LegKind] from the stop it leads to, as [buildings] draw that
/// stop (the server status alone when none are given): a done stop's leg was
/// walked, the next stop's leg is the next one. Released stops are left out,
/// impeded ones stay. A live [approach] becomes [RouteMapData.approach],
/// drawn as the next leg.
///
/// ```dart
/// final data = buildRouteMapData(route, buildings: buildings);
/// CampusMap(data: data, buildings: buildings);
/// ```
RouteMapData buildRouteMapData(
  RouteSummary route, {
  List<DayBuilding>? buildings,
  LiveApproach? approach,
}) {
  final states = _slotStates(
    buildings ?? buildDayBuildings(route, const {}, const {}, const {}),
  );
  final drawn = (route.stops.where((s) => states[s.id] != null).toList()
    ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex)));
  return RouteMapData(
    stops: [
      for (final stop in drawn)
        RouteMapStop(
          position: LatLng(stop.latitude, stop.longitude),
          order: stop.orderIndex,
          pending: stop.status == 'PENDING',
        ),
    ],
    legs: [
      for (var i = 1; i < drawn.length; i++)
        _legTo(drawn[i], drawn[i - 1], states[drawn[i].id]),
    ],
    approach: approach == null ? null : _approachLeg(approach),
  );
}

/// The state each visible stop is drawn in; a released stop has none (it
/// went back to the pool and is not on the map).
Map<String, SlotState> _slotStates(List<DayBuilding> buildings) => {
  for (final slot in buildings.expand((b) => b.floors).expand((f) => f.slots))
    if (slot.state != SlotState.released) slot.stopId: slot.state,
};

RouteMapLeg _legTo(
  RouteStopSummary stop,
  RouteStopSummary previous,
  SlotState? state,
) {
  final geometry = stop.legGeometry;
  final real = geometry != null && geometry.isNotEmpty;
  return RouteMapLeg(
    points: real
        ? [for (final point in geometry) LatLng(point[1], point[0])]
        : [
            LatLng(previous.latitude, previous.longitude),
            LatLng(stop.latitude, stop.longitude),
          ],
    approximate: !real,
    kind: _legKind(state),
    destinationDone: state == SlotState.done,
  );
}

RouteMapLeg _approachLeg(LiveApproach approach) => RouteMapLeg(
  points: approach.points,
  approximate: approach.approximate,
  kind: LegKind.next,
);

LegKind _legKind(SlotState? destination) => switch (destination) {
  SlotState.done || SlotState.released || SlotState.impeded => LegKind.walked,
  SlotState.next => LegKind.next,
  _ => LegKind.rest,
};

/// From here up the building pins show their names (the middle of the
/// 12–19 zoom range); below, only the circle and its `n/m`.
const double kPinLabelMinZoom = 15.5;

/// Where the map opens when there is nothing to fit (no route yet): the
/// UFCG Campina Grande campus.
const LatLng kCampusCenter = LatLng(-7.2167, -35.9097);

/// The bundled offline base map plus the day's building pins and trajectory
/// (redesign §6.3).
///
/// The base layer is the `assets/campus.pmtiles` vector archive rendered with
/// `assets/campus-style.json`. Tests pass [tileProviderOverride] — a no-op
/// raster [TileProvider] — so `flutter_test` never spins up vector_map_tiles'
/// async tile pipeline; production leaves it null and gets the real PMTiles
/// layer via [loadCampusTiles].
///
/// A "trajeto aproximado" caption is overlaid whenever any leg is a straight
/// approximation (spec §6.2), so the field worker does not read the dashed
/// line as a surveyed path.
///
///     CampusMap(data: data, buildings: buildings, onPinTap: select)
class CampusMap extends StatelessWidget {
  const CampusMap({
    required this.data,
    this.buildings = const [],
    this.selectedBuildingId,
    this.workerPosition,
    this.controller,
    this.onPinTap,
    this.onMapTap,
    this.overlayPadding = const EdgeInsets.all(48),
    this.tileProviderOverride,
    super.key,
  });

  /// The route to draw.
  final RouteMapData data;

  /// One pin per building of the day, numbered in route order.
  final List<DayBuilding> buildings;

  /// The building whose pin grows; every other pin dims.
  final String? selectedBuildingId;

  /// The worker's last known position, drawn as an ink dot with a halo.
  final LatLng? workerPosition;

  final MapController? controller;
  final ValueChanged<DayBuilding>? onPinTap;

  /// A tap on the map itself (not a pin) — clears the selection.
  final VoidCallback? onMapTap;

  /// The part of the map hidden by the top bar and the sheet: the camera
  /// fits the route inside the rest, and the caption sits above the sheet.
  final EdgeInsets overlayPadding;

  /// Test seam: when set, the base map is a plain [TileLayer] fed by this
  /// provider instead of the PMTiles vector layer.
  final TileProvider? tileProviderOverride;

  List<LatLng> get _allPoints => [
    for (final stop in data.stops) stop.position,
    for (final leg in data.legs) ...leg.points,
  ];

  @override
  Widget build(BuildContext context) {
    final p =
        material.Theme.of(context).extension<FieldPalette>() ??
        FieldPalette.light;
    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: controller,
          options: _options(p),
          children: [
            _CampusBaseLayer(
              tileProviderOverride: tileProviderOverride,
              ground: p.mapGround,
            ),
            PolylineLayer(
              polylines: [
                for (final leg in data.drawnLegs) legPolyline(leg, p),
              ],
            ),
            CircleLayer(circles: routeLineCircles(data, p)),
            // Rebuilt with the camera: the pin labels follow the zoom.
            Builder(
              builder: (context) => MarkerLayer(
                markers: _markers(p, MapCamera.of(context).zoom),
              ),
            ),
            _RefitOnNewRoute(points: _allPoints, padding: overlayPadding),
          ],
        ),
        if (data.drawnLegs.any((leg) => leg.approximate))
          ApproximateLegend(padding: overlayPadding),
      ],
    );
  }

  MapOptions _options(FieldPalette p) {
    final points = _allPoints;
    return MapOptions(
      initialCenter: kCampusCenter,
      initialZoom: 16,
      initialCameraFit: points.isEmpty ? null : _fitTo(points, overlayPadding),
      minZoom: 12,
      maxZoom: 19,
      backgroundColor: p.mapGround,
      onTap: onMapTap == null ? null : (_, _) => onMapTap!(),
      interactionOptions: const InteractionOptions(
        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
      ),
    );
  }

  List<Marker> _markers(FieldPalette p, double zoom) {
    final selected = selectedBuildingId;
    final position = workerPosition;
    final nextId = nextBuilding(buildings)?.buildingId;
    return [
      if (position != null) workerMarker(position, p),
      for (final building in buildings)
        buildingMarker(
          building,
          selected: building.buildingId == selected,
          dimmed: selected != null && building.buildingId != selected,
          isNext: building.buildingId == nextId,
          // A selected pin keeps its name at any zoom.
          showLabel:
              zoom >= kPinLabelMinZoom || building.buildingId == selected,
          onTap: onPinTap == null ? null : () => onPinTap!(building),
        ),
    ];
  }
}

CameraFit _fitTo(List<LatLng> points, EdgeInsets padding) =>
    CameraFit.coordinates(coordinates: points, padding: padding, maxZoom: 18);

/// Re-frames the camera when the drawn route changes (the day loaded after
/// the map, or a new batch came in): `initialCameraFit` only runs once.
class _RefitOnNewRoute extends StatefulWidget {
  const _RefitOnNewRoute({required this.points, required this.padding});

  final List<LatLng> points;
  final EdgeInsets padding;

  @override
  State<_RefitOnNewRoute> createState() => _RefitOnNewRouteState();
}

class _RefitOnNewRouteState extends State<_RefitOnNewRoute> {
  @override
  void didUpdateWidget(_RefitOnNewRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    final points = widget.points;
    if (points.isEmpty || _samePoints(points, oldWidget.points)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      MapController.of(context).fitCamera(_fitTo(points, widget.padding));
    });
  }

  bool _samePoints(List<LatLng> a, List<LatLng> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Base map: the injected no-op provider under test, the real PMTiles vector
/// layer otherwise. The load future is held in state so a rebuild does not
/// re-open the archive.
class _CampusBaseLayer extends StatefulWidget {
  const _CampusBaseLayer({
    required this.tileProviderOverride,
    required this.ground,
  });

  final TileProvider? tileProviderOverride;

  /// Shown while the archive loads (the style's own background after).
  final Color ground;

  @override
  State<_CampusBaseLayer> createState() => _CampusBaseLayerState();
}

class _CampusBaseLayerState extends State<_CampusBaseLayer> {
  Future<CampusTiles>? _tiles;

  @override
  void initState() {
    super.initState();
    if (widget.tileProviderOverride == null) {
      _tiles = loadCampusTiles();
    }
  }

  @override
  Widget build(BuildContext context) {
    final override = widget.tileProviderOverride;
    if (override != null) {
      return TileLayer(tileProvider: override);
    }
    final tilesFuture = _tiles;
    if (tilesFuture == null) {
      return ColoredBox(color: widget.ground);
    }
    return FutureBuilder<CampusTiles>(
      future: tilesFuture,
      builder: (context, snapshot) {
        final tiles = snapshot.data;
        if (tiles == null) {
          // A plain filled box, never a spinner: a spinner animates forever and
          // would keep `pumpAndSettle` from ever returning.
          return ColoredBox(color: widget.ground);
        }
        return VectorTileLayer(
          theme: tiles.theme,
          tileProviders: TileProviders({'campus': tiles.provider}),
          fileCacheTtl: Duration.zero,
          // The archive stops at z15 while the map zooms to z19; raster mode
          // would upscale z15 images (blocky shapes, labels sized for z15).
          // Vector mode re-renders at each zoom: sharp roads and street names.
          layerMode: VectorTileLayerMode.vector,
        );
      },
    );
  }
}

/// The parsed offline base map: the render theme and the PMTiles tile source.
class CampusTiles {
  CampusTiles({required this.theme, required this.provider});

  /// Rendering theme read from `assets/campus-style.json`.
  final Theme theme;

  /// Vector tiles served from the bundled `assets/campus.pmtiles` archive.
  final PmTilesVectorTileProvider provider;
}

/// Loads and wires the bundled offline base map.
///
/// `assets/campus.pmtiles` is read as bytes (`rootBundle.load`) and opened
/// in-memory with [PmTilesArchive.fromBytes] — the pmtiles package's
/// path/URL constructors cannot see an asset. `assets/campus-style.json` is a
/// MapLibre style whose single `campus` vector source is filled in here by
/// name via [TileProviders]. The style's `glyphs` entry is left untouched
/// (inert) because vector_map_tiles 8.0.0 / vector_tile_renderer 5.2.1 renders
/// labels with Flutter's own text engine (the `text-font` name becomes a
/// `fontFamily`) and never fetches glyph PBFs — confirmed in Etapa 4, and the
/// once-bundled `assets/glyphs/**` were removed as dead weight in Etapa 5
/// Task 20 (Ruling 14).
Future<CampusTiles> loadCampusTiles() async {
  final styleText = await rootBundle.loadString('assets/campus-style.json');
  final styleJson = json.decode(styleText) as Map<String, dynamic>;
  final archiveBytes = await rootBundle.load('assets/campus.pmtiles');
  final archive = await PmTilesArchive.fromBytes(
    archiveBytes.buffer.asUint8List(
      archiveBytes.offsetInBytes,
      archiveBytes.lengthInBytes,
    ),
  );
  return CampusTiles(
    theme: ThemeReader().read(styleJson),
    provider: PmTilesVectorTileProvider.fromArchive(archive),
  );
}
