import 'package:route_monitor/local/local_write_store.dart';

/// The outbox rows that `blocked` rows hold back: only the ones that depend
/// on a blocked row — the same stop (a check-out behind its check-in, an
/// impediment on that stop) and evidence of the same execution. A blocked
/// row never holds back another stop of the route: under automatic
/// allocation a late `409 STOP_RELEASED` check-out is routine (it is parked
/// for the appeal flow), and the rest of the worker's day must keep flowing.
///
///     final scope = BlockedScope(await store.blockedForRoute(routeId));
///     if (scope.holds(row)) continue;
class BlockedScope {
  BlockedScope(Iterable<PendingOperationRow> blocked) {
    blocked.forEach(add);
  }

  final Set<String> _stops = {};
  final Set<String> _executions = {};

  /// Widens the scope with a row that has just been blocked.
  void add(PendingOperationRow row) {
    final stop = _stopOf(row);
    if (stop != null) _stops.add(stop);
    final execution = _executionOf(row);
    if (execution != null) _executions.add(execution);
  }

  bool holds(PendingOperationRow row) {
    final stop = _stopOf(row);
    final execution = _executionOf(row);
    return (stop != null && _stops.contains(stop)) ||
        (execution != null && _executions.contains(execution));
  }

  /// The rows of [rows] nothing holds back — what a drain can still deliver.
  List<PendingOperationRow> deliverable(Iterable<PendingOperationRow> rows) =>
      rows.where((row) => !holds(row)).toList();

  /// A ROUTE_REMAINDER impediment has a null `route_stop_id`: it depends on
  /// no single stop and holds none back.
  static String? _stopOf(PendingOperationRow row) => switch (row.kind) {
    PendingOpKind.checkIn ||
    PendingOpKind.checkOut ||
    PendingOpKind.impediment => row.payload['route_stop_id'] as String?,
    PendingOpKind.evidencePhoto || PendingOpKind.evidenceNote => null,
  };

  /// The check-in's `execution_id` is the one its evidence carries; a
  /// check-out's `execution_id` is a throwaway id the backend ignores (see
  /// `ExecutionRepository.checkOut`), so it links to nothing.
  static String? _executionOf(PendingOperationRow row) => switch (row.kind) {
    PendingOpKind.checkIn ||
    PendingOpKind.evidencePhoto ||
    PendingOpKind.evidenceNote => row.payload['execution_id'] as String?,
    PendingOpKind.checkOut || PendingOpKind.impediment => null,
  };
}
