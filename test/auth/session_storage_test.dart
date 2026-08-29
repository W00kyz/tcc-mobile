import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/auth/session_storage.dart';

void main() {
  test('InMemorySessionStorage round-trips a token', () async {
    final storage = InMemorySessionStorage();

    await storage.saveAccessToken('a-token');

    expect(await storage.readAccessToken(), 'a-token');
  });

  test('InMemorySessionStorage clears the token', () async {
    final storage = InMemorySessionStorage();
    await storage.saveAccessToken('a-token');

    await storage.clear();

    expect(await storage.readAccessToken(), isNull);
  });
}
