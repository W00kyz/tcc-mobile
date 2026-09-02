import 'package:dio/dio.dart';

/// The backend's response to a successful check-in (`app/api/checkins.py`,
/// `CheckInResponse`) — the Layer 7 (QR + GPS) validation outcome for the
/// stop the floor cross-reference resolved to.
class CheckInResult {
  const CheckInResult({
    required this.routeStopId,
    required this.geoValidation,
    required this.flags,
  });

  final String routeStopId;
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
    required this.checkedOutAt,
    required this.flags,
  });

  final String routeStopId;
  final DateTime checkedOutAt;
  final List<String> flags;
}

// This interface is the seam that keeps ExecutionRepository's tests off the
// real HTTP client (docs/CLAUDE.base.md — Dependencies: "wrap third-party
// libs behind a thin interface").
abstract class ExecutionApi {
  Future<CheckInResult> checkIn({
    required String qrPayload,
    required DateTime scannedAt,
    required String idempotencyKey,
    double? latitude,
    double? longitude,
    String? routeStopId,
  });

  Future<CheckOutResult> checkOut({
    required String qrPayload,
    required DateTime scannedAt,
    required String checkoutIdempotencyKey,
    double? latitude,
    double? longitude,
    String? routeStopId,
  });
}

class DioExecutionApi implements ExecutionApi {
  DioExecutionApi(this._dio);

  final Dio _dio;

  @override
  Future<CheckInResult> checkIn({
    required String qrPayload,
    required DateTime scannedAt,
    required String idempotencyKey,
    double? latitude,
    double? longitude,
    String? routeStopId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/check-ins',
        data: {
          'qr_payload': qrPayload,
          'latitude': latitude,
          'longitude': longitude,
          'scanned_at': scannedAt.toUtc().toIso8601String(),
          'idempotency_key': idempotencyKey,
          'route_stop_id': routeStopId,
        },
      );
      final body = response.data!;
      return CheckInResult(
        routeStopId: body['route_stop_id'] as String,
        geoValidation: body['geo_validation'] as String,
        flags: (body['validation_flags'] as List).cast<String>(),
      );
    } on DioException catch (e) {
      final candidates = _ambiguousRoomCandidates(e);
      if (candidates != null) throw AmbiguousRoomException(candidates);
      rethrow;
    }
  }

  @override
  Future<CheckOutResult> checkOut({
    required String qrPayload,
    required DateTime scannedAt,
    required String checkoutIdempotencyKey,
    double? latitude,
    double? longitude,
    String? routeStopId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/check-outs',
        data: {
          'qr_payload': qrPayload,
          'latitude': latitude,
          'longitude': longitude,
          'scanned_at': scannedAt.toUtc().toIso8601String(),
          'checkout_idempotency_key': checkoutIdempotencyKey,
          'route_stop_id': routeStopId,
        },
      );
      final body = response.data!;
      return CheckOutResult(
        routeStopId: body['route_stop_id'] as String,
        checkedOutAt: DateTime.parse(body['checked_out_at'] as String),
        flags: (body['validation_flags'] as List).cast<String>(),
      );
    } on DioException catch (e) {
      final candidates = _ambiguousRoomCandidates(e);
      if (candidates != null) throw AmbiguousRoomException(candidates);
      rethrow;
    }
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
