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

  test('fetchNotifications GETs /notifications/me and parses items', () async {
    late RequestOptions captured;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(
        statusCode: 200,
        onRequest: (options) => captured = options,
        body: {
          'items': [
            {
              'id': 'n1',
              'kind': 'ALERT',
              'title': 'Nova rota',
              'body': 'Você recebeu uma rota para hoje.',
              'created_at': '2026-09-07T09:00:00Z',
              'read_at': null,
            },
          ],
          'total': 1,
          'page': 1,
          'page_size': 30,
        },
      );

    final result = await DioMonitoringApi(dio).fetchNotifications(limit: 15);

    expect(captured.path, '/notifications/me');
    expect(captured.method, 'GET');
    expect(captured.queryParameters['page_size'], 15);
    expect(result, hasLength(1));
    expect(result.single.id, 'n1');
    expect(result.single.kind, 'ALERT');
    expect(result.single.isUnread, isTrue);
  });

  test('unreadCount GETs /notifications/me/unread-count', () async {
    late RequestOptions captured;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(
        statusCode: 200,
        onRequest: (options) => captured = options,
        body: {'count': 4},
      );

    final count = await DioMonitoringApi(dio).unreadCount();

    expect(captured.path, '/notifications/me/unread-count');
    expect(captured.method, 'GET');
    expect(count, 4);
  });

  test('markRead POSTs /notifications/{id}/read', () async {
    late RequestOptions captured;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(
        statusCode: 204,
        onRequest: (options) => captured = options,
      );

    await DioMonitoringApi(dio).markRead('n1');

    expect(captured.path, '/notifications/n1/read');
    expect(captured.method, 'POST');
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({
    required this.statusCode,
    this.onRequest,
    this.body = const <String, dynamic>{},
  });
  final int statusCode;
  final void Function(RequestOptions)? onRequest;
  final Object body;

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
