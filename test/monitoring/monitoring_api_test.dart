import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/monitoring/monitoring_api.dart';

void main() {
  test('reportPosition POSTs /worker-positions with the fix body', () async {
    late RequestOptions captured;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(
        statusCode: 202,
        onRequest: (options) => captured = options,
      );

    await DioMonitoringApi(dio).reportPosition(
      routeId: 'route-1',
      latitude: -7.21,
      longitude: -35.90,
      reportedAt: DateTime.utc(2026, 9, 7, 12, 30),
      accuracyM: 8.5,
    );

    expect(captured.path, '/worker-positions');
    expect(captured.method, 'POST');
    final body = captured.data as Map;
    expect(body['route_id'], 'route-1');
    expect(body['latitude'], -7.21);
    expect(body['longitude'], -35.90);
    expect(body['reported_at'], '2026-09-07T12:30:00.000Z');
    expect(body['accuracy_m'], 8.5);
  });

  test('reportPosition omits accuracy_m when not provided', () async {
    late RequestOptions captured;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(
        statusCode: 202,
        onRequest: (options) => captured = options,
      );

    await DioMonitoringApi(dio).reportPosition(
      routeId: 'route-1',
      latitude: -7.21,
      longitude: -35.90,
      reportedAt: DateTime.utc(2026, 9, 7, 12, 30),
    );

    expect((captured.data as Map).containsKey('accuracy_m'), isFalse);
  });

  test('reportPosition lets a 409 propagate as a DioException', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(statusCode: 409);

    await expectLater(
      DioMonitoringApi(dio).reportPosition(
        routeId: 'route-1',
        latitude: -7.21,
        longitude: -35.90,
        reportedAt: DateTime.utc(2026, 9, 7, 12, 30),
      ),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'statusCode',
          409,
        ),
      ),
    );
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.statusCode, this.onRequest});
  final int statusCode;
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
      jsonEncode(const <String, dynamic>{}),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
