import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show FutureProviderFamily, StreamProviderFamily;

import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
import 'package:route_monitor/sync/connectivity.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/sync/sync_worker.dart';

/// Flat key/value bookkeeping for the [SyncWorker] (clock offset — spec
/// Ruling 7), on the one shared app database.
final syncMetaStoreProvider = Provider<SyncMetaStore>(
  (ref) => DriftSyncMetaStore(ref.watch(appDatabaseProvider)),
);

/// The `connectivity_plus` seam the worker uses to skip a drain while the
/// device is offline.
final connectivityProvider = Provider<Connectivity>(
  (ref) => ConnectivityPlusConnectivity(),
);

/// The single owner of write network I/O (spec Ruling 2). `ExecutionRepository`
/// kicks `syncRoute` after every enqueue; foreground/connectivity triggers
/// call it too.
final syncWorkerProvider = Provider<SyncWorker>((ref) {
  final worker = SyncWorker(
    ref.watch(localWriteStoreProvider),
    ref.watch(stopProgressStoreProvider),
    ref.watch(syncMetaStoreProvider),
    ref.watch(connectivityProvider),
    ref.watch(executionApiProvider),
    ref.watch(evidenceApiProvider),
  );
  ref.onDispose(worker.dispose);
  return worker;
});

/// One route's outbox drain status, re-emitted after every sync pass (spec
/// Ruling 5 — the top-of-screen sync banner). `.loading`/`.error` on the
/// stream means "no status yet"; the banner renders nothing then.
final StreamProviderFamily<RouteSyncStatus, String> routeSyncStatusProvider =
    StreamProvider.family<RouteSyncStatus, String>(
      (ref, routeId) => ref.watch(syncWorkerProvider).statusFor(routeId),
    );

/// The `blocked` outbox rows for a route — the manual-attention list behind
/// `BlockedSyncScreen`. Invalidate it after a `SyncWorker.unblock`.
final FutureProviderFamily<List<PendingOperationRow>, String>
blockedOperationsProvider =
    FutureProvider.family<List<PendingOperationRow>, String>(
      (ref, routeId) =>
          ref.watch(localWriteStoreProvider).blockedForRoute(routeId),
    );

/// Per-stop sync state for the route screen's inline chip (spec Ruling 5).
enum StopSyncChip { none, pending, blocked }

/// Resolves the [StopSyncChip] for one stop by scanning the route's outbox
/// rows: a check-in/out/impediment row belongs to the stop when its payload
/// `route_stop_id` matches; an evidence row belongs when its `execution_id`
/// matches the stop's open execution (from `stopProgressForProvider`).
/// Keyed by `(routeId, routeStopId)` — the row lookup needs the route id.
final FutureProviderFamily<StopSyncChip, (String routeId, String routeStopId)>
stopSyncChipProvider =
    FutureProvider.family<StopSyncChip, (String routeId, String routeStopId)>((
      ref,
      key,
    ) async {
      final (routeId, routeStopId) = key;
      final store = ref.watch(localWriteStoreProvider);
      final blocked = await store.blockedForRoute(routeId);
      final unsynced = await store.unsyncedForRoute(routeId);
      final progress = await ref.watch(
        stopProgressForProvider(routeStopId).future,
      );
      final executionId = progress?.executionId;

      bool matchesStop(PendingOperationRow row) {
        switch (row.kind) {
          case PendingOpKind.checkIn:
          case PendingOpKind.checkOut:
          case PendingOpKind.impediment:
            return row.payload['route_stop_id'] == routeStopId;
          case PendingOpKind.evidencePhoto:
          case PendingOpKind.evidenceNote:
            return executionId != null &&
                row.payload['execution_id'] == executionId;
        }
      }

      if (blocked.any(matchesStop)) return StopSyncChip.blocked;
      if (unsynced.any(matchesStop)) return StopSyncChip.pending;
      return StopSyncChip.none;
    });
