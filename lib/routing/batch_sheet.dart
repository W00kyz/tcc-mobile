import 'dart:async';

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
import 'package:route_monitor/ui/batch_card_carousel.dart';

// The home sheet's content while a batch is being worked (redesign §6.2):
// the next stop, then the day's batch cards in a carousel (product owner,
// 2026-10-28: no stop list). A slot tapped opens that stop's actions in a
// modal sheet; a pin selected brings the current card back with its
// building highlighted.

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

/// The route's stops with an outbox row not yet delivered — every batch's,
/// since the carousel shows them all (a batch just finished may still be
/// uploading).
Set<String> watchPendingSyncStops(WidgetRef ref, RouteSummary route) => {
  for (final stop in route.stops)
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

/// The half/open sheet's body: the day's batch cards, one per page, opening
/// on the current batch. A tapped slot opens its stop's actions.
class BatchOverview extends ConsumerWidget {
  const BatchOverview({
    required this.route,
    required this.cards,
    this.highlightBuildingId,
    super.key,
  });

  final RouteSummary route;
  final List<BatchCard> cards;

  /// The building whose pin was tapped: the carousel goes back to the
  /// current batch and underlines it there.
  final String? highlightBuildingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: BatchCardCarousel(
        cards: cards,
        currentBatch: route.currentBatch,
        highlightBuildingId: highlightBuildingId,
        // The stamp falls only on the stop just checked out (redesign §6.6).
        stampingStopId: ref.watch(lastStampedStopProvider),
        onSlotTap: (slot) => unawaited(showStopSheet(context, route, slot)),
      ),
    );
  }
}

/// One stop's actions, in a modal sheet over the map: its building and
/// floor, then its [StopRow] — every action and state rule the stop list
/// had, released and done stops included (they read their state, with no
/// action). The sheet closes once an action has written; one abandoned
/// (the camera or a dialog cancelled) leaves it open.
///
///     onSlotTap: (slot) => showStopSheet(context, route, slot)
Future<void> showStopSheet(
  BuildContext context,
  RouteSummary route,
  CardSlot slot,
) {
  final stop = _stopOf(route, slot.stopId);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      key: const ValueKey('stop-sheet'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StopSheetHeader(stop: stop),
            StopRow(
              key: ValueKey('stop-row-${slot.stopId}'),
              route: route,
              stop: stop,
              slot: slot,
              onActionDone: () => _closeStopSheet(sheetContext),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Removes the stop sheet itself, not whatever is on top: the full card
/// may already have opened over it once the batch's last stamp fell.
void _closeStopSheet(BuildContext sheetContext) {
  if (!sheetContext.mounted) return;
  final route = ModalRoute.of(sheetContext);
  if (route == null || !route.isActive) return;
  final navigator = Navigator.of(sheetContext);
  if (route.isCurrent) return navigator.pop();
  navigator.removeRoute(route);
}

/// The stop sheet's title: building and floor, as "Próxima parada" reads.
class _StopSheetHeader extends StatelessWidget {
  const _StopSheetHeader({required this.stop});

  final RouteStopSummary stop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        AppStrings.buildingFloor(stop.buildingName, stop.floorLabel),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
