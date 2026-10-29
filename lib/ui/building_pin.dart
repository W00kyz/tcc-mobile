import 'package:flutter/material.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/building_card_model.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/stamp_painters.dart';

/// The brief says 14 but also expects "Central de Aulas" (16) whole.
const int _maxLabelChars = 16;
const double _headSize = 40;
const double _stemHeight = 10;

String truncateLabel(String name) => name.length <= _maxLabelChars
    ? name
    : '${name.substring(0, _maxLabelChars - 1)}…';

/// A building on the map, Shopee-style: a teardrop pin whose tip stands on
/// the building, with its name above. Pending ones carry their number in
/// route order; finished ones turn grey with a check; the next one wears the
/// dashed ink ring. The map hides the name when zoomed out ([showLabel]
/// false); the pin always stays.
///
///     BuildingPin(building: building, isNext: building == next)
class BuildingPin extends StatelessWidget {
  const BuildingPin({
    required this.building,
    this.selected = false,
    this.dimmed = false,
    this.isNext = false,
    this.showLabel = true,
    super.key,
  });

  final DayBuilding building;
  final bool selected;
  final bool dimmed;

  /// The building holding the next task: its head gets the dashed ring.
  final bool isNext;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>()!;
    return Opacity(
      opacity: dimmed ? 0.45 : 1,
      // The name sits above the pin, so the tip stays on the building and
      // neighbouring pins' names do not run into each other sideways.
      child: Semantics(
        label: AppStrings.buildingPinSemantics(
          building.number,
          building.name,
          building.closedTasks,
          building.totalTasks,
        ),
        // One announcement for the whole pin, not its number and name again.
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showLabel) ...[_label(p), const SizedBox(height: 4)],
              _teardrop(p),
            ],
          ),
        ),
      ),
    );
  }

  /// Scales from the tip, so a selected pin grows without leaving its spot.
  Widget _teardrop(FieldPalette p) {
    final complete = building.complete;
    return AnimatedScale(
      scale: selected ? 1.15 : 1,
      alignment: Alignment.bottomCenter,
      duration: const Duration(milliseconds: 120),
      child: CustomPaint(
        key: const ValueKey('pin-teardrop'),
        size: const Size(_headSize, _headSize + _stemHeight),
        painter: _TeardropPainter(
          fill: complete ? p.muted : p.white,
          outline: complete ? p.muted : p.rule,
          shadow: p.ink,
        ),
        child: SizedBox(
          width: _headSize,
          height: _headSize + _stemHeight,
          child: Column(
            children: [SizedBox(height: _headSize, child: _head(p, complete))],
          ),
        ),
      ),
    );
  }

  Widget _head(FieldPalette p, bool complete) {
    final content = complete
        ? Icon(Icons.check, size: 22, color: p.white)
        : Text(
            '${building.number}',
            style: TextStyle(
              fontFamily: kUiFont,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: p.ink,
            ),
          );
    return CustomPaint(
      painter: isNext && !complete
          ? RingPainter(kind: RingKind.next, palette: p)
          : null,
      child: Center(child: content),
    );
  }

  Widget _label(FieldPalette p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: p.white,
        border: Border.all(color: p.rule),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        truncateLabel(building.name),
        maxLines: 1,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: p.ink,
        ),
      ),
    );
  }
}

/// The pin's body: a 40dp circle with a tapered 10dp stem under it, filled
/// and outlined as one shape so no seam shows where they meet.
class _TeardropPainter extends CustomPainter {
  const _TeardropPainter({
    required this.fill,
    required this.outline,
    required this.shadow,
  });

  final Color fill;
  final Color outline;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _shape(size);
    canvas
      ..drawShadow(path, shadow, 2, false)
      ..drawPath(path, Paint()..color = fill)
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = outline,
      );
  }

  /// The circle joined to a triangle whose base sits inside it, so the
  /// union has no gap and its outline runs smoothly into the stem.
  Path _shape(Size size) {
    final centerX = size.width / 2;
    final head = Path()
      ..addOval(Rect.fromCircle(center: Offset(centerX, 20), radius: 20));
    final stem = Path()
      ..moveTo(centerX - 11.5, 36)
      ..lineTo(centerX + 11.5, 36)
      ..lineTo(centerX, size.height)
      ..close();
    return Path.combine(PathOperation.union, head, stem);
  }

  @override
  bool shouldRepaint(_TeardropPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.outline != outline ||
      oldDelegate.shadow != shadow;
}
