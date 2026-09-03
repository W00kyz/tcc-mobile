import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/routing/route_repository.dart';

Map<String, dynamic> _routePayload() => {
  'id': 'r1',
  'field_worker_name': 'João',
  'route_date': '2026-08-25',
  'route_type': 'REGULAR',
  'status': 'IN_PROGRESS',
  'scheduled_start_at': null,
  'started_at': '2026-08-25T08:15:00Z',
  'stops': [
    {
      'id': 's1',
      'order_index': 1,
      'status': 'PENDING',
      'service_point_name': 'Sala 101',
      'latitude': -7.21,
      'longitude': -35.91,
      'point_type': 'REGULAR',
      'expected_arrival_from': null,
      'expected_arrival_to': null,
      'distance_from_prev_m': null,
      'duration_from_prev_s': null,
      'leg_geometry': null,
    },
    {
      'id': 's2',
      'order_index': 2,
      'status': 'PENDING',
      'service_point_name': 'Sala 202',
      'latitude': -7.22,
      'longitude': -35.92,
      'point_type': 'OCCASIONAL',
      'expected_arrival_from': '2026-08-25T09:00:00Z',
      'expected_arrival_to': '2026-08-25T09:30:00Z',
      'distance_from_prev_m': 1234.5,
      'duration_from_prev_s': 180.0,
      'leg_geometry': [
        [-35.91, -7.21],
        [-35.915, -7.215],
        [-35.92, -7.22],
      ],
    },
  ],
};

void main() {
  test('fetchMyRoutes parses the stops in order', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(
        statusCode: 200,
        body: [_routePayload()],
      );
    final repository = DioRouteRepository(dio);

    final routes = await repository.fetchMyRoutes();

    expect(routes, hasLength(1));
    expect(routes.first.stops.first.servicePointName, 'Sala 101');
  });

  test('fetchMyRoutes parses the route type, status and date', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(
        statusCode: 200,
        body: [_routePayload()],
      );
    final repository = DioRouteRepository(dio);

    final route = (await repository.fetchMyRoutes()).first;

    expect(route.routeType, 'REGULAR');
    expect(route.status, 'IN_PROGRESS');
    expect(route.routeDate, DateTime.parse('2026-08-25'));
  });

  test('fetchMyRoutes parses the leg geometry and null legs', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(
        statusCode: 200,
        body: [_routePayload()],
      );
    final repository = DioRouteRepository(dio);

    final stops = (await repository.fetchMyRoutes()).first.stops;

    expect(stops[0].legGeometry, isNull);
    expect(stops[1].legGeometry, isA<List<List<double>>>());
    expect(stops[1].legGeometry, [
      [-35.91, -7.21],
      [-35.915, -7.215],
      [-35.92, -7.22],
    ]);
  });

  test(
    'fetchMyRoutes parses the arrival window, coordinates and leg cost',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = _FakeAdapter(
          statusCode: 200,
          body: [_routePayload()],
        );
      final repository = DioRouteRepository(dio);

      final stops = (await repository.fetchMyRoutes()).first.stops;

      expect(stops[0].expectedArrivalFrom, isNull);
      expect(stops[1].latitude, -7.22);
      expect(stops[1].longitude, -35.92);
      expect(stops[1].pointType, 'OCCASIONAL');
      expect(
        stops[1].expectedArrivalFrom,
        DateTime.parse('2026-08-25T09:00:00Z'),
      );
      expect(
        stops[1].expectedArrivalTo,
        DateTime.parse('2026-08-25T09:30:00Z'),
      );
      expect(stops[1].distanceFromPrevM, 1234.5);
      expect(stops[1].durationFromPrevS, 180.0);
    },
  );

  test(
    'fetchMyRoutes parses an IN_PROGRESS stop status the same way as '
    'PENDING/DONE — plain string pass-through, no enum mapping (Task 20)',
    () async {
      final payload = _routePayload();
      final stopsJson = (payload['stops'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      stopsJson[0]['status'] = 'IN_PROGRESS';
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = _FakeAdapter(
          statusCode: 200,
          body: [payload],
        );
      final repository = DioRouteRepository(dio);

      final stops = (await repository.fetchMyRoutes()).first.stops;

      expect(stops[0].status, 'IN_PROGRESS');
    },
  );

  test(
    'fetchMyRoutes forwards the date filter as a YYYY-MM-DD query',
    () async {
      late RequestOptions capturedRequest;
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = _FakeAdapter(
          statusCode: 200,
          body: <dynamic>[],
          onRequest: (options) => capturedRequest = options,
        );
      final repository = DioRouteRepository(dio);

      await repository.fetchMyRoutes(date: DateTime(2026, 9, 2));

      expect(capturedRequest.path, '/routes/me');
      expect(capturedRequest.uri.queryParameters['date'], '2026-09-02');
    },
  );

  test('fetchMyRoutes omits the date query when no date is given', () async {
    late RequestOptions capturedRequest;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(
        statusCode: 200,
        body: <dynamic>[],
        onRequest: (options) => capturedRequest = options,
      );
    final repository = DioRouteRepository(dio);

    await repository.fetchMyRoutes();

    expect(capturedRequest.uri.queryParameters.containsKey('date'), isFalse);
  });

  test('startRoute posts the captured position', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    late RequestOptions capturedRequest;
    dio.httpClientAdapter = _FakeAdapter(
      statusCode: 200,
      body: _routePayload(),
      onRequest: (options) => capturedRequest = options,
    );
    final repository = DioRouteRepository(dio);

    await repository.startRoute(
      routeId: 'r1',
      latitude: -7.2,
      longitude: -35.9,
      startedAt: DateTime.utc(2026, 8, 25, 8, 15),
    );

    expect(capturedRequest.path, '/routes/r1/start');
    expect((capturedRequest.data as Map)['latitude'], -7.2);
  });

  test(
    'startRoute sends the caller-supplied started_at, not DateTime.now',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      late RequestOptions capturedRequest;
      dio.httpClientAdapter = _FakeAdapter(
        statusCode: 200,
        body: _routePayload(),
        onRequest: (options) => capturedRequest = options,
      );
      final repository = DioRouteRepository(dio);
      final startedAt = DateTime.utc(2026, 8, 25, 8, 15);

      await repository.startRoute(
        routeId: 'r1',
        latitude: -7.2,
        longitude: -35.9,
        startedAt: startedAt,
      );

      expect(
        (capturedRequest.data as Map)['started_at'],
        startedAt.toIso8601String(),
      );
    },
  );
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
