import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/execution/evidence_photo_count.dart';
import 'package:route_monitor/execution/evidence_requirement.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/stop_actions.dart';
import 'package:route_monitor/routing/stop_evidence_section.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/stamp_slot.dart';

/// Formats the travel-from-previous leg as `N m · N min` (RF12). Returns `null`
/// when the distance is unknown; drops the time part when the duration is.
String? formatLeg(double? distanceM, double? durationS) {
  if (distanceM == null) return null;
  final distance = '${distanceM.round()} m';
  if (durationS == null) return distance;
  return '$distance · ${(durationS / 60).round()} min';
}

/// One stop of the sheet's lists: floor, service point, state (in words —
/// never by colour alone) and the actions the state allows.
///
/// The stop is drawn with its *effective* state (spec Ruling 5), the one
/// [slot] carries: a local `done` beats a local `inProgress` beats the
/// server `stop.status`, so a not-yet-synced check-in/out shows at once.
///
///     StopRow(route: route, stop: stop, slot: slot)
class StopRow extends ConsumerWidget {
  const StopRow({
    required this.route,
    required this.stop,
    required this.slot,
    super.key,
  });

  final RouteSummary route;
  final RouteStopSummary stop;
  final CardSlot slot;

  bool get _inProgress => slot.state == SlotState.inProgress;
  bool get _open =>
      _inProgress ||
      slot.state == SlotState.next ||
      slot.state == SlotState.pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    final syncChip =
        ref.watch(stopSyncChipProvider((route.id, stop.id))).asData?.value ??
        StopSyncChip.none;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _summary(p, syncChip),
          _actions(context, ref),
          if (_inProgress)
            StopEvidenceSection(
              routeId: route.id,
              routeStopId: stop.id,
              requiresEvidence: stop.requiresEvidence,
            ),
        ],
      ),
    );
  }

  Widget _summary(FieldPalette p, StopSyncChip syncChip) {
    final leg = formatLeg(stop.distanceFromPrevM, stop.durationFromPrevS);
    final muted = TextStyle(fontSize: 13, color: p.muted);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stop.floorLabel,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: p.ink,
                ),
              ),
              Text(stop.servicePointName, style: muted),
              Text(_stateLabel(), style: _stateStyle(p)),
              if (leg != null) Text(AppStrings.routeLeg(leg), style: muted),
            ],
          ),
        ),
        if (syncChip != StopSyncChip.none) _SyncChipLabel(syncChip),
      ],
    );
  }

  String _stateLabel() => switch (slot.state) {
    SlotState.done => _doneLabel(slot.stampedAt),
    SlotState.next => AppStrings.slotNext,
    SlotState.inProgress => AppStrings.slotInProgress,
    SlotState.pending => AppStrings.slotPending,
    SlotState.released => AppStrings.routeStopReleased(
      stop.releaseReason == null
          ? null
          : AppStrings.releaseReasonLabel(stop.releaseReason!),
    ),
  };

  TextStyle _stateStyle(FieldPalette p) => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: slot.state == SlotState.done ? p.moss : p.muted,
  );

  Widget _actions(BuildContext context, WidgetRef ref) {
    // PENDING too, not just IN_PROGRESS: a worker who can't even reach a
    // stop (access blocked → can't scan the QR → can't check in) must still
    // be able to signal it. Gated on an IN_PROGRESS route — the backend
    // rejects an impediment on a route that has not started (RF16). A DONE
    // stop is finished work and offers no such action.
    final canSignal = route.status == 'IN_PROGRESS' && _open;
    if (!canSignal && !_inProgress) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      children: [
        if (_inProgress)
          TextButton(
            onPressed: _canConclude(ref)
                ? () => checkOutStop(context, ref, route, stop)
                : null,
            child: const Text(AppStrings.routeConcludeButton),
          ),
        if (canSignal)
          TextButton(
            onPressed: () => signalImpossibility(context, ref, route, stop),
            child: const Text(AppStrings.routeSignalImpossibilityButton),
          ),
      ],
    );
  }

  /// An evidence stop may conclude only with its photos; the count is the
  /// device outbox first, the merged list only as a larger floor, or `null`
  /// without an execution or while the local read loads: "Concluir" stays
  /// closed then (never release before knowing).
  bool _canConclude(WidgetRef ref) {
    final progress = ref.watch(stopProgressForProvider(stop.id)).asData?.value;
    final executionId = progress?.executionId;
    final photoCount = executionId == null
        ? null
        : ref.watch(stopPhotoCountProvider((route.id, executionId)));
    return canConcludeWithEvidence(
      requiresEvidence: stop.requiresEvidence,
      photoCount: photoCount,
    );
  }
}

String _doneLabel(DateTime? at) =>
    at == null ? AppStrings.slotDoneNoHour : AppStrings.slotDone(stampHour(at));

/// A compact inline chip flagging a stop's outbox state — "Pendente" for a
/// not-yet-synced row, "Bloqueado" (brick) for a hard-blocked one.
class _SyncChipLabel extends StatelessWidget {
  const _SyncChipLabel(this.chip);

  final StopSyncChip chip;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    final (label, color) = switch (chip) {
      StopSyncChip.pending => (AppStrings.routeChipPending, p.muted),
      StopSyncChip.blocked => (AppStrings.routeChipBlocked, p.brick),
      StopSyncChip.none => ('', p.muted),
    };
    return Chip(
      label: Text(label, style: TextStyle(color: color)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
