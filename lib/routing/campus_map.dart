import 'dart:convert';

// Theme is hidden from material: vector_tile_renderer exports its own Theme and
// that is the one VectorTileLayer wants. Same choice VectorTileLayer makes.
import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart'
    show Theme, ThemeReader;

/// Everything [CampusMap] needs to draw one route, already projected to
/// screen-space types. Building this is a pure transform ([buildRouteMapData]),
/// kept apart from the widget so it can be unit-tested without `pumpWidget`
/// (Ruling 10 — the map stays a thin seam over flutter_map + vector_map_tiles).
class RouteMapData {
  RouteMapData({required this.stops, required this.legs});

  /// The stops in visiting order.
  final List<RouteMapStop> stops;

  /// One leg per stop after the first: `legs[i]` joins `stops[i]` to
  /// `stops[i + 1]`.
  final List<RouteMapLeg> legs;
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

/// One segment of the drawn trajectory.
class RouteMapLeg {
  RouteMapLeg({required this.points, required this.approximate});

  /// The polyline vertices, in `LatLng(lat, lng)` order.
  final List<LatLng> points;

  /// `true` when the backend gave no real geometry for this leg and the line
  /// is just a straight hop between the two stops — drawn dashed so the field
  /// worker does not read it as a surveyed path.
  final bool approximate;
}

/// Pure transform from the API summary to what the map draws.
///
/// The OSRM leg geometry arrives as `[lng, lat]` pairs; every pair is flipped
/// to `LatLng(lat, lng)`. A stop with no `legGeometry` gets a straight,
/// [RouteMapLeg.approximate] leg between it and its predecessor.
///
/// ```dart
/// final data = buildRouteMapData(route);
/// CampusMap(data: data);
/// ```
RouteMapData buildRouteMapData(RouteSummary route) {
  final stops = [
    for (final stop in route.stops)
      RouteMapStop(
        position: LatLng(stop.latitude, stop.longitude),
        order: stop.orderIndex,
        pending: stop.status == 'PENDING',
      ),
  ];

  final legs = <RouteMapLeg>[];
  for (var i = 1; i < route.stops.length; i++) {
    final previous = route.stops[i - 1];
    final current = route.stops[i];
    final geometry = current.legGeometry;
    if (geometry != null && geometry.isNotEmpty) {
      legs.add(
        RouteMapLeg(
          points: [
            for (final point in geometry) LatLng(point[1], point[0]),
          ],
          approximate: false,
        ),
      );
    } else {
      legs.add(
        RouteMapLeg(
          points: [
            LatLng(previous.latitude, previous.longitude),
            LatLng(current.latitude, current.longitude),
          ],
          approximate: true,
        ),
      );
    }
  }

  return RouteMapData(stops: stops, legs: legs);
}

/// The bundled offline base map plus one route's pins and trajectory.
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
class CampusMap extends StatelessWidget {
  const CampusMap({required this.data, this.tileProviderOverride, super.key});

  /// The route to draw.
  final RouteMapData data;

  /// Test seam: when set, the base map is a plain [TileLayer] fed by this
  /// provider instead of the PMTiles vector layer.
  final TileProvider? tileProviderOverride;

  List<LatLng> get _allPoints => [
    for (final stop in data.stops) stop.position,
    for (final leg in data.legs) ...leg.points,
  ];

  @override
  Widget build(BuildContext context) {
    final points = _allPoints;
    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          options: MapOptions(
            initialCameraFit: points.isEmpty
                ? null
                : CameraFit.coordinates(
                    coordinates: points,
                    padding: const EdgeInsets.all(48),
                    maxZoom: 18,
                  ),
            minZoom: 12,
            maxZoom: 19,
            backgroundColor: const Color(0xFFF2EFE9),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            _CampusBaseLayer(tileProviderOverride: tileProviderOverride),
            PolylineLayer(
              polylines: [for (final leg in data.legs) _polyline(leg)],
            ),
            MarkerLayer(
              markers: [
                for (final stop in data.stops)
                  Marker(
                    point: stop.position,
                    width: 34,
                    height: 34,
                    child: _StopPin(stop: stop),
                  ),
              ],
            ),
          ],
        ),
        if (data.legs.any((leg) => leg.approximate)) const _ApproximateLegend(),
      ],
    );
  }

  Polyline _polyline(RouteMapLeg leg) => Polyline(
    points: leg.points,
    strokeWidth: leg.approximate ? 3 : 5,
    color: leg.approximate ? const Color(0xFF9E9E9E) : const Color(0xFF1565C0),
    pattern: leg.approximate
        ? StrokePattern.dashed(segments: const [7, 5])
        : const StrokePattern.solid(),
  );
}

/// Base map: the injected no-op provider under test, the real PMTiles vector
/// layer otherwise. The load future is held in state so a rebuild does not
/// re-open the archive.
class _CampusBaseLayer extends StatefulWidget {
  const _CampusBaseLayer({required this.tileProviderOverride});

  final TileProvider? tileProviderOverride;

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
      return const ColoredBox(color: Color(0xFFF2EFE9));
    }
    return FutureBuilder<CampusTiles>(
      future: tilesFuture,
      builder: (context, snapshot) {
        final tiles = snapshot.data;
        if (tiles == null) {
          // A plain filled box, never a spinner: a spinner animates forever and
          // would keep `pumpAndSettle` from ever returning.
          return const ColoredBox(color: Color(0xFFF2EFE9));
        }
        return VectorTileLayer(
          theme: tiles.theme,
          tileProviders: TileProviders({'campus': tiles.provider}),
          fileCacheTtl: Duration.zero,
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

/// A numbered circular pin. Pending stops are blue, done stops green.
class _StopPin extends StatelessWidget {
  const _StopPin({required this.stop});

  final RouteMapStop stop;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: stop.pending ? const Color(0xFF1565C0) : const Color(0xFF2E7D32),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(
        child: Text(
          '${stop.order}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Bottom-left caption shown whenever the route has at least one approximate
/// leg (spec §6.2). A dashed swatch plus the pt-BR label so a straight hop is
/// never mistaken for a surveyed path.
class _ApproximateLegend extends StatelessWidget {
  const _ApproximateLegend();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: EdgeInsets.all(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            // Near-opaque white so the caption stays readable over any tile.
            color: Color(0xF2FFFFFF),
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 26,
                  height: 3,
                  child: CustomPaint(painter: _DashSwatchPainter()),
                ),
                SizedBox(width: 8),
                Text(
                  AppStrings.mapApproximateLegLabel,
                  style: TextStyle(fontSize: 12, color: Color(0xFF424242)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the short dashed line used in [_ApproximateLegend], matched to the
/// approximate-leg polyline style.
class _DashSwatchPainter extends CustomPainter {
  const _DashSwatchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF9E9E9E)
      ..strokeWidth = 3;
    const dash = 5.0;
    const gap = 4.0;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      final endX = (x + dash).clamp(0.0, size.width);
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(endX, size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashSwatchPainter oldDelegate) => false;
}
