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

/// Wide enough for the 40dp circle plus a 16-character label on its right.
const double _pinMarkerWidth = 280;
const double _pinMarkerHeight = 56;

/// The circle's centre inside the marker box: the point it stands on.
const double _pinCircleCenterX = 24;

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

/// A building's pin, standing on the mean of its stops; the label hangs to
/// the right of the circle, like Google Maps' place labels.
Marker buildingMarker(
  BuildingGroup group, {
  required bool selected,
  required bool dimmed,
  required VoidCallback? onTap,
}) {
  return Marker(
    key: ValueKey('marker-${group.buildingId}'),
    point: group.position,
    width: _pinMarkerWidth,
    height: _pinMarkerHeight,
    alignment: Marker.computePixelAlignment(
      width: _pinMarkerWidth,
      height: _pinMarkerHeight,
      left: _pinCircleCenterX,
      top: _pinMarkerHeight / 2,
    ),
    child: Align(
      alignment: Alignment.centerLeft,
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
            inProgress: group.slots.any((s) => s.state == SlotState.inProgress),
          ),
        ),
      ),
    ),
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
        color: p.ink.withValues(alpha: 0.13),
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
