import 'package:dio/dio.dart';
import 'package:route_monitor/api/api_client.dart' show apiErrorCode;

/// What a `409 STOP_RELEASED` says (spec 2026-10-20-alocacao-automatica
/// §7.5): a check-in, check-out or evidence upload reached the server after
/// its stop went back to the pool. The server wrote nothing; [appealable]
/// says whether the worker may contest the release.
///
///     final release = StopRelease.fromError(error);
///     if (release != null && release.appealable) { /* offer the appeal */ }
class StopRelease {
  const StopRelease({
    required this.routeStopId,
    required this.releaseReason,
    required this.appealable,
  });

  /// The release [error] reports, or null for any other failure. The stop
  /// comes from the body, not from the row: an evidence row has none.
  static StopRelease? fromError(Object error) {
    if (error is! DioException || error.response?.statusCode != 409) {
      return null;
    }
    if (apiErrorCode(error) != 'STOP_RELEASED') return null;
    // `apiErrorCode` already checked the `{"detail": {...}}` shape.
    final detail = (error.response!.data as Map)['detail'] as Map;
    return StopRelease(
      routeStopId: detail['route_stop_id'] as String,
      releaseReason: detail['release_reason'] as String,
      appealable: detail['appealable'] as bool,
    );
  }

  final String routeStopId;

  /// `IMPEDIMENT` | `ROUTE_REMAINDER` | `LEFT_CAMPUS` | `LOCATION_SILENCE` |
  /// `END_OF_DAY`.
  final String releaseReason;
  final bool appealable;

  @override
  String toString() =>
      'StopRelease: route stop "$routeStopId" was released ($releaseReason); '
      'appealable=$appealable.';
}
