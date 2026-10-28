import 'package:flutter/material.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/stamp_painters.dart';

/// The brief says 14 but also expects "Central de Aulas" (16) whole.
const int _maxLabelChars = 16;
const double _pinSize = 40;

String truncateLabel(String name) => name.length <= _maxLabelChars
    ? name
    : '${name.substring(0, _maxLabelChars - 1)}…';

/// A building on the map: a 40dp circle with `done/total` and the name beside.
class BuildingPin extends StatelessWidget {
  const BuildingPin({
    required this.group,
    this.selected = false,
    this.dimmed = false,
    this.inProgress = false,
    super.key,
  });

  final BuildingGroup group;
  final bool selected;
  final bool dimmed;
  final bool inProgress;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>()!;
    return Opacity(
      opacity: dimmed ? 0.4 : 1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _circle(p),
          const SizedBox(width: 6),
          _label(p),
        ],
      ),
    );
  }

  bool get _hasNext => group.slots.any((s) => s.state == SlotState.next);

  Widget _circle(FieldPalette p) {
    final complete = group.complete;
    final dashed = inProgress || _hasNext;
    return AnimatedScale(
      scale: selected ? 1.2 : 1,
      duration: const Duration(milliseconds: 120),
      child: SizedBox(
        width: _pinSize,
        height: _pinSize,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            _disc(p, complete, dashed),
            if (inProgress) _seal(p),
          ],
        ),
      ),
    );
  }

  Widget _disc(FieldPalette p, bool complete, bool dashed) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: complete ? p.moss : p.white,
        border: dashed ? null : Border.all(color: complete ? p.moss : p.rule),
      ),
      child: CustomPaint(
        painter: dashed ? RingPainter(kind: RingKind.next, palette: p) : null,
        child: Center(
          child: Text(
            '${group.done}/${group.total}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: complete ? p.white : p.ink,
            ),
          ),
        ),
      ),
    );
  }

  /// "Em andamento" mark: a small ink seal with a dot.
  Widget _seal(FieldPalette p) {
    return Positioned(
      top: -3,
      right: -3,
      child: Semantics(
        label: AppStrings.slotInProgress,
        child: ExcludeSemantics(
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.ink,
              border: Border.all(color: p.white, width: 2),
            ),
            child: Center(
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: p.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
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
        truncateLabel(group.buildingName),
        maxLines: 1,
        style: TextStyle(
          fontSize: 12,
          fontWeight: inProgress ? FontWeight.w700 : FontWeight.w600,
          color: p.ink,
        ),
      ),
    );
  }
}
