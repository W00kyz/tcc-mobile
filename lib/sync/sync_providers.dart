import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show FutureProviderFamily, StreamProviderFamily;

import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/released_stop_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
import 'package:route_monitor/monitoring/monitoring_providers.dart'
    show silenceWatchdogProvider;
import 'package:route_monitor/sync/connectivity.dart';
import 'package:route_monitor/sync/stop_release.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/sync/sync_worker.dart';

/// Flat key/value bookkeeping for the [SyncWorker] (clock offset — spec
/// Ruling 7), on the one shared app database.
final syncMetaStoreProvider = Provider<SyncMetaStore>(
  (ref) => DriftSyncMetaStore(ref.watch(appDatabaseProvider)),
);

/// The stops the server released while this device still had writes for
/// them, and the data parked on them (spec 2026-10-20-alocacao-automatica
/// §7.5), on the one shared app database.
final releasedStopStoreProvider = Provider<ReleasedStopStore>(
  (ref) => DriftReleasedStopStore(ref.watch(appDatabaseProvider)),
);

/// The latest stop the sync worker found released — each new one replaces
/// the last, so a listener hears every first-time release (the route
/// screen's "Recorrer" snackbar). Null until the first.
final stopReleaseAnnouncementsProvider =
    NotifierProvider<StopReleaseAnnouncements, StopRelease?>(
      StopReleaseAnnouncements.new,
    );

class StopReleaseAnnouncements extends Notifier<StopRelease?> {
  @override
  StopRelease? build() => null;

  // An event being announced, not a property being set: a setter would read
  // as if the latest release were state callers manage.
  // ignore: use_setters_to_change_properties
  void announce(StopRelease release) => state = release;
}

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
    ref.watch(releasedStopStoreProvider),
    // Read at each delivery, not watched: the watchdog's rebuilds must not
    // rebuild the outbox worker. A pass that outlives this worker (another
    // user signed in mid-drain) finds the ref unmounted and reports nothing.
    onScanDelivered: (scannedAt) {
      if (!ref.mounted) return;
      ref.read(silenceWatchdogProvider)?.onActivity(scannedAt);
    },
    // Same rule as onScanDelivered.
    onStopReleased: (release) {
      if (!ref.mounted) return;
      ref.read(stopReleaseAnnouncementsProvider.notifier).announce(release);
    },
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

/// The stops of a route the worker reported impossible: the `route_stop_id`
/// of every `STOP` impediment row, whatever its sync state. The day's cards
/// draw these as impeded at once, offline too.
final StreamProviderFamily<Set<String>, String> impededStopIdsProvider =
    StreamProvider.family<Set<String>, String>(
      (ref, routeId) =>
          ref.watch(localWriteStoreProvider).watchImpededStopIds(routeId),
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
