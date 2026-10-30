import 'dart:convert';
import 'dart:developer' as developer;

import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/sync/location_refusal.dart';

/// What the sync worker does when the server refuses a location completion
/// for good (outside the radius, or no position): the stop goes back to
/// pending, its photos — which would 404 against an execution the server
/// never made — are dropped, and the row is marked `rejected`: terminal,
/// never retried, holding nothing but its own stop back. The worker keeps
/// draining the rest of the route.
///
///     await LocationRejection(
///       store: store, stopProgress: progress, onRefused: tell,
///     ).apply(row, error);
class LocationRejection {
  LocationRejection({
    required this.store,
    required this.stopProgress,
    required this.onRefused,
  });

  final LocalWriteStore store;
  final StopProgressStore stopProgress;
  final void Function(LocationRefusal refusal)? onRefused;

  /// Applies the refusal [error] of [row] (a `locationCompletion`).
  ///
  /// IMPORTANT: the row is marked LAST. A crash before it leaves the row
  /// claimed, so the next pass asks again, gets the same refusal and finishes
  /// the job — every step here is repeatable.
  Future<void> apply(PendingOperationRow row, Object error) async {
    final routeStopId = row.payload['route_stop_id'] as String;
    await stopProgress.remove(routeStopId);
    await store.discardUnsentEvidence(row.payload['execution_id'] as String);
    await store.markRejected(row.id, error.toString());
    _report(
      LocationRefusal.of(
        error,
        routeStopId: routeStopId,
        placeName: row.payload['place_name'] as String?,
      )!,
    );
  }

  /// Best-effort: the row is rejected already, and a failing listener (e.g. a
  /// disposed Riverpod ref) must neither undo that nor stop the pass.
  void _report(LocationRefusal refusal) {
    try {
      onRefused?.call(refusal);
      // Deliberately broad: nothing a listener throws may escape the drain.
      // ignore: avoid_catches_without_on_clauses
    } catch (error, stack) {
      developer.log(
        jsonEncode({
          'event': 'location_refusal_report_failed',
          'route_stop_id': refusal.routeStopId,
          'error': '$error',
        }),
        name: 'sync_worker',
        stackTrace: stack,
      );
    }
  }
}
