import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/stop_actions.dart';
import 'package:route_monitor/routing/stop_row.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/batch_card.dart';

// The home sheet's content while a batch is being worked (redesign §6.2):
// the next stop, the batch card and the stops grouped by building — or, with
// a pin selected, that building's stops alone.

/// What this device knows about each stop of [route], from its local
/// progress rows (watched, so a check-in/out redraws the card).
///
///     final local = watchLocalStates(ref, route);
Map<String, LocalStopState> watchLocalStates(
  WidgetRef ref,
  RouteSummary route,
) => {
  for (final stop in route.stops)
    if (ref.watch(stopProgressForProvider(stop.id)).asData?.value
        case final entry?)
      stop.id: LocalStopState.fromEntry(entry),
};

/// The batch's slot in progress, if any: it takes the place of "Próxima
/// parada" with the `InProgressBlock`.
CardSlot? inProgressSlotOf(BatchCard card) => card.groups
    .expand((group) => group.slots)
    .where((slot) => slot.state == SlotState.inProgress)
    .firstOrNull;

/// The current batch's stops with an outbox row not yet delivered.
Set<String> watchPendingSyncStops(WidgetRef ref, RouteSummary route) => {
  for (final stop in route.currentBatchStops)
    if ((ref.watch(stopSyncChipProvider((route.id, stop.id))).asData?.value ??
            StopSyncChip.none) !=
        StopSyncChip.none)
      stop.id,
};

RouteStopSummary _stopOf(RouteSummary route, String stopId) =>
    route.stops.firstWhere((stop) => stop.id == stopId);

/// "Próxima parada": the first PENDING stop of the batch in route order,
/// with the leg to it. A stop in progress shows the `InProgressBlock`
/// instead (redesign §6.2).
///
///     NextStopRow(route: route, card: card)
class NextStopRow extends StatelessWidget {
  const NextStopRow({required this.route, required this.card, super.key});

  final RouteSummary route;
  final BatchCard card;

  @override
  Widget build(BuildContext context) {
    final next = card.next;
    if (next == null) return const SizedBox.shrink();
    return _row(
      Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light,
      label: AppStrings.nextStopLabel,
      stop: _stopOf(route, next.stopId),
    );
  }

  Widget _row(
    FieldPalette p, {
    required String label,
    required RouteStopSummary stop,
  }) {
    final leg = formatLeg(stop.distanceFromPrevM, stop.durationFromPrevS);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: p.muted)),
                Text(
                  AppStrings.buildingFloor(stop.buildingName, stop.floorLabel),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: p.ink,
                  ),
                ),
              ],
            ),
          ),
          if (leg != null)
            Text(
              leg,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: p.ink,
              ),
            ),
        ],
      ),
    );
  }
}

/// The half/open sheet with no building selected: the card, then every
/// building of the batch with its stops and their actions.
class BatchOverview extends ConsumerWidget {
  const BatchOverview({required this.route, required this.card, super.key});

  final RouteSummary route;
  final BatchCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        // The stamp falls only on the stop just checked out (redesign §6.6).
        BatchCardView(
          card: card,
          stampingStopId: ref.watch(lastStampedStopProvider),
        ),
        for (final group in card.groups) ...[
          const SizedBox(height: 16),
          BuildingHeader(group: group),
          BuildingStops(route: route, group: group),
        ],
      ],
    );
  }
}

/// A building's name (whole, unlike the pin's label) and its `done/total`.
class BuildingHeader extends StatelessWidget {
  const BuildingHeader({required this.group, super.key});

  final BuildingGroup group;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    return Row(
      children: [
        Expanded(
          child: Text(
            group.buildingName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Text(
          '${group.done}/${group.total}',
          style: TextStyle(fontWeight: FontWeight.w700, color: p.ink),
        ),
      ],
    );
  }
}

/// One building's stops, in route order, each with its actions. The whole
/// batch, in order: a stop released since (an impediment that reached the
/// server, say) shows as such, with no action left on it — nothing on it is
/// the worker's any more (spec §7).
class BuildingStops extends StatelessWidget {
  const BuildingStops({required this.route, required this.group, super.key});

  final RouteSummary route;
  final BuildingGroup group;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, slot) in group.slots.indexed) ...[
          if (i > 0) Divider(height: 1, color: p.rule),
          StopRow(
            key: ValueKey('stop-row-${slot.stopId}'),
            route: route,
            stop: _stopOf(route, slot.stopId),
            slot: slot,
          ),
        ],
      ],
    );
  }
}
