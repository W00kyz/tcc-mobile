import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/api/api_client.dart';

void main() {
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
