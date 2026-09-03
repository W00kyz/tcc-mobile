import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
import 'package:route_monitor/sync/connectivity.dart';
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
