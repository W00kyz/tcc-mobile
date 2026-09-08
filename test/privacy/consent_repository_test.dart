import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/privacy/consent_repository.dart';

void main() {
  test('status parses consent_required and the notice', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(
        statusCode: 200,
        body: {
          'consent_required': true,
          'notice': {
            'version': 3,
            'title': 'Antes de continuar',
            'body_markdown': 'A PU/UFCG coleta seus dados...',
          },
        },
      );
    final repository = DioConsentRepository(dio);

    final status = await repository.status();

    expect(status.consentRequired, isTrue);
    expect(status.noticeVersion, 3);
    expect(status.noticeTitle, 'Antes de continuar');
    expect(status.noticeBody, 'A PU/UFCG coleta seus dados...');
  });

  test('status tolerates a response with no notice', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(
        statusCode: 200,
        body: {'consent_required': false},
      );
    final repository = DioConsentRepository(dio);

    final status = await repository.status();

    expect(status.consentRequired, isFalse);
    expect(status.noticeTitle, isNull);
    expect(status.noticeBody, isNull);
  });

  test('accept issues a POST to /auth/consent', () async {
    late RequestOptions capturedRequest;
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(
        statusCode: 204,
        body: null,
        onRequest: (options) => capturedRequest = options,
      );
    final repository = DioConsentRepository(dio);

    await repository.accept();

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.path, '/auth/consent');
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
