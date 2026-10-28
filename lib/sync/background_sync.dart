import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart' show Session;
import 'package:route_monitor/execution/execution_providers.dart'
    show localWriteStoreProvider;
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
import 'package:route_monitor/monitoring/monitoring_providers.dart'
    show silenceWatchdogProvider;
import 'package:route_monitor/sync/sync_notifications.dart';
import 'package:route_monitor/sync/sync_progress.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_worker.dart';
import 'package:workmanager/workmanager.dart';

/// Asks the OS to drain the outbox when there is network, even with the app
/// closed (redesign §6.9). A project seam over `workmanager`.
///
///     await scheduler.scheduleDrain();
// A class, not a function: the seam the global constraints name, and what a
// test fake implements.
// ignore: one_member_abstracts
abstract class BackgroundSyncScheduler {
  Future<void> scheduleDrain();
}

/// [BackgroundSyncScheduler] over `workmanager`: one unique one-off task,
/// network-constrained, kept (not replaced) when one is already queued.
class WorkmanagerSyncScheduler implements BackgroundSyncScheduler {
  WorkmanagerSyncScheduler({Workmanager? workmanager})
    : _workmanager = workmanager ?? Workmanager();

  final Workmanager _workmanager;
  bool _initialized = false;

  static const String uniqueName = 'drain-outbox';

  @override
  Future<void> scheduleDrain() async {
    // Lazily, here rather than in `main()`: main stays thin (DO NOT CHANGE),
    // and nothing needs the dispatcher before the first schedule.
    if (!_initialized) {
      await _workmanager.initialize(backgroundSyncDispatcher);
      _initialized = true;
    }
    await _workmanager.registerOneOffTask(
      uniqueName,
      uniqueName,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }
}

/// The OS-side drain scheduler; tests override it with a fake.
final backgroundSyncSchedulerProvider = Provider<BackgroundSyncScheduler>(
  (ref) => WorkmanagerSyncScheduler(),
);

/// What `SyncTriggers` tells on each lifecycle change.
final appForegroundTrackerProvider = Provider<AppForegroundTracker>(
  (ref) => AppForegroundTracker(
    meta: ref.watch(syncMetaStoreProvider),
    store: ref.watch(localWriteStoreProvider),
    scheduler: ref.watch(backgroundSyncSchedulerProvider),
  ),
);

/// Whether [store] holds rows still owed to the network (`pending` or
/// `failed`). Blocked-only routes do not count: no drain can send them.
///
///     if (await hasPendingWork(store)) await scheduler.scheduleDrain();
Future<bool> hasPendingWork(LocalWriteStore store) async {
  for (final routeId in await store.routeIdsWithWork()) {
    if ((await store.unsyncedForRoute(routeId)).isNotEmpty) return true;
  }
  return false;
}

/// How many rows sit `blocked` across every route of [store].
Future<int> blockedRowCount(LocalWriteStore store) async {
  var count = 0;
  for (final routeId in await store.routeIdsWithWork()) {
    count += (await store.blockedForRoute(routeId)).length;
  }
  return count;
}

/// The first route of [store] with a `blocked` row — where the "needs
/// attention" tap leads.
Future<String?> firstBlockedRoute(LocalWriteStore store) async {
  for (final routeId in await store.routeIdsWithWork()) {
    if ((await store.blockedForRoute(routeId)).isNotEmpty) return routeId;
  }
  return null;
}

/// Records the app entering and leaving the foreground for the background
/// drain, and on leaving with rows still owed asks for a drain — the OS runs
/// it once there is network (redesign §6.9).
///
///     tracker.entered(); // resumed
///     tracker.left();    // paused
class AppForegroundTracker {
  AppForegroundTracker({
    required this._meta,
    required this._store,
    required this._scheduler,
  });

  final SyncMetaStore _meta;
  final LocalWriteStore _store;
  final BackgroundSyncScheduler _scheduler;

  Future<void> entered() =>
      _bestEffort(() => _meta.setAppInForeground(inForeground: true));

  Future<void> left() => _bestEffort(() async {
    await _meta.setAppInForeground(inForeground: false);
    if (await hasPendingWork(_store)) await _scheduler.scheduleDrain();
  });

