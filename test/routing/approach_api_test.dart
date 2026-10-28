import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_monitor/routing/approach_api.dart';

void main() {
  test('GETs /routes/me/approach and flips the [lng, lat] geometry', () async {
    late RequestOptions captured;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _ApproachAdapter(
        statusCode: 200,
        body: jsonEncode({
          'route_stop_id': 's2',
          'geometry': [
            [-35.909, -7.214],
            [-35.9095, -7.215],
          ],
          'distance_m': 120,
          'duration_s': 90.5,
        }),
        onRequest: (options) => captured = options,
      );

    final leg = await DioApproachApi(
      dio,
    ).fetchApproach(latitude: -7.214, longitude: -35.909);

    expect(captured.path, '/routes/me/approach');
    expect(captured.queryParameters, {'lat': -7.214, 'lng': -35.909});
    expect(leg!.routeStopId, 's2');
    expect(leg.points, const [
      LatLng(-7.214, -35.909),
      LatLng(-7.215, -35.9095),
    ]);
    expect((leg.distanceM, leg.durationS), (120.0, 90.5));
  });

  test('a 204 means no next stop: null', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _ApproachAdapter(statusCode: 204, body: '');

    final leg = await DioApproachApi(
      dio,
    ).fetchApproach(latitude: -7.214, longitude: -35.909);

    expect(leg, isNull);
  });

  test('a 503 (OSRM down) throws, for the caller to fall back', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _ApproachAdapter(
        statusCode: 503,
        body: jsonEncode({
          'detail': {'code': 'OSRM_UNAVAILABLE', 'detail': 'down'},
        }),
      );

    expect(
      DioApproachApi(dio).fetchApproach(latitude: -7.2, longitude: -35.9),
      throwsA(isA<DioException>()),
    );
  });

  test('a geometry point that is not a pair names itself', () {
    expect(
      () => ApproachLeg.fromJson({
        'route_stop_id': 's2',
        'geometry': [
          [-35.9],
        ],
        'distance_m': 1,
        'duration_s': 1,
      }),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('[-35.9]'),
        ),
      ),
    );
  });
}

class _ApproachAdapter implements HttpClientAdapter {
  _ApproachAdapter({
    required this.statusCode,
    required this.body,
    this.onRequest,
  });

  final int statusCode;
  final String body;
  final void Function(RequestOptions)? onRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    onRequest?.call(options);
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
