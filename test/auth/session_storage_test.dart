import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/auth/session_storage.dart';

const _session = Session(
  accessToken: 'a-token',
  refreshToken: 'r-token',
  role: 'FIELD_WORKER',
  consentRequired: true,
);

void main() {
  test('InMemorySessionStorage round-trips the whole session', () async {
    final storage = InMemorySessionStorage();

    await storage.saveSession(_session);

    final restored = await storage.readSession();
    expect(restored?.accessToken, 'a-token');
    expect(restored?.refreshToken, 'r-token');
    expect(restored?.role, 'FIELD_WORKER');
    expect(restored?.consentRequired, isTrue);
  });

  test('InMemorySessionStorage clears the session', () async {
    final storage = InMemorySessionStorage();
    await storage.saveSession(_session);

    await storage.clear();

    expect(await storage.readSession(), isNull);
  });
}
