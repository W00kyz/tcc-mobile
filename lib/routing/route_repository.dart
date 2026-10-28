import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:route_monitor/api/api_client.dart' show apiErrorCode;
import 'package:route_monitor/routing/route_snapshot_cache.dart';

DateTime? _parseOptionalTimestamp(Object? raw) =>
    raw == null ? null : DateTime.parse(raw as String);

class RouteStopSummary {
  const RouteStopSummary({
    required this.id,
    required this.orderIndex,
    required this.batchNumber,
    required this.status,
    required this.servicePointName,
    required this.buildingId,
    required this.buildingName,
    required this.floorLabel,
    required this.latitude,
    required this.longitude,
    this.releaseReason,
    this.doneAt,
    this.distanceFromPrevM,
    this.durationFromPrevS,
    this.legGeometry,
    this.serviceTypeId,
    this.serviceTypeName,
    this.requiresEvidence = false,
  });

  factory RouteStopSummary.fromJson(Map<String, dynamic> json) =>
      RouteStopSummary(
        id: json['id'] as String,
        orderIndex: json['order_index'] as int,
        batchNumber: json['batch_number'] as int,
        status: json['status'] as String,
        releaseReason: json['release_reason'] as String?,
        servicePointName: json['service_point_name'] as String,
        buildingId: json['building_id'] as String,
        buildingName: json['building_name'] as String,
        floorLabel: json['floor_label'] as String,
        doneAt: _parseOptionalTimestamp(json['done_at']),
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
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
        requiresEvidence: json['requires_evidence'] as bool? ?? false,
      );

  final String id;

  /// Position in the whole day's route — it keeps counting across batches.
  final int orderIndex;

  /// The allocation batch that handed this stop out (spec §6.2).
  final int batchNumber;

  /// `PENDING` | `IN_PROGRESS` | `DONE` | `RELEASED` (back in the pool).
  final String status;

  /// Why a `RELEASED` stop went back to the pool (`IMPEDIMENT`,
  /// `ROUTE_REMAINDER`, `LEFT_CAMPUS`, `LOCATION_SILENCE`, `END_OF_DAY`);
  /// null for any other status.
  final String? releaseReason;
  final String servicePointName;
  final String buildingId;
  final String buildingName;
  final String floorLabel;

  /// When the server recorded the stop done; null until then.
  final DateTime? doneAt;
  final double latitude;
  final double longitude;
  final double? distanceFromPrevM;
  final double? durationFromPrevS;
  final List<List<double>>? legGeometry;

  /// The service type assigned to this stop (RF-adjacent metadata, not yet
  /// surfaced in the UI) — null for a stop with none.
  final String? serviceTypeId;
  final String? serviceTypeName;

  /// Copied onto the stop at allocation: it needs at least 2 photos before
  /// "Concluir" and asks for complaints/suggestions on the way out.
  final bool requiresEvidence;
}

class RouteSummary {
  const RouteSummary({
    required this.id,
    required this.fieldWorkerName,
    required this.routeDate,
    required this.status,
    required this.startedAt,
    required this.currentBatch,
    required this.stops,
  });

