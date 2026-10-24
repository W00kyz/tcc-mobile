import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/api/api_client.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/auth/session_storage.dart';

const _stored = Session(
  accessToken: 'old-access',
  refreshToken: 'refresh',
  role: 'FIELD_WORKER',
);

/// Refresh behaviour is scripted per test: a token, a refusal, or "offline".
class _ScriptedAuthRepository implements AuthRepository {
  _ScriptedAuthRepository({
    this.refreshResult,
    this.refuse = false,
    this.standing = const WorkerStanding(),
    this.consentRequired,
  });

  final String? refreshResult;
  final bool refuse;
  final WorkerStanding standing;
  final bool? consentRequired;
  int refreshCalls = 0;

  @override
  Future<Session> login({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<RefreshedAccess> refreshAccessToken(String refreshToken) async {
    refreshCalls++;
    if (refuse) throw const SessionExpiredException();
    final result = refreshResult;
    if (result == null) {
      throw DioException(requestOptions: RequestOptions(path: '/auth/refresh'));
    }
    return RefreshedAccess(
      accessToken: result,
      workerStanding: standing,
      consentRequired: consentRequired,
    );
  }

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<List<CompanyOption>> publicCompanies() => throw UnimplementedError();

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String companyId,
    required int noticeVersion,
  }) => throw UnimplementedError();
}

