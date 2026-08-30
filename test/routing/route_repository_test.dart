import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/routing/route_repository.dart';

void main() {
  test('fetchMyRoutes parses the stops in order', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(
        statusCode: 200,
        body: [
          {
            'id': 'r1',
            'field_worker_name': 'João',
            'scheduled_start_at': null,
            'started_at': null,
            'stops': [
              {
                'id': 's1',
                'order_index': 1,
                'status': 'PENDING',
                'service_point_name': 'Sala 101',
              },
            ],
          },
        ],
      );
    final repository = DioRouteRepository(dio);

    final routes = await repository.fetchMyRoutes();

    expect(routes, hasLength(1));
    expect(routes.first.stops.first.servicePointName, 'Sala 101');
  });

  test('startRoute posts the captured position', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    late RequestOptions capturedRequest;
    dio.httpClientAdapter = _FakeAdapter(
      statusCode: 200,
      body: {
        'id': 'r1',
        'field_worker_name': 'João',
        'scheduled_start_at': null,
        'started_at': '2026-08-25T08:15:00Z',
        'stops': <dynamic>[],
      },
      onRequest: (options) => capturedRequest = options,
    );
    final repository = DioRouteRepository(dio);

    await repository.startRoute(
      routeId: 'r1',
      latitude: -7.2,
      longitude: -35.9,
    );

    expect(capturedRequest.path, '/routes/r1/start');
    expect((capturedRequest.data as Map)['latitude'], -7.2);
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.statusCode, required this.body, this.onRequest});

  final int statusCode;
  final dynamic body;
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
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
