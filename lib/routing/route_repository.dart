import 'package:dio/dio.dart';

DateTime? _parseOptionalTimestamp(Object? raw) =>
    raw == null ? null : DateTime.parse(raw as String);

class RouteStopSummary {
  const RouteStopSummary({
    required this.id,
    required this.orderIndex,
    required this.status,
    required this.servicePointName,
    required this.latitude,
    required this.longitude,
    required this.pointType,
    this.expectedArrivalFrom,
    this.expectedArrivalTo,
    this.distanceFromPrevM,
    this.durationFromPrevS,
    this.legGeometry,
  });

  factory RouteStopSummary.fromJson(Map<String, dynamic> json) =>
      RouteStopSummary(
        id: json['id'] as String,
        orderIndex: json['order_index'] as int,
        status: json['status'] as String,
        servicePointName: json['service_point_name'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        pointType: json['point_type'] as String,
        expectedArrivalFrom: _parseOptionalTimestamp(
          json['expected_arrival_from'],
        ),
        expectedArrivalTo: _parseOptionalTimestamp(json['expected_arrival_to']),
        distanceFromPrevM: (json['distance_from_prev_m'] as num?)?.toDouble(),
        durationFromPrevS: (json['duration_from_prev_s'] as num?)?.toDouble(),
        // OSRM leg geometry arrives as [[lng, lat], ...]; keep that order so
        // the map layer can hand it straight to a polyline.
        legGeometry: (json['leg_geometry'] as List<dynamic>?)
            ?.map(
              (p) => (p as List<dynamic>)
                  .map((n) => (n as num).toDouble())
                  .toList(),
            )
            .toList(),
      );

  final String id;
  final int orderIndex;
  final String status;
  final String servicePointName;
  final double latitude;
  final double longitude;
  final String pointType;
  final DateTime? expectedArrivalFrom;
  final DateTime? expectedArrivalTo;
  final double? distanceFromPrevM;
  final double? durationFromPrevS;
  final List<List<double>>? legGeometry;
}

class RouteSummary {
  const RouteSummary({
    required this.id,
    required this.fieldWorkerName,
    required this.routeDate,
    required this.routeType,
    required this.status,
    required this.startedAt,
    required this.stops,
  });

  factory RouteSummary.fromJson(Map<String, dynamic> json) => RouteSummary(
    id: json['id'] as String,
    fieldWorkerName: json['field_worker_name'] as String,
    // route_date is a date-only ISO string ("YYYY-MM-DD"); DateTime.parse
    // reads it as local midnight, which is all the day view needs.
    routeDate: DateTime.parse(json['route_date'] as String),
    routeType: json['route_type'] as String,
    status: json['status'] as String,
    startedAt: _parseOptionalTimestamp(json['started_at']),
    stops: (json['stops'] as List<dynamic>)
        .map((raw) => RouteStopSummary.fromJson(raw as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final String fieldWorkerName;
  final DateTime routeDate;
  final String routeType;
  final String status;
  final DateTime? startedAt;
  final List<RouteStopSummary> stops;
}

abstract class RouteRepository {
  Future<List<RouteSummary>> fetchMyRoutes({DateTime? date});
  Future<RouteSummary> startRoute({
    required String routeId,
    required double latitude,
    required double longitude,
    required DateTime startedAt,
  });
}

class DioRouteRepository implements RouteRepository {
  DioRouteRepository(this._dio);

  final Dio _dio;

  @override
  Future<List<RouteSummary>> fetchMyRoutes({DateTime? date}) async {
    final response = await _dio.get<List<dynamic>>(
      '/routes/me',
      queryParameters: {
        if (date != null) 'date': date.toIso8601String().split('T').first,
      },
    );
    return response.data!
        .map((raw) => RouteSummary.fromJson(raw as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<RouteSummary> startRoute({
    required String routeId,
    required double latitude,
    required double longitude,
    required DateTime startedAt,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/routes/$routeId/start',
      data: {
        'latitude': latitude,
        'longitude': longitude,
        // Client-supplied (spec Ruling 8): the outbox worker passes the
        // tap-time instant so a late sync still records when the field
        // worker actually started, not when the row happened to drain.
        'started_at': startedAt.toUtc().toIso8601String(),
      },
    );
    return RouteSummary.fromJson(response.data!);
  }
}
