import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/checkin/checkin_repository.dart';

void main() {
  test(
    'checkIn posts the QR payload, position and a generated idempotency key',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      late RequestOptions captured;
      dio.httpClientAdapter = _FakeAdapter(
        statusCode: 201,
        body: {'execution_id': 'e1', 'checked_in_at': '2026-08-25T08:20:00Z'},
        onRequest: (options) => captured = options,
      );
      final repository = DioCheckInRepository(dio);

      await repository.checkIn(
        routeStopId: 's1',
        qrPayload: 'v1.floor.1.sig',
        latitude: -7.2,
        longitude: -35.9,
      );

      final body = captured.data as Map;
      expect(body['route_stop_id'], 's1');
      expect(body['qr_payload'], 'v1.floor.1.sig');
      expect(body['idempotency_key'], isNotEmpty);
    },
  );
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.statusCode, required this.body, this.onRequest});
  final int statusCode;
  final Map<String, dynamic> body;
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
