import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      appBar: AppBar(title: const Text('Sincronização bloqueada')),
      body: blockedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('Não foi possível carregar as operações bloqueadas.'),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(child: Text('Nenhuma operação bloqueada.'));
          }
          return ListView(
            children: [
              for (final row in rows)
                ListTile(
                  title: Text(_rowLabel(row)),
                  subtitle: Text(row.lastError ?? 'Erro desconhecido'),
                  trailing: TextButton(
                    onPressed: () async {
                      final worker = ref.read(syncWorkerProvider);
                      await worker.unblock(row.id);
                      ref.invalidate(blockedOperationsProvider(routeId));
                      await worker.syncAll();
                    },
                    child: const Text('Tentar de novo'),
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
    PendingOpKind.checkIn => 'Check-in',
    PendingOpKind.checkOut => 'Check-out',
    PendingOpKind.evidencePhoto => 'Foto',
    PendingOpKind.evidenceNote => 'Observação',
    PendingOpKind.startRoute => 'Início de rota',
    PendingOpKind.impediment => 'Impedimento',
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
  return reference == null ? kind : '$kind — $reference';
}
