import 'package:dio/dio.dart';

/// The seam over `POST /worker-positions` (spec §2 Ruling 5) — the thin
/// interface that keeps `PositionReporter`'s tests off the real HTTP client
/// (docs/CLAUDE.base.md — Dependencies: "wrap third-party libs behind a thin
/// interface").
///
///     await api.reportPosition(
///       routeId: 'r1',
///       latitude: -7.21,
///       longitude: -35.90,
///       reportedAt: DateTime.now().toUtc(),
///     );
// ignore: one_member_abstracts
abstract class MonitoringApi {
  /// Appends one GPS fix for the worker's in-progress route. Fire-and-forget:
  /// the caller (`PositionReporter`) swallows transient failures and stops on
  /// a 409 (the route is no longer `IN_PROGRESS`). Lets every error throw —
  /// there is no useful response body.
  Future<void> reportPosition({
    required String routeId,
    required double latitude,
    required double longitude,
    required DateTime reportedAt,
    double? accuracyM,
  });
}

class DioMonitoringApi implements MonitoringApi {
  DioMonitoringApi(this._dio);

  final Dio _dio;

  @override
  Future<void> reportPosition({
    required String routeId,
    required double latitude,
    required double longitude,
    required DateTime reportedAt,
    double? accuracyM,
  }) async {
    await _dio.post<void>(
      '/worker-positions',
      data: {
        'route_id': routeId,
        'latitude': latitude,
        'longitude': longitude,
        'reported_at': reportedAt.toUtc().toIso8601String(),
        'accuracy_m': ?accuracyM,
      },
    );
  }
}
