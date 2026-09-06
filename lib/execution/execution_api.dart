import 'dart:io' show HttpDate;

import 'package:dio/dio.dart';

/// The backend's response to a successful check-in (`app/api/checkins.py`,
/// `CheckInResponse`) — the Layer 7 (QR + GPS) validation outcome for the
/// stop the floor cross-reference resolved to.
class CheckInResult {
  const CheckInResult({
    required this.routeStopId,
    required this.executionId,
    required this.geoValidation,
    required this.flags,
  });

  final String routeStopId;

  /// The backend's `execution_id` (`CheckInResponse.execution_id`) — the app
  /// has no other way to learn it (spec §6.3b Ruling 17: `RouteStopOut` has
  /// no `execution_id` field, and `GET /executions` is MANAGER/ADMIN-only),
  /// so `ExecutionRepository.checkIn` records it in `OpenExecutions` for the
  /// evidence endpoints to use later.
  final String executionId;
  final String geoValidation;
  final List<String> flags;
}

/// One candidate service point returned by the backend's 409 "multiple
/// service points on this floor" body.
class RoomCandidate {
  const RoomCandidate({
    required this.routeStopId,
    required this.servicePointId,
    required this.name,
    this.distanceM,
  });

  final String routeStopId;
  final String servicePointId;
  final String name;
  final double? distanceM;
}

/// Thrown when the backend's floor-QR cross-reference (spec §5.3) finds more
/// than one candidate room on the scanned floor and cannot resolve one
/// automatically. Carries every candidate so the UI can ask the field worker
/// to choose (Task 18 — the picker itself is out of scope here).
class AmbiguousRoomException implements Exception {
  const AmbiguousRoomException(this.candidates);
  final List<RoomCandidate> candidates;
}

/// The backend's response to a successful check-out (`app/api/checkouts.py`,
/// `CheckOutResponse`).
class CheckOutResult {
  const CheckOutResult({
    required this.routeStopId,
    required this.executionId,
    required this.checkedOutAt,
    required this.flags,
  });

  final String routeStopId;

  /// See `CheckInResult.executionId` — same Ruling 17 rationale, this time
  /// used to clear the `OpenExecutions` row for the stop.
  final String executionId;
  final DateTime checkedOutAt;
  final List<String> flags;
}

// This interface is the seam that keeps ExecutionRepository's tests off the
// real HTTP client (docs/CLAUDE.base.md — Dependencies: "wrap third-party
// libs behind a thin interface").
abstract class ExecutionApi {
  /// Returns the parsed body alongside the response's `Date` header
  /// (`serverDate`, null when absent/unparseable) so the sync worker can
  /// measure the device-vs-server clock offset (spec Ruling 7).
  Future<({CheckInResult result, DateTime? serverDate})> checkIn({
    required String executionId,
    required String qrPayload,
    required DateTime scannedAt,
    required String idempotencyKey,
    double? latitude,
    double? longitude,
    String? routeStopId,
    double? clientClockOffsetSeconds,
  });

  Future<({CheckOutResult result, DateTime? serverDate})> checkOut({
    required String executionId,
    required String qrPayload,
    required DateTime scannedAt,
    required String checkoutIdempotencyKey,
    double? latitude,
    double? longitude,
    String? routeStopId,
    double? clientClockOffsetSeconds,
    String? formVersionId,
    List<Map<String, Object?>>? answers,
  });

  /// Signals an impossibility to execute (spec RF16-RF17): `scope='STOP'` with
  /// a [routeStopId] for one stop, `scope='ROUTE_REMAINDER'` with a null
  /// [routeStopId] for the rest of the route. Returns nothing — the backend's
  /// response is just the created row, and the clock offset is already
  /// measured on every check-in/out (spec Ruling 7). A 409
  /// (`RouteNotInProgress`/`StopNotPending`) is a hard failure for the sync
  /// worker: the report can never succeed for this route state.
  Future<void> reportImpediment({
    required String routeId,
    required String? routeStopId,
    required String scope,
    required String reason,
    required DateTime reportedAt,
    String? note,
  });
}

/// The response's `Date` header parsed to a [DateTime], or null when the
/// header is missing or not an RFC-1123 date. Shared by every method here and
/// in `EvidenceApi` — the worker reads it once per successful dispatch.
DateTime? parseServerDate(Headers headers) {
  final raw = headers.value('date');
  if (raw == null) return null;
  try {
    return HttpDate.parse(raw);
  } on Exception {
    return null;
  }
}

class DioExecutionApi implements ExecutionApi {
  DioExecutionApi(this._dio);

  final Dio _dio;

