import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:route_monitor/forms/form_schema.dart';
import 'package:route_monitor/routing/route_snapshot_cache.dart';

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
    this.expectedArrivalFrom,
    this.expectedArrivalTo,
    this.distanceFromPrevM,
    this.durationFromPrevS,
    this.legGeometry,
    this.serviceTypeId,
    this.serviceTypeName,
    this.form,
    this.reassigned = false,
  });

  factory RouteStopSummary.fromJson(Map<String, dynamic> json) =>
      RouteStopSummary(
        id: json['id'] as String,
        orderIndex: json['order_index'] as int,
        status: json['status'] as String,
        servicePointName: json['service_point_name'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
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
        serviceTypeId: json['service_type_id'] as String?,
        serviceTypeName: json['service_type_name'] as String?,
        form: json['form'] == null
            ? null
            : FormSchema.fromJson(json['form'] as Map<String, dynamic>),
        reassigned: json['reassigned'] as bool? ?? false,
      );

  final String id;
  final int orderIndex;
  final String status;
  final String servicePointName;
  final double latitude;
  final double longitude;
  final DateTime? expectedArrivalFrom;
  final DateTime? expectedArrivalTo;
  final double? distanceFromPrevM;
  final double? durationFromPrevS;
  final List<List<double>>? legGeometry;

  /// The service type assigned to this stop (RF-adjacent metadata, not yet
  /// surfaced in the UI) — null for a stop with none.
  final String? serviceTypeId;
  final String? serviceTypeName;

  /// The stop's PUBLISHED `active_form_version` and its ordered questions
  /// (spec §6.2), or null when the stop's service type has no form attached.
  final FormSchema? form;

  /// True when this stop was moved onto the current route by an emergency
  /// substitution/reassignment (Etapa 8, RF20) — the substitute sees a
  /// "Reatribuído" badge. Defaults to false: a stop from an older backend,
  /// or the common not-reassigned case.
  final bool reassigned;
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
  /// With a [cache] (and the signed-in [userId] that keys it), today's route
  /// list is saved after every successful fetch and served from the device
  /// when the network is unreachable.
  DioRouteRepository(this._dio, {RouteSnapshotCache? cache, String? userId})
    // Public named params can't be initializing formals for private fields
    // (same idiom as sync_worker.dart).
    // ignore: prefer_initializing_formals
    : _cache = cache,
      // Same reason as `_cache` above.
      // ignore: prefer_initializing_formals
      _userId = userId;

  final Dio _dio;
  final RouteSnapshotCache? _cache;
  final String? _userId;

  @override
  Future<List<RouteSummary>> fetchMyRoutes({DateTime? date}) async {
    // Only "today" (no explicit date) is cached — it is the list the worker
    // acts on.
    final cache = date == null ? _cache : null;
    final userId = _userId ?? '';
    try {
      final response = await _dio.get<List<dynamic>>(
        '/routes/me',
        queryParameters: {
          if (date != null) 'date': date.toIso8601String().split('T').first,
        },
      );
      await cache?.save(userId, jsonEncode(response.data));
      return _parseRoutes(response.data!);
    } on DioException catch (error) {
      // No HTTP response at all = no network: fall back to the last list
      // this device saw. An HTTP error (401, 500) is a real answer — rethrow.
      final cached = error.response == null ? await cache?.load(userId) : null;
      if (cached == null) rethrow;
      return _parseRoutes(jsonDecode(cached) as List<dynamic>);
    }
  }

  List<RouteSummary> _parseRoutes(List<dynamic> body) => body
      .map((raw) => RouteSummary.fromJson(raw as Map<String, dynamic>))
      .toList();

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
