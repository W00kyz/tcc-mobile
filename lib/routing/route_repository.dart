import 'package:dio/dio.dart';

class RouteStopSummary {
  const RouteStopSummary({
    required this.id,
    required this.orderIndex,
    required this.status,
    required this.servicePointName,
  });

  factory RouteStopSummary.fromJson(Map<String, dynamic> json) =>
      RouteStopSummary(
        id: json['id'] as String,
        orderIndex: json['order_index'] as int,
        status: json['status'] as String,
        servicePointName: json['service_point_name'] as String,
      );

  final String id;
  final int orderIndex;
  final String status;
  final String servicePointName;
}

class RouteSummary {
  const RouteSummary({
    required this.id,
    required this.fieldWorkerName,
    required this.startedAt,
    required this.stops,
  });

  factory RouteSummary.fromJson(Map<String, dynamic> json) => RouteSummary(
    id: json['id'] as String,
    fieldWorkerName: json['field_worker_name'] as String,
    startedAt: json['started_at'] == null
        ? null
        : DateTime.parse(json['started_at'] as String),
    stops: (json['stops'] as List<dynamic>)
        .map((raw) => RouteStopSummary.fromJson(raw as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final String fieldWorkerName;
  final DateTime? startedAt;
  final List<RouteStopSummary> stops;
}

abstract class RouteRepository {
  Future<List<RouteSummary>> fetchMyRoutes();
  Future<RouteSummary> startRoute({
    required String routeId,
    required double latitude,
    required double longitude,
  });
}

class DioRouteRepository implements RouteRepository {
  DioRouteRepository(this._dio);

  final Dio _dio;

  @override
  Future<List<RouteSummary>> fetchMyRoutes() async {
    final response = await _dio.get<List<dynamic>>('/routes/me');
    return response.data!
        .map((raw) => RouteSummary.fromJson(raw as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<RouteSummary> startRoute({
    required String routeId,
    required double latitude,
    required double longitude,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/routes/$routeId/start',
      data: {
        'latitude': latitude,
        'longitude': longitude,
        'started_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    return RouteSummary.fromJson(response.data!);
  }
}
