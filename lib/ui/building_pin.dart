import 'package:flutter/material.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/ui/app_theme.dart';

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
      opacity: dimmed ? 0.5 : 1,
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

  Widget _circle(FieldPalette p) {
    final complete = group.complete;
    return Container(
      width: _pinSize,
      height: _pinSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: complete ? p.moss : p.white,
        border: Border.all(
          color: complete ? p.moss : p.ink,
          width: selected ? 3.5 : 2,
        ),
      ),
      child: Text(
        '${group.done}/${group.total}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: complete ? p.white : p.ink,
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
