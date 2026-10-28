import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/sync/blocked_scope.dart';

/// How far one `SyncWorker.syncAll` has got: [done] rows delivered out of
/// the [total] that were due when it started (redesign §6.9 — "Enviando
/// registros · 3 de 5").
///
///     worker.progress.listen((p) => print('${p.done}/${p.total}'));
class SyncProgress {
  const SyncProgress({required this.done, required this.total});

  final int done;
  final int total;
}

/// The counter behind one `syncAll`: each delivered row advances it and
/// emits a [SyncProgress]. The total grows with the count when a row enqueued
/// mid-drain is delivered too, so `done <= total` always holds.
class SyncProgressRun {
  SyncProgressRun(this._total, this._emit);

  int _total;
  int _done = 0;
  final void Function(SyncProgress progress) _emit;

  /// Announces the run — `(0, total)`, so the bar shows before the first
  /// row lands — when it has anything to deliver.
  void start() {
    if (_total > 0) _emit(SyncProgress(done: 0, total: _total));
  }

  /// Called once per row the server took.
  void advance() {
    _done++;
    if (_done > _total) _total = _done;
    _emit(SyncProgress(done: _done, total: _total));
  }
}

/// The rows a `syncAll` over [routeIds] may deliver: due at [now] (epoch
/// millis) and not held back by a blocked row ([BlockedScope]) — the
/// starting total of its [SyncProgressRun].
///
///     final total = await countDeliverable(store, ids, now: nowMs);
Future<int> countDeliverable(
  LocalWriteStore store,
  List<String> routeIds, {
  required int now,
}) async {
  var count = 0;
  for (final routeId in routeIds) {
    final scope = BlockedScope(await store.blockedForRoute(routeId));
    final due = await store.dueForRoute(routeId, now: now);
    count += due.where((row) => !scope.holds(row)).length;
  }
  return count;
}
