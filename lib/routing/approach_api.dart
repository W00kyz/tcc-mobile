import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

/// `GET /routes/me/approach`'s answer: the street path from where the worker
/// stands to their next stop, as OSRM walks it. Never cached — it is only
/// right for the position it was asked from.
class ApproachLeg {
  const ApproachLeg({
    required this.routeStopId,
    required this.points,
    required this.distanceM,
    required this.durationS,
  });

  /// Parses the backend's `ApproachOut`. The geometry arrives as `[lng, lat]`
  /// pairs (GeoJSON order, like `leg_geometry`) and is flipped to `LatLng`.
  ///
  ///     final leg = ApproachLeg.fromJson(response.data!);
  factory ApproachLeg.fromJson(Map<String, dynamic> json) => ApproachLeg(
    routeStopId: json['route_stop_id'] as String,
    points: [
      for (final pair in json['geometry'] as List<dynamic>)
        _latLngOf(pair as List<dynamic>),
    ],
    distanceM: (json['distance_m'] as num).toDouble(),
    durationS: (json['duration_s'] as num).toDouble(),
  );

  /// The stop the server measured to: the first PENDING of the batch.
  final String routeStopId;

  /// The polyline, worker first, in `LatLng(lat, lng)` order.
  final List<LatLng> points;
  final double distanceM;
  final double durationS;
}

LatLng _latLngOf(List<dynamic> pair) {
  if (pair.length != 2) {
    throw FormatException(
      'Approach geometry point $pair has ${pair.length} values; '
      'expected [lng, lat].',
    );
  }
  return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
}

/// The seam over `GET /routes/me/approach`, so the live first leg's tests
/// never reach the network (CLAUDE.md — Dependencies).
// A single-method interface on purpose, like `LocationService`.
// ignore: one_member_abstracts
abstract class ApproachApi {
  /// The street leg from ([latitude], [longitude]) to the next stop; null
  /// when the server has no PENDING stop for today (204). Throws on any
  /// failure — offline, or 503 when OSRM cannot route — and the caller
  /// draws a straight line instead.
  Future<ApproachLeg?> fetchApproach({
    required double latitude,
    required double longitude,
  });
}

class DioApproachApi implements ApproachApi {
  DioApproachApi(this._dio);

  static const String _path = '/routes/me/approach';

  final Dio _dio;

  @override
  Future<ApproachLeg?> fetchApproach({
    required double latitude,
    required double longitude,
  }) async {
    // Untyped on purpose: a 204 has no body, and Dio hands it back as an
    // empty string or null depending on the transformer.
    final response = await _dio.get<Object?>(
      _path,
      queryParameters: {'lat': latitude, 'lng': longitude},
    );
    final body = response.data;
    if (response.statusCode == 204) return null;
    if (body is! Map<String, dynamic>) {
      throw FormatException(
        'GET $_path answered ${response.statusCode} with "$body"; '
        'expected an ApproachOut object.',
      );
    }
    return ApproachLeg.fromJson(body);
  }
}
