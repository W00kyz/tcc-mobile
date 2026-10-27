import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  test('SecureSessionStorage persists the worker standing', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final storage = SecureSessionStorage();

    await storage.saveSession(
      const Session(
        accessToken: 'a-token',
        refreshToken: 'r-token',
        role: 'FIELD_WORKER',
        workerStanding: WorkerStanding(
          status: WorkerStatus.rejected,
          rejectionReason: 'Documento ilegível',
          active: true,
        ),
      ),
    );

    final standing = (await storage.readSession())?.workerStanding;
    expect(standing?.status, WorkerStatus.rejected);
    expect(standing?.rejectionReason, 'Documento ilegível');
    expect(standing?.active, isTrue);
  });

  test(
    'a session stored before worker standing reads as no standing',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'session':
            '{"access_token":"a","refresh_token":"r","role":"FIELD_WORKER",'
            '"consent_required":false}',
      });

      final session = await SecureSessionStorage().readSession();

      expect(session?.workerStanding.status, isNull);
      expect(session?.workerStanding.blocksWork, isFalse);
    },
  );

  test('InMemorySessionStorage clears the session', () async {
    final storage = InMemorySessionStorage();
    await storage.saveSession(_session);

    await storage.clear();

    expect(await storage.readSession(), isNull);
  });
}
