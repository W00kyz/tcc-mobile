import 'package:dio/dio.dart';

import 'package:route_monitor/monitoring/notification_models.dart';

export 'package:route_monitor/monitoring/notification_models.dart';

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

  /// The worker's in-app notifications, newest first (`GET /notifications/me`).
  /// [limit] caps the page — the list screen shows a single recent page, not a
  /// paginated history.
  Future<List<AppNotification>> fetchNotifications({int limit});

  /// How many of the worker's notifications are still unread
  /// (`GET /notifications/me/unread-count`) — drives the route-screen badge.
  Future<int> unreadCount();

  /// Marks one notification read (`POST /notifications/{id}/read`). Idempotent
  /// on the backend; lets every error throw.
  Future<void> markRead(String id);
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

  @override
  Future<List<AppNotification>> fetchNotifications({int limit = 30}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/notifications/me',
      queryParameters: {'page_size': limit},
    );
    final items = response.data!['items'] as List<dynamic>;
    return items
        .map((item) => AppNotification.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<int> unreadCount() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/notifications/me/unread-count',
    );
    return response.data!['count'] as int;
  }

  @override
  Future<void> markRead(String id) async {
    await _dio.post<void>('/notifications/$id/read');
  }
}