  factory RouteSummary.fromJson(Map<String, dynamic> json) => RouteSummary(
    id: json['id'] as String,
    fieldWorkerName: json['field_worker_name'] as String,
    // route_date is a date-only ISO string ("YYYY-MM-DD"); DateTime.parse
    // reads it as local midnight, which is all the day view needs.
    routeDate: DateTime.parse(json['route_date'] as String),
    status: json['status'] as String,
    startedAt: _parseOptionalTimestamp(json['started_at']),
    currentBatch: json['current_batch'] as int,
    stops: (json['stops'] as List<dynamic>)
        .map((raw) => RouteStopSummary.fromJson(raw as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final String fieldWorkerName;
  final DateTime routeDate;

  /// `IN_PROGRESS` | `PAUSED` (points released, "Iniciar rota" resumes) |
  /// `DONE` (pool empty or end of the workday).
  final String status;
  final DateTime? startedAt;
  final int currentBatch;

  /// Every stop of the day, of every batch, released ones included.
  final List<RouteStopSummary> stops;

  /// Points done today over every batch. `RouteOut` carries no count, so it
  /// is derived from the stops the server reports `DONE`.
  int get doneToday => stops.where((stop) => stop.status == 'DONE').length;

  /// The stops the worker acts on: the current batch, minus the released
  /// ones (they went back to the pool).
  List<RouteStopSummary> get currentBatchStops => stops
      .where(
        (stop) => stop.batchNumber == currentBatch && stop.status != 'RELEASED',
      )
      .toList();

  /// True once no stop of the current batch is left to work: each one is
  /// `DONE`/`RELEASED` on the server or done on this device ([doneLocally],
  /// the stop ids with a local check-out the server may not have yet).
  ///
  ///     route.currentBatchClosed(doneLocally: {'stop-3'})
  bool currentBatchClosed({Set<String> doneLocally = const {}}) => stops
      .where((stop) => stop.batchNumber == currentBatch)
      .every(
        (stop) =>
            stop.status == 'DONE' ||
            stop.status == 'RELEASED' ||
            doneLocally.contains(stop.id),
      );

  /// Why the most recent stop went back to the pool — what a `PAUSED` route
  /// tells the worker — or null when none was released.
  String? get latestReleaseReason => stops.reversed
      .where((stop) => stop.status == 'RELEASED')
      .firstOrNull
      ?.releaseReason;
}

/// `GET /routes/me`: the worker's day — today's route, if any, and the
/// location limits the app works with (spec §7.3).
class MyDay {
  const MyDay({
    required this.serviceDay,
    required this.route,
    required this.positionIntervalSeconds,
    required this.silenceWarningMinutes,
    required this.silenceReleaseMinutes,
  });

  factory MyDay.fromJson(Map<String, dynamic> json) {
    final route = json['route'];
    return MyDay(
      serviceDay: json['service_day'] as bool,
      route: route == null
          ? null
          : RouteSummary.fromJson(route as Map<String, dynamic>),
      positionIntervalSeconds: json['position_report_interval_seconds'] as int,
      silenceWarningMinutes: json['location_silence_warning_minutes'] as int,
      silenceReleaseMinutes: json['location_silence_release_minutes'] as int,
    );
  }

  final bool serviceDay;

  /// Null until the first "Iniciar rota" of the day.
  final RouteSummary? route;
  final int positionIntervalSeconds;
  final int silenceWarningMinutes;
  final int silenceReleaseMinutes;
}

/// `POST /routes/start` and `POST /routes/{id}/next-batch`: the route with
/// its current batch, and whether the pool ran out (the route is then DONE).
class AllocationResult {
  const AllocationResult({required this.route, required this.poolEmpty});

  factory AllocationResult.fromJson(Map<String, dynamic> json) =>
      AllocationResult(
        route: RouteSummary.fromJson(json['route'] as Map<String, dynamic>),
        poolEmpty: json['pool_empty'] as bool,
      );

  final RouteSummary route;
  final bool poolEmpty;
}

/// 409 `NOT_A_SERVICE_DAY`: no allocation on a day without service.
final class NotAServiceDayException implements Exception {
  const NotAServiceDayException();

  @override
  String toString() =>
      'NotAServiceDayException: allocation refused with NOT_A_SERVICE_DAY; '
      'expected a service weekday.';
}

/// 409 `WORKDAY_OVER`: asked for a batch after the end of the workday.
final class WorkdayOverException implements Exception {
  const WorkdayOverException();

  @override
  String toString() =>
      'WorkdayOverException: allocation refused with WORKDAY_OVER; expected '
      'a request before the end of the workday.';
}

/// 409 `OUTSIDE_CAMPUS`: the position sent lies outside the campus.
final class OutsideCampusException implements Exception {
  const OutsideCampusException();

  @override
  String toString() =>
      'OutsideCampusException: allocation refused with OUTSIDE_CAMPUS; '
      'expected a position inside the campus bounds.';
}

/// 409 `ROUTE_DONE`: the route asked about belongs to a past day (the app kept
/// yesterday's route past midnight). The server never refuses today's route
/// so — a DONE route of today is looked at again and answers `pool_empty`.
/// Shown like an empty pool: "no points now", and the day reloads.
final class RouteDoneException implements Exception {
  const RouteDoneException();

  @override
  String toString() =>
      'RouteDoneException: allocation refused with ROUTE_DONE; expected an '
      'open route.';
}

/// No HTTP response at all for [path] (and, for `GET /routes/me`, no snapshot
/// on the device to fall back to).
final class OfflineException implements Exception {
  const OfflineException(this.path);

  final String path;

  @override
  String toString() =>
      'OfflineException: no response from "$path"; expected a reachable '
      'server.';
}

abstract class RouteRepository {
  /// Today's day; offline, the last one this device saw.
  Future<MyDay> fetchMyDay();

  /// "Iniciar rota": creates or reopens today's route and hands out a batch.
  /// Retrying while the batch is open returns it unchanged.
  Future<AllocationResult> startOrResume({
    required double lat,
    required double lng,
    required DateTime capturedAt,
  });

  /// The next batch once the current one has no open stop (the current one,
  /// unchanged, while it still has).
  Future<AllocationResult> nextBatch(
    String routeId, {
    required double lat,
    required double lng,
    required DateTime capturedAt,
  });
}

class DioRouteRepository implements RouteRepository {
  /// With a [cache] (and the signed-in [userId] that keys it), the day is
  /// saved after every successful fetch and served from the device when the
  /// network is unreachable.
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

  static const _myDayPath = '/routes/me';

  @override
  Future<MyDay> fetchMyDay() async {
    final userId = _userId ?? '';
    try {
      final response = await _dio.get<Map<String, dynamic>>(_myDayPath);
      await _cache?.save(userId, jsonEncode(response.data));
      return MyDay.fromJson(response.data!);
    } on DioException catch (error) {
      // An HTTP error (401, 500) is a real answer — rethrow. No HTTP response
      // at all = no network: fall back to the last day this device saw.
      if (error.response != null) rethrow;
      final cached = await _cache?.load(userId);
      final day = cached == null ? null : _parseSnapshot(cached);
      if (day == null) throw const OfflineException(_myDayPath);
      return day;
    }
  }

  /// The saved day, or null when it no longer parses. A snapshot saved by an
  /// older build lacks fields this one requires (`building_id`,
  /// `building_name`, `floor_label`): it counts as no snapshot rather than
  /// a crash offline (final review M-4). The next online fetch replaces it.
  static MyDay? _parseSnapshot(String cached) {
    try {
      return MyDay.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      // A missing or mistyped field fails the `as` casts in fromJson with a
      // TypeError; a corrupt string fails jsonDecode.
      // ignore: avoid_catching_errors
    } on TypeError {
      return null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<AllocationResult> startOrResume({
    required double lat,
    required double lng,
    required DateTime capturedAt,
  }) => _allocate('/routes/start', lat, lng, capturedAt);

  @override
  Future<AllocationResult> nextBatch(
    String routeId, {
    required double lat,
    required double lng,
    required DateTime capturedAt,
  }) => _allocate('/routes/$routeId/next-batch', lat, lng, capturedAt);

  Future<AllocationResult> _allocate(
    String path,
    double lat,
    double lng,
    DateTime capturedAt,
  ) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        path,
        data: {
          'latitude': lat,
          'longitude': lng,
          'captured_at': capturedAt.toUtc().toIso8601String(),
        },
      );
      return AllocationResult.fromJson(response.data!);
    } on DioException catch (error) {
      if (error.response == null) throw OfflineException(path);
      final refusal = _refusalFor(error);
      if (refusal != null) throw refusal;
      // 403, 404 (another worker's route), 5xx: the caller's generic failure
      // path. A 403 CONSENT_REQUIRED / WORKER_NOT_APPROVED already flagged the
      // session on its way here (buildSessionDio), and the router moves on.
      rethrow;
    }
  }

  static Exception? _refusalFor(DioException error) {
    if (error.response?.statusCode != 409) return null;
    return switch (apiErrorCode(error)) {
      'NOT_A_SERVICE_DAY' => const NotAServiceDayException(),
      'WORKDAY_OVER' => const WorkdayOverException(),
      'OUTSIDE_CAMPUS' => const OutsideCampusException(),
      'ROUTE_DONE' => const RouteDoneException(),
      _ => null,
    };
  }
}