Future<ProviderContainer> _container(
  SessionStorage storage,
  AuthRepository repository,
) async {
  final container = ProviderContainer(
    overrides: [
      sessionStorageProvider.overrideWithValue(storage),
      authRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  container.read(sessionProvider);
  // Let the async restore in build() land.
  await Future<void>.delayed(Duration.zero);
  return container;
}

/// The backend refusing a worker who is no longer (or not yet) approved —
/// or, with [code], for another reason.
class _WorkerNotApprovedAdapter implements HttpClientAdapter {
  _WorkerNotApprovedAdapter([this.code = 'WORKER_NOT_APPROVED']);

  final String code;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '{"detail":{"code":"$code","detail":"refused"}}',
    403,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  group('403 WORKER_NOT_APPROVED', workerNotApprovedTests);
  group('403 CONSENT_REQUIRED', consentRequiredTests);

  test('restores the persisted session on start (offline restart)', () async {
    final storage = InMemorySessionStorage();
    await storage.saveSession(_stored);

    final container = await _container(storage, _ScriptedAuthRepository());

    expect(container.read(sessionProvider)?.accessToken, 'old-access');
  });

  test('a refresh stores and persists the new access token', () async {
    final storage = InMemorySessionStorage();
    await storage.saveSession(_stored);
    final container = await _container(
      storage,
      _ScriptedAuthRepository(refreshResult: 'new-access'),
    );

    final token = await container
        .read(sessionProvider.notifier)
        .refreshAccessToken();

    expect(token, 'new-access');
    expect(container.read(sessionProvider)?.accessToken, 'new-access');
    expect((await storage.readSession())?.accessToken, 'new-access');
  });

  test('a refresh stores the worker standing it brings back', () async {
    // "Atualizar" on the waiting screen: the manager approved meanwhile.
    final storage = InMemorySessionStorage();
    await storage.saveSession(
      const Session(
        accessToken: 'old-access',
        refreshToken: 'refresh',
        role: 'FIELD_WORKER',
        workerStanding: WorkerStanding(
          status: WorkerStatus.pendingApproval,
          active: true,
        ),
      ),
    );
    final container = await _container(
      storage,
      _ScriptedAuthRepository(
        refreshResult: 'new-access',
        standing: const WorkerStanding(
          status: WorkerStatus.approved,
          active: true,
        ),
      ),
    );

    await container.read(sessionProvider.notifier).refreshAccessToken();

    final session = container.read(sessionProvider);
    expect(session?.workerStanding.status, WorkerStatus.approved);
    expect(session?.workerStanding.blocksWork, isFalse);
    expect(
      (await storage.readSession())?.workerStanding.status,
      WorkerStatus.approved,
    );
  });

  test('a refresh stores whether a new privacy notice is owed', () async {
    // Logged in before the notice changed: the next refresh says so and the
    // router's consent gate takes over.
    final storage = InMemorySessionStorage();
    await storage.saveSession(_stored);
    final container = await _container(
      storage,
      _ScriptedAuthRepository(
        refreshResult: 'new-access',
        consentRequired: true,
      ),
    );

    await container.read(sessionProvider.notifier).refreshAccessToken();

    expect(container.read(sessionProvider)?.consentRequired, isTrue);
    expect((await storage.readSession())?.consentRequired, isTrue);
  });

  test(
    'a refresh from a server that says nothing keeps the consent flag',
    () async {
      final storage = InMemorySessionStorage();
      await storage.saveSession(
        const Session(
          accessToken: 'old-access',
          refreshToken: 'refresh',
          role: 'FIELD_WORKER',
          consentRequired: true,
        ),
      );
      final container = await _container(
        storage,
        _ScriptedAuthRepository(refreshResult: 'new-access'),
      );

      await container.read(sessionProvider.notifier).refreshAccessToken();

      expect(container.read(sessionProvider)?.consentRequired, isTrue);
    },
  );

  test('concurrent refreshes share one request', () async {
    final storage = InMemorySessionStorage();
    await storage.saveSession(_stored);
    final repository = _ScriptedAuthRepository(refreshResult: 'new-access');
    final container = await _container(storage, repository);
    final notifier = container.read(sessionProvider.notifier);

    await Future.wait([
      notifier.refreshAccessToken(),
      notifier.refreshAccessToken(),
    ]);

    expect(repository.refreshCalls, 1);
  });

  test('a refused refresh token signs the user out', () async {
    final storage = InMemorySessionStorage();
    await storage.saveSession(_stored);
    final container = await _container(
      storage,
      _ScriptedAuthRepository(refuse: true),
    );

    final token = await container
        .read(sessionProvider.notifier)
        .refreshAccessToken();

    expect(token, isNull);
    expect(container.read(sessionProvider), isNull);
    expect(await storage.readSession(), isNull);
  });

  test('an offline refresh keeps the session for later', () async {
    final storage = InMemorySessionStorage();
    await storage.saveSession(_stored);
    final container = await _container(storage, _ScriptedAuthRepository());

    final token = await container
        .read(sessionProvider.notifier)
        .refreshAccessToken();

    expect(token, isNull);
    expect(container.read(sessionProvider)?.accessToken, 'old-access');
  });
}

/// A session standing as [standing], whose refreshes answer [afterRefresh],
/// and a Dio wired to it the way buildSessionDio wires it (that one needs
/// API_BASE_URL) that the backend always refuses as not approved.
Future<(ProviderContainer, _ScriptedAuthRepository, Dio)> _refusedWorker({
  required WorkerStanding standing,
  required WorkerStanding afterRefresh,
}) async {
  final storage = InMemorySessionStorage();
  await storage.saveSession(
    Session(
      accessToken: 'old-access',
      refreshToken: 'refresh',
      role: 'FIELD_WORKER',
      workerStanding: standing,
    ),
  );
  final repository = _ScriptedAuthRepository(
    refreshResult: 'new-access',
    standing: afterRefresh,
  );
  final container = await _container(storage, repository);
  final dio = buildDio(
    baseUrl: 'http://test',
    onWorkerNotApproved: container
        .read(sessionProvider.notifier)
        .refreshWorkerStanding,
  )..httpClientAdapter = _WorkerNotApprovedAdapter();
  return (container, repository, dio);
}

const _approved = WorkerStanding(status: WorkerStatus.approved, active: true);
const _deactivated = WorkerStanding(
  status: WorkerStatus.approved,
  active: false,
);

void workerNotApprovedTests() {
  test('refreshes the standing so the router can hold the worker', () async {
    // Deactivated mid-shift: the next call is refused and the router must
    // learn why, so it can send the worker to the waiting screen.
    final (container, _, dio) = await _refusedWorker(
      standing: _approved,
      afterRefresh: _deactivated,
    );

    await expectLater(
      dio.get<void>('/routes/me'),
      throwsA(isA<DioException>()),
    );

    expect(container.read(sessionProvider)?.workerStanding.blocksWork, isTrue);
  });

  test('a session already held back is not refreshed again', () async {
    // The route watchers re-fetch on every session change; refreshing here
    // would change the session, re-fetch, get 403 again — forever.
    final (_, repository, dio) = await _refusedWorker(
      standing: _deactivated,
      afterRefresh: _deactivated,
    );

    await expectLater(
      dio.get<void>('/routes/me'),
      throwsA(isA<DioException>()),
    );

    expect(repository.refreshCalls, 0);
  });

  test(
    'refreshes once when the server still says the worker may work',
    () async {
      // A worker account without a worker profile: refresh reports no standing
      // while every worker endpoint keeps refusing it.
      final (_, repository, dio) = await _refusedWorker(
        standing: const WorkerStanding(),
        afterRefresh: const WorkerStanding(),
      );

      for (var call = 0; call < 3; call++) {
        await expectLater(
          dio.get<void>('/routes/me'),
          throwsA(isA<DioException>()),
        );
      }

      expect(repository.refreshCalls, 1);
    },
  );
}

void consentRequiredTests() {
  Future<(ProviderContainer, InMemorySessionStorage, Dio)> owingConsent({
    bool alreadyFlagged = false,
  }) async {
    final storage = InMemorySessionStorage();
    await storage.saveSession(
      Session(
        accessToken: 'old-access',
        refreshToken: 'refresh',
        role: 'FIELD_WORKER',
        consentRequired: alreadyFlagged,
      ),
    );
    final container = await _container(storage, _ScriptedAuthRepository());
    final dio = buildDio(
      baseUrl: 'http://test',
      onConsentRequired: container
          .read(sessionProvider.notifier)
          .requireConsent,
    )..httpClientAdapter = _WorkerNotApprovedAdapter('CONSENT_REQUIRED');
    return (container, storage, dio);
  }

  test('sends a logged-in worker to the consent gate', () async {
    // A new notice was published mid-session: "Iniciar rota" is refused and
    // the router must show the notice instead of a generic failure.
    final (container, storage, dio) = await owingConsent();

    await expectLater(
      dio.post<void>('/routes/start'),
      throwsA(isA<DioException>()),
    );

    expect(container.read(sessionProvider)?.consentRequired, isTrue);
    expect((await storage.readSession())?.consentRequired, isTrue);
  });

  test('a session already owing consent is left as it is', () async {
    // Watchers re-fetch on every session change: a new session object for
    // every 403 would mean 403, re-fetch, 403, forever.
    final (container, _, dio) = await owingConsent(alreadyFlagged: true);
    final before = container.read(sessionProvider);

    await expectLater(
      dio.post<void>('/routes/start'),
      throwsA(isA<DioException>()),
    );

    expect(identical(container.read(sessionProvider), before), isTrue);
  });
}
