import 'package:flutter/material.dart';

import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/batch_card_model.dart' show CardSlot;
import 'package:route_monitor/routing/building_card_model.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/stamp_slot.dart';

/// The selected building's stamp card: "Complete N tarefas" (or "Prédio
/// concluído"), then one row per floor, its label over its task slots.
///
///     FloorCard(building: b, onSlotTap: (slot, floor) => open(slot))
class FloorCard extends StatelessWidget {
  const FloorCard({
    required this.building,
    required this.onSlotTap,
    this.animateStopId,
    this.animateImpededStopId,
    super.key,
  });

  final DayBuilding building;

  /// A task slot tapped, with the floor it is on.
  final void Function(CardSlot, FloorRow) onSlotTap;

  /// The one stop whose stamp just fell: only its slot animates.
  final String? animateStopId;

  /// The one stop just reported impossible: only its slot animates.
  final String? animateImpededStopId;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.rule),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(p),
          for (final floor in building.floors) _floorRow(floor, p),
        ],
      ),
    );
  }

  /// The card-title slot: Bowlby One SC, the one display face (DESIGN.md).
  Widget _title(FieldPalette p) {
    return Text(
      building.complete
          ? AppStrings.floorCardDone
          : AppStrings.floorCardTitle(building.totalTasks),
      style: TextStyle(
        fontFamily: kDisplayFont,
        fontSize: 17,
        letterSpacing: 0.51,
        height: 22 / 17,
        color: p.ink,
      ),
    );
  }

  Widget _floorRow(FloorRow floor, FieldPalette p) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            floor.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: p.ink,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final slot in floor.slots) _slot(slot, floor)],
          ),
        ],
      ),
    );
  }

  Widget _slot(CardSlot slot, FloorRow floor) {
    final animate =
        slot.stopId == animateStopId || slot.stopId == animateImpededStopId;
    return StampSlot(
      key: ValueKey('floor-slot-${slot.stopId}'),
      slot: slot,
      animateStamp: animate,
      onTap: () => onSlotTap(slot, floor),
    );
  }
}