  @override
  Future<({CheckInResult result, DateTime? serverDate})> checkIn({
    required String executionId,
    required String qrPayload,
    required DateTime scannedAt,
    required String idempotencyKey,
    double? latitude,
    double? longitude,
    String? routeStopId,
    double? clientClockOffsetSeconds,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/check-ins',
        data: {
          'execution_id': executionId,
          'qr_payload': qrPayload,
          'latitude': latitude,
          'longitude': longitude,
          'scanned_at': scannedAt.toUtc().toIso8601String(),
          'idempotency_key': idempotencyKey,
          'route_stop_id': routeStopId,
          'client_clock_offset_seconds': clientClockOffsetSeconds,
        },
      );
      final body = response.data!;
      return (
        result: CheckInResult(
          routeStopId: body['route_stop_id'] as String,
          executionId: body['execution_id'] as String,
          geoValidation: body['geo_validation'] as String,
          flags: (body['validation_flags'] as List).cast<String>(),
        ),
        serverDate: parseServerDate(response.headers),
      );
    } on DioException catch (e) {
      final candidates = _ambiguousRoomCandidates(e);
      if (candidates != null) throw AmbiguousRoomException(candidates);
      rethrow;
    }
  }

  @override
  Future<({CheckOutResult result, DateTime? serverDate})> checkOut({
    required String executionId,
    required String qrPayload,
    required DateTime scannedAt,
    required String checkoutIdempotencyKey,
    double? latitude,
    double? longitude,
    String? routeStopId,
    double? clientClockOffsetSeconds,
    String? formVersionId,
    List<Map<String, Object?>>? answers,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/check-outs',
        data: {
          // The backend accepts `execution_id` here for symmetry with
          // check-in but ignores it (the open check-in already pins the
          // execution) — still sent so the outbox payload shape is uniform.
          'execution_id': executionId,
          'qr_payload': qrPayload,
          'latitude': latitude,
          'longitude': longitude,
          'scanned_at': scannedAt.toUtc().toIso8601String(),
          'checkout_idempotency_key': checkoutIdempotencyKey,
          'route_stop_id': routeStopId,
          'client_clock_offset_seconds': clientClockOffsetSeconds,
          // Task 14 — the stop's form draft, carried through only when one
          // exists (a stop with no form, or an already-cleared draft, sends
          // neither field, same null-when-absent convention as every other
          // optional field above).
          'form_version_id': formVersionId,
          'answers': answers,
        },
      );
      final body = response.data!;
      return (
        result: CheckOutResult(
          routeStopId: body['route_stop_id'] as String,
          executionId: body['execution_id'] as String,
          checkedOutAt: DateTime.parse(body['checked_out_at'] as String),
          flags: (body['validation_flags'] as List).cast<String>(),
        ),
        serverDate: parseServerDate(response.headers),
      );
    } on DioException catch (e) {
      final candidates = _ambiguousRoomCandidates(e);
      if (candidates != null) throw AmbiguousRoomException(candidates);
      rethrow;
    }
  }

  @override
  Future<void> reportImpediment({
    required String routeId,
    required String? routeStopId,
    required String scope,
    required String reason,
    required DateTime reportedAt,
    String? note,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/routes/$routeId/impediments',
      data: {
        'route_stop_id': routeStopId,
        'scope': scope,
        'reason': reason,
        'note': note,
        'reported_at': reportedAt.toUtc().toIso8601String(),
      },
    );
  }
}

/// Parses the 409 "multiple service points on this floor" body, shared by
/// `checkIn` (`backend/app/api/checkins.py`) and `checkOut`
/// (`backend/app/api/checkouts.py`'s `_ambiguous_conflict`) — byte-for-byte
/// the same nesting on both endpoints. FastAPI's `HTTPException(409,
/// detail={...})` wraps our payload, so the actual response is
/// `{"detail": {"detail": "...", "candidates": [...]}}` — the outer `detail`
/// is FastAPI's own envelope, the inner `detail`+`candidates` is this app's.
/// Returns null for every other 409 (RouteNotStarted, RouteCancelled, "no
/// active route today" — all plain-string `detail`) and for any non-409
/// status (e.g. check-out's `422 NO_OPEN_CHECKIN`, also a plain string) —
/// the `statusCode != 409` guard below is what keeps that 422 from ever
/// being misparsed as ambiguous. Both are left to
/// propagate as an unhandled DioException like every other repository here.
List<RoomCandidate>? _ambiguousRoomCandidates(DioException error) {
  if (error.response?.statusCode != 409) return null;
  final data = error.response?.data;
  if (data is! Map) return null;
  final inner = data['detail'];
  if (inner is! Map) return null;
  final candidates = inner['candidates'];
  if (candidates is! List) return null;
  return candidates
      .cast<Map<String, dynamic>>()
      .map(
        (c) => RoomCandidate(
          routeStopId: c['route_stop_id'] as String,
          servicePointId: c['service_point_id'] as String,
          name: c['name'] as String,
          distanceM: (c['distance_m'] as num?)?.toDouble(),
        ),
      )
      .toList();
}
