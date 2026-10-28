import 'package:flutter/material.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/stamp_slot.dart';

const int _slotsPerRow = 4;

/// The batch's stamp card: title, score, then one grid per building.
class BatchCardView extends StatelessWidget {
  const BatchCardView({
    required this.card,
    this.highlightBuildingId,
    super.key,
  });

  final BatchCard card;
  final String? highlightBuildingId;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>()!;
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
          Text(
            AppStrings.batchCardTitle(card.batchNumber),
            style: TextStyle(
              fontFamily: kDisplayFont,
              fontSize: 17,
              letterSpacing: 0.51,
              height: 22 / 17,
              color: p.ink,
            ),
          ),
          _subtitle(p),
          for (final g in card.groups) _group(g, p),
        ],
      ),
    );
  }

  Widget _subtitle(FieldPalette p) {
    final muted = TextStyle(fontSize: 12, color: p.muted);
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 10),
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.rule)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(AppStrings.batchCardSubtitle(card.total), style: muted),
          Row(
            children: [
              Text(
                '${card.done}/${card.total}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: p.ink,
                ),
              ),
              if (card.released > 0) ...[
                const SizedBox(width: 8),
                Text(
                  AppStrings.batchReleasedCount(card.released),
                  style: muted,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _group(BuildingGroup g, FieldPalette p) {
    final highlighted = g.buildingId == highlightBuildingId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            g.buildingName,
            style: TextStyle(
              fontSize: 13,
              fontWeight: highlighted ? FontWeight.w800 : FontWeight.w600,
              decoration: highlighted ? TextDecoration.underline : null,
              color: p.ink,
            ),
          ),
          const SizedBox(height: 6),
          _grid(g),
        ],
      ),
    );
  }

  Widget _grid(BuildingGroup g) {
    final rows = <Widget>[];
    for (var i = 0; i < g.slots.length; i += _slotsPerRow) {
      final chunk = g.slots.skip(i).take(_slotsPerRow).toList();
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
          child: Row(
            children: [
              for (var j = 0; j < _slotsPerRow; j++)
                Expanded(
                  child: j < chunk.length
                      ? Center(child: StampSlot(slot: chunk[j]))
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}
