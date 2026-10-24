import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/appeals/appeal_form_screen.dart';
import 'package:route_monitor/appeals/appeal_providers.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/released_stop_store.dart';
import 'package:route_monitor/sync/sync_providers.dart';

/// The manual-attention list for one route's hard-blocked outbox rows (spec
/// Ruling 6). Each row shows its kind, a reference to the stop/execution it
/// belongs to and the last error; "Tentar de novo" resets it to `pending`
/// and kicks a fresh drain.
///
/// Rows parked on a released stop (a late `409 STOP_RELEASED`, spec
/// 2026-10-20-alocacao-automatica §7.5) show once per stop instead, and
/// never with "Tentar de novo" — the replay would get the same 409. The
/// worker appeals ("Recorrer", when the server said they may) or discards
/// the stop's local data ("Descartar"), so no release leaves them stuck.
class BlockedSyncScreen extends ConsumerWidget {
  const BlockedSyncScreen({required this.routeId, super.key});

  final String routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockedAsync = ref.watch(blockedOperationsProvider(routeId));

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.blockedSyncAppBarTitle)),
      body: blockedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text(AppStrings.blockedSyncLoadError),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(child: Text(AppStrings.blockedSyncEmpty));
          }
          final releasedStops = {
            for (final row in rows) ?row.releasedStopId,
          };
          return ListView(
            children: [
              for (final stop in releasedStops) _ReleasedStopTile(stop),
              for (final row in rows)
                if (row.releasedStopId == null)
                  _BlockedRowTile(routeId: routeId, row: row),
            ],
          );
        },
      ),
    );
  }
}

class _BlockedRowTile extends ConsumerWidget {
  const _BlockedRowTile({required this.routeId, required this.row});

  final String routeId;
  final PendingOperationRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    title: Text(_rowLabel(row)),
    subtitle: Text(row.lastError ?? AppStrings.blockedSyncUnknownError),
    trailing: TextButton(
      onPressed: () async {
        final worker = ref.read(syncWorkerProvider);
        await worker.unblock(row.id);
        ref.invalidate(blockedOperationsProvider(routeId));
        await worker.syncAll();
      },
      child: const Text(AppStrings.blockedSyncRetryButton),
    ),
  );
}

/// One released stop and the actions that clear its parked rows.
class _ReleasedStopTile extends ConsumerWidget {
  const _ReleasedStopTile(this.routeStopId);

  final String routeStopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref
        .watch(releasedStopNoticeProvider(routeStopId))
        .asData
        ?.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ListTile(
          title: Text(AppStrings.blockedSyncReleasedStop(routeStopId)),
          subtitle: notice == null
              ? null
              : Text(
                  AppStrings.blockedSyncReleasedReason(
                    AppStrings.releaseReasonLabel(notice.releaseReason),
                  ),
                ),
        ),
        Wrap(
          spacing: 8,
          children: [
            if (notice != null && notice.appealable)
              TextButton(
                onPressed: () => _appeal(context, notice),
                child: const Text(AppStrings.blockedSyncAppealButton),
              ),
            TextButton(
              onPressed: () => _discard(context, ref),
              child: const Text(AppStrings.blockedSyncDiscardButton),
            ),
          ],
        ),
      ],
    );
  }

  /// The appeal form clears the stop itself once the appeal is on record.
  Future<void> _appeal(BuildContext context, ReleasedStopNotice notice) =>
      Navigator.of(context).push(
        MaterialPageRoute<bool>(
          builder: (_) => AppealFormScreen(
            routeStopId: notice.routeStopId,
            releaseReason: notice.releaseReason,
          ),
        ),
      );

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.blockedSyncDiscardTitle),
        content: const Text(AppStrings.blockedSyncDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStrings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(AppStrings.blockedSyncDiscardButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await discardReleasedStop(ref, routeStopId);
    messenger.showSnackBar(
      const SnackBar(content: Text(AppStrings.blockedSyncDiscarded)),
    );
  }
}

/// A `Check-in — <route_stop_id>` style label. Evidence rows carry an
/// `execution_id` instead of a stop id.
String _rowLabel(PendingOperationRow row) {
  final kind = switch (row.kind) {
    PendingOpKind.checkIn => AppStrings.blockedSyncKindCheckIn,
    PendingOpKind.checkOut => AppStrings.blockedSyncKindCheckOut,
    PendingOpKind.evidencePhoto => AppStrings.blockedSyncKindPhoto,
    PendingOpKind.evidenceNote => AppStrings.blockedSyncKindNote,
    PendingOpKind.impediment => AppStrings.blockedSyncKindImpediment,
  };
  final reference = switch (row.kind) {
    PendingOpKind.checkIn ||
    PendingOpKind.checkOut ||
    // A ROUTE_REMAINDER impediment has a null route_stop_id and falls back
    // to the kind label alone.
    PendingOpKind.impediment => row.payload['route_stop_id'] as String?,
    PendingOpKind.evidencePhoto ||
    PendingOpKind.evidenceNote => row.payload['execution_id'] as String?,
  };
  return reference == null
      ? kind
      : AppStrings.blockedSyncRowLabel(kind, reference);
}
