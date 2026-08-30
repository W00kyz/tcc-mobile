import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/auth/auth_repository.dart';

void main() {
  test('login returns tokens on a 200 response', () async {
    // Access token shaped like a real JWT (header.payload.signature) because
    // DioAuthRepository decodes the `role` claim out of the payload segment —
    // a bare string here would make that decode throw a RangeError.
    const accessToken = 'a.eyJyb2xlIjoiRklFTERfV09SS0VSIn0.c';
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(
        statusCode: 200,
        body: {
          'access_token': accessToken,
          'refresh_token': 'r',
          'token_type': 'bearer',
        },
      );
    final repository = DioAuthRepository(dio);

    final session = await repository.login(
      email: 'joao@empresa.com',
      password: 'senha-forte-o-suficiente',
    );

    expect(session.accessToken, accessToken);
    expect(session.refreshToken, 'r');
    expect(session.role, 'FIELD_WORKER');
  });

  test('login throws InvalidCredentialsException on a 401 response', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(
        statusCode: 401,
        body: {'detail': 'Invalid'},
      );
    final repository = DioAuthRepository(dio);

    expect(
      () =>
          repository.login(email: 'joao@empresa.com', password: 'senha-errada'),
      throwsA(isA<InvalidCredentialsException>()),
    );
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final Map<String, dynamic> body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
