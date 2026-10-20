import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/api/api_client.dart';

void main() {
  group('refresh on 401', refreshInterceptorTests);
  group('worker not approved', workerNotApprovedTests);

  test('buildDio sets the base URL', () {
    final dio = buildDio(baseUrl: 'http://localhost:8000');

    expect(dio.options.baseUrl, 'http://localhost:8000');
  });

  test('buildDio attaches the bearer token when one is provided', () {
    final dio = buildDio(
      baseUrl: 'http://localhost:8000',
      accessToken: 'a-test-token',
    );

    expect(dio.options.headers['Authorization'], 'Bearer a-test-token');
  });

  test('buildDio omits the Authorization header without a token', () {
    final dio = buildDio(baseUrl: 'http://localhost:8000');

    expect(dio.options.headers.containsKey('Authorization'), isFalse);
  });
}

/// Answers 401 to any request whose bearer is not [validToken], 200
/// otherwise — a named fake transport, so the interceptor runs without
/// touching the network.
class _TokenCheckingAdapter implements HttpClientAdapter {
  _TokenCheckingAdapter(this.validToken);

  final String validToken;
  final List<String?> seenAuthorization = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final header = options.headers['Authorization'] as String?;
    seenAuthorization.add(header);
    final ok = header == 'Bearer $validToken';
    return ResponseBody.fromString(
      ok ? '{"ok":true}' : '{"detail":"expired"}',
      ok ? 200 : 401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void refreshInterceptorTests() {
  test('a 401 refreshes the token once and retries the request', () async {
    var refreshCalls = 0;
    final dio = buildDio(
      baseUrl: 'http://localhost:8000',
      accessToken: 'expired',
      onUnauthorized: () async {
        refreshCalls++;
        return 'fresh';
      },
    );
    final adapter = _TokenCheckingAdapter('fresh');
    dio.httpClientAdapter = adapter;

    final response = await dio.get<Map<String, dynamic>>('/routes/me');

    expect(response.statusCode, 200);
    expect(refreshCalls, 1);
    expect(adapter.seenAuthorization, ['Bearer expired', 'Bearer fresh']);
  });

  test('a refresh that yields nothing surfaces the original 401', () async {
    final dio = buildDio(
      baseUrl: 'http://localhost:8000',
      accessToken: 'expired',
      onUnauthorized: () async => null,
    )..httpClientAdapter = _TokenCheckingAdapter('fresh');

    await expectLater(
      dio.get<void>('/routes/me'),
      throwsA(
        isA<DioException>().having(
          (error) => error.response?.statusCode,
          'status',
          401,
        ),
      ),
    );
  });

  test('a second 401 after the retry is not retried again', () async {
    var refreshCalls = 0;
    final dio = buildDio(
      baseUrl: 'http://localhost:8000',
      accessToken: 'expired',
      onUnauthorized: () async {
        refreshCalls++;
        return 'still-wrong';
      },
    )..httpClientAdapter = _TokenCheckingAdapter('fresh');

    await expectLater(
      dio.get<void>('/routes/me'),
      throwsA(isA<DioException>()),
    );
    expect(refreshCalls, 1);
  });
}

/// Answers every request with [statusCode] and [body].
class _FixedAdapter implements HttpClientAdapter {
  _FixedAdapter(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

void workerNotApprovedTests() {
  test('a 403 WORKER_NOT_APPROVED is reported, then surfaced', () async {
    var reports = 0;
    final dio =
        buildDio(
            baseUrl: 'http://localhost:8000',
            accessToken: 'token',
            onWorkerNotApproved: () async => reports++,
          )
          ..httpClientAdapter = _FixedAdapter(
            403,
            '{"detail":{"code":"WORKER_NOT_APPROVED","detail":"not approved"}}',
          );

    await expectLater(
      dio.get<void>('/routes/me'),
      throwsA(
        isA<DioException>().having(
          (error) => error.response?.statusCode,
          'status',
          403,
        ),
      ),
    );
    expect(reports, 1);
  });

  test('any other 403 is not reported', () async {
    var reports = 0;
    final dio =
        buildDio(
            baseUrl: 'http://localhost:8000',
            accessToken: 'token',
            onWorkerNotApproved: () async => reports++,
          )
          ..httpClientAdapter = _FixedAdapter(
            403,
            '{"detail":"Consent to the current privacy notice is required."}',
          );

    await expectLater(
      dio.get<void>('/routes/me'),
      throwsA(isA<DioException>()),
    );
    expect(reports, 0);
  });
}
