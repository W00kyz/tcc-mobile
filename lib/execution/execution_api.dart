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

// A single-method interface is deliberate here, not an oversight: it is the
// seam that keeps ExecutionRepository's tests off the real HTTP client
// (docs/CLAUDE.base.md — Dependencies: "wrap third-party libs behind a thin
// interface"). check-out is Task 18's concern — declaring an unimplemented
// method now would force every concrete class (including test fakes) to
// stub a method nothing calls yet; Task 18 extends this interface instead.
// ignore: one_member_abstracts
abstract class ExecutionApi {
  Future<CheckInResult> checkIn({
    required String qrPayload,
    required DateTime scannedAt,
    required String idempotencyKey,
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
}

/// Parses the 409 "multiple service points on this floor" body
/// (`backend/app/api/checkins.py`). FastAPI's `HTTPException(409,
/// detail={...})` wraps our payload, so the actual response is
/// `{"detail": {"detail": "...", "candidates": [...]}}` — the outer `detail`
/// is FastAPI's own envelope, the inner `detail`+`candidates` is this app's.
/// Returns null for every other 409 (RouteNotStarted, RouteCancelled, "no
/// active route today" — all plain-string `detail`), which are left to
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
