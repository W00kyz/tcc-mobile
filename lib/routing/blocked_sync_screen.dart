import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/sync/sync_providers.dart';

/// The manual-attention list for one route's hard-blocked outbox rows (spec
/// Ruling 6). Each row shows its kind, a reference to the stop/execution it
/// belongs to and the last error; "Tentar de novo" resets it to `pending`
/// and kicks a fresh drain.
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
          return ListView(
            children: [
              for (final row in rows)
                ListTile(
                  title: Text(_rowLabel(row)),
                  subtitle: Text(
                    row.lastError ?? AppStrings.blockedSyncUnknownError,
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      final worker = ref.read(syncWorkerProvider);
                      await worker.unblock(row.id);
                      ref.invalidate(blockedOperationsProvider(routeId));
                      await worker.syncAll();
                    },
                    child: const Text(AppStrings.blockedSyncRetryButton),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A `Check-in — <route_stop_id>` style label. Evidence rows carry an
/// `execution_id` instead of a stop id; a `startRoute` row carries neither,
/// so it falls back to the route id (the Task 9 carry-note: the blocked
/// `startRoute` row IS the truth signal for a stuck local "iniciada" marker).
String _rowLabel(PendingOperationRow row) {
  final kind = switch (row.kind) {
    PendingOpKind.checkIn => AppStrings.blockedSyncKindCheckIn,
    PendingOpKind.checkOut => AppStrings.blockedSyncKindCheckOut,
    PendingOpKind.evidencePhoto => AppStrings.blockedSyncKindPhoto,
    PendingOpKind.evidenceNote => AppStrings.blockedSyncKindNote,
    PendingOpKind.startRoute => AppStrings.blockedSyncKindStartRoute,
    PendingOpKind.impediment => AppStrings.blockedSyncKindImpediment,
  };
  final reference = switch (row.kind) {
    PendingOpKind.checkIn ||
    PendingOpKind.checkOut ||
    // A ROUTE_REMAINDER impediment has a null route_stop_id and falls back
    // to the kind label alone, same as a bare startRoute row.
    PendingOpKind.impediment => row.payload['route_stop_id'] as String?,
    PendingOpKind.evidencePhoto ||
    PendingOpKind.evidenceNote => row.payload['execution_id'] as String?,
    PendingOpKind.startRoute => row.routeId,
  };
  return reference == null
      ? kind
      : AppStrings.blockedSyncRowLabel(kind, reference);
}
