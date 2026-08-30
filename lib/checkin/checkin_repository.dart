import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

// A single-method interface is deliberate here, not an oversight: it is the
// seam that keeps widget tests off the real HTTP client (docs/CLAUDE.base.md
// — Dependencies: "wrap third-party libs behind a thin interface").
// ignore: one_member_abstracts
abstract class CheckInRepository {
  Future<void> checkIn({
    required String routeStopId,
    required String qrPayload,
    required double latitude,
    required double longitude,
  });
}

class DioCheckInRepository implements CheckInRepository {
  DioCheckInRepository(this._dio);

  final Dio _dio;
  static const _uuid = Uuid();

  @override
  Future<void> checkIn({
    required String routeStopId,
    required String qrPayload,
    required double latitude,
    required double longitude,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/check-ins',
      data: {
        'route_stop_id': routeStopId,
        'qr_payload': qrPayload,
        'latitude': latitude,
        'longitude': longitude,
        'scanned_at': DateTime.now().toUtc().toIso8601String(),
        // Generated on the app, not the server — the seam Etapa 6 (offline)
        // reuses without changing shape (spec §5.1, decision #4).
        'idempotency_key': _uuid.v4(),
      },
    );
  }
}