  /// Lifecycle callbacks fire these unawaited: a failure (no workmanager
  /// channel, a busy database) is logged, never thrown into the zone.
  Future<void> _bestEffort(Future<void> Function() step) async {
    try {
      await step();
      // Deliberately broad, for the reason above.
      // ignore: avoid_catches_without_on_clauses
    } catch (error, stack) {
      _logFailure('foreground_tracking_failed', error, stack);
    }
  }
}

/// One background drain: runs [worker]'s `syncAll` and reports it through
/// [notifications] — progress per delivered row, then "needs attention" when
/// rows ended blocked ([blockedCount]), "finished" when every due row went,
/// or a clear otherwise. While [appInForeground] says so, it still drains
/// but posts nothing (the snackbars cover it — Review Focus 4).
///
///     await runBackgroundDrain(worker: w, notifications: n,
///         appInForeground: meta.getAppInForeground,
///         blockedCount: () => blockedRowCount(store));
Future<void> runBackgroundDrain({
  required SyncWorker worker,
  required SyncNotificationPublisher notifications,
  required Future<bool> Function() appInForeground,
  required Future<int> Function() blockedCount,
}) async {
  final publisher = await appInForeground()
      ? const SilentSyncNotifications()
      : notifications;
  final last = await _drainReporting(worker, publisher);
  final blocked = await blockedCount();
  if (blocked > 0) return publisher.needsAttention(blocked);
  if (last != null && last.done == last.total) {
    return publisher.finished(last.done);
  }
  await publisher.clear();
}

/// Runs `syncAll`, posting each progress step in order; returns the last.
Future<SyncProgress?> _drainReporting(
  SyncWorker worker,
  SyncNotificationPublisher publisher,
) async {
  SyncProgress? last;
  var posted = Future<void>.value();
  final subscription = worker.progress.listen((step) {
    last = step;
    posted = posted.then((_) => publisher.progress(step.done, step.total));
  });
  try {
    await worker.syncAll();
  } finally {
    await subscription.cancel();
  }
  await posted;
  return last;
}

/// The `workmanager` entry point. Runs on a headless engine — or on the
/// app's own engine when it is alive (workmanager 0.10 in-process one-off
/// tasks) — so it builds its own [ProviderContainer] with the app's
/// providers; the `--dart-define` env is compiled into this same snapshot.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((_, _) => drainOutboxInBackground());
}

/// The task body. True tells WorkManager it is done; false asks for a retry
/// with backoff (rows still owed, or the pass crashed).
Future<bool> drainOutboxInBackground() async {
  DartPluginRegistrant.ensureInitialized();
  final container = ProviderContainer(
    overrides: [
      // The app's watchdog would start a day fetch and reschedule warnings
      // from this isolate; the app's own watchdog owns them.
      silenceWatchdogProvider.overrideWithValue(null),
    ],
  );
  try {
    // No one signed in: nothing this device may send — done, no retry.
    final stored = await container.read(sessionStorageProvider).readSession();
    if (stored == null) return true;
    if (!await _sessionRestored(container)) return false;
    await _drainWith(container);
    return !await hasPendingWork(container.read(localWriteStoreProvider));
    // Deliberately broad: a crash must become a retry, never kill the task.
    // ignore: avoid_catches_without_on_clauses
  } catch (error, stack) {
    _logFailure('background_drain_failed', error, stack);
    return false;
  } finally {
    container.dispose();
  }
}

Future<void> _drainWith(ProviderContainer container) {
  final store = container.read(localWriteStoreProvider);
  final meta = container.read(syncMetaStoreProvider);
  return runBackgroundDrain(
    worker: container.read(syncWorkerProvider),
    notifications: LocalSyncNotifications(
      blockedRouteId: () => firstBlockedRoute(store),
    ),
    appInForeground: meta.getAppInForeground,
    blockedCount: () => blockedRowCount(store),
  );
}

/// Waits for `SessionNotifier` to restore the stored session — the API
/// clients read the token from it. False when it did not land in time.
Future<bool> _sessionRestored(ProviderContainer container) async {
  final restored = Completer<bool>();
  final subscription = container.listen<Session?>(sessionProvider, (_, next) {
    if (next != null && !restored.isCompleted) restored.complete(true);
  }, fireImmediately: true);
  try {
    return await restored.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => false,
    );
  } finally {
    subscription.close();
  }
}

void _logFailure(String event, Object error, StackTrace stack) {
  developer.log(
    jsonEncode({'event': event, 'error': '$error'}),
    name: 'background_sync',
    stackTrace: stack,
  );
}
