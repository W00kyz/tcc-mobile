import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/appeals/appeal_providers.dart';
import 'package:route_monitor/appeals/released_stop_entry.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart';
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
/// The same entries are on `/recursos`, reachable whatever the route's
/// state — this screen is only reachable from an IN_PROGRESS route.
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

/// The parked rows of one released stop, as a [ReleasedStopEntry].
class _ReleasedStopTile extends ConsumerWidget {
  const _ReleasedStopTile(this.routeStopId);

  final String routeStopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref
        .watch(releasedStopNoticeProvider(routeStopId))
        .asData
        ?.value;
    return ReleasedStopEntry(
      routeStopId: routeStopId,
      title: AppStrings.releasedStopTitle(routeStopId),
      releaseReason: notice?.releaseReason,
      canAppeal: notice?.appealable ?? false,
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
