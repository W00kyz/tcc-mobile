import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/routing/campus_map.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/building_pin.dart';

// What [CampusMap] draws over the base map: legs, building pins, the
// worker's dot and the "trajeto aproximado" caption.

/// Wide enough for a 16-character label centred over the circle; tall enough
/// for that label, a 4dp gap and the 48dp padded circle.
const double _pinMarkerWidth = 200;
const double _pinMarkerHeight = 80;

/// The circle's centre inside the marker box: the point it stands on (the
/// bottom-centre circle, 4dp padding plus half its 40dp).
const double _pinCircleCenterY = _pinMarkerHeight - 24;

/// A leg's stroke (redesign §6.3): walked in `rule`, the next one thicker
/// in moss, the rest in ink. A straight approximation stays dashed.
Polyline legPolyline(RouteMapLeg leg, FieldPalette p) {
  final (color, width) = switch (leg.kind) {
    LegKind.walked => (p.rule, 4.0),
    LegKind.next => (p.moss, 6.0),
    LegKind.rest => (p.ink, 3.0),
  };
  return Polyline(
    points: leg.points,
    strokeWidth: width,
    color: color,
    pattern: leg.approximate
        ? StrokePattern.dashed(segments: const [7, 5])
        : const StrokePattern.solid(),
  );
}

/// A building's pin, standing on the mean of its stops; the label sits above
/// the circle, so the circle itself marks the spot on the route.
Marker buildingMarker(
  BuildingGroup group, {
  required bool selected,
  required bool dimmed,
  required VoidCallback? onTap,
  bool showLabel = true,
}) {
  return Marker(
    key: ValueKey('marker-${group.buildingId}'),
    point: group.position,
    width: _pinMarkerWidth,
    height: _pinMarkerHeight,
    alignment: Marker.computePixelAlignment(
      width: _pinMarkerWidth,
      height: _pinMarkerHeight,
      left: _pinMarkerWidth / 2,
      top: _pinCircleCenterY,
    ),
    child: Align(
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        key: ValueKey('pin-${group.buildingId}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          // Pads the 40dp circle up to a 48dp touch target.
          padding: const EdgeInsets.all(4),
          child: BuildingPin(
            group: group,
            selected: selected,
            dimmed: dimmed,
            showLabel: showLabel,
            inProgress: group.slots.any((s) => s.state == SlotState.inProgress),
          ),
        ),
      ),
    ),
  );
}

/// Diameter of a circle on the route line, in logical pixels.
const double _lineCircleDiameter = 12;

/// Uber-style circles on the route line (redesign, 2026-10-28): one where
/// each drawn leg ends — its real line endpoint, which OSRM may snap a few
/// metres off the stop — and one where the live approach starts. A done
/// destination fills moss; the next one gets a thicker ring. The worker's
/// own dot stays the [workerMarker] drawn above these.
///
///     CircleLayer(circles: routeLineCircles(data, palette));
List<CircleMarker> routeLineCircles(RouteMapData data, FieldPalette p) {
  final approach = data.approach;
  return [
    if (approach != null && approach.points.isNotEmpty)
      _lineCircle(approach.points.first, p.white, p.ink, 2),
    // The next destination last, so it sits on top of any it overlaps.
    for (final leg in data.drawnLegs.where((l) => l.kind != LegKind.next))
      ?_destinationCircle(leg, p),
    for (final leg in data.drawnLegs.where((l) => l.kind == LegKind.next))
      ?_destinationCircle(leg, p),
  ];
}

CircleMarker? _destinationCircle(RouteMapLeg leg, FieldPalette p) {
  if (leg.points.isEmpty) return null;
  final end = leg.points.last;
  if (leg.destinationDone) return _lineCircle(end, p.moss, p.moss, 2);
  return _lineCircle(end, p.white, p.ink, leg.kind == LegKind.next ? 3 : 2);
}

CircleMarker _lineCircle(LatLng point, Color fill, Color ring, double width) {
  return CircleMarker(
    point: point,
    radius: _lineCircleDiameter / 2,
    color: fill,
    borderColor: ring,
    borderStrokeWidth: width,
  );
}

/// The worker's position: an ink dot with a white ring and a soft halo.
Marker workerMarker(LatLng position, FieldPalette p) {
  return Marker(
    key: const ValueKey('worker-position'),
    point: position,
    width: 34,
    height: 34,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.positionHalo,
      ),
      child: Center(
        child: Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.ink,
            border: Border.all(color: p.white, width: 3),
          ),
        ),
      ),
    ),
  );
}

/// Caption shown whenever the route has at least one approximate leg (spec
/// §6.2), bottom-left above the sheet: a dashed swatch plus the pt-BR label
/// so a straight hop is never mistaken for a surveyed path.
class ApproximateLegend extends StatelessWidget {
  const ApproximateLegend({required this.padding, super.key});

  /// The covered part of the map; the caption sits just inside it.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    return Positioned(
      left: 8,
      bottom: padding.bottom + 8,
      // A caption, not a control: a pin under it still takes the tap.
      child: IgnorePointer(child: _caption(p)),
    );
  }

  Widget _caption(FieldPalette p) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.white,
        border: Border.all(color: p.rule),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 26,
              height: 3,
              child: CustomPaint(painter: _DashSwatchPainter(p.ink)),
            ),
            const SizedBox(width: 8),
            Text(
              AppStrings.mapApproximateLegLabel,
              style: TextStyle(fontSize: 12, color: p.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints the short dashed line used in [ApproximateLegend], matched to the
/// approximate-leg polyline style.
class _DashSwatchPainter extends CustomPainter {
  const _DashSwatchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
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
  bool shouldRepaint(_DashSwatchPainter oldDelegate) =>
      oldDelegate.color != color;
}
