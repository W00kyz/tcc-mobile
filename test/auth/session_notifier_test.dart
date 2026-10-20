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
  });

  final String? refreshResult;
  final bool refuse;
  final WorkerStanding standing;
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
    return RefreshedAccess(accessToken: result, workerStanding: standing);
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

/// The backend refusing a worker who is no longer (or not yet) approved.
class _WorkerNotApprovedAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '{"detail":{"code":"WORKER_NOT_APPROVED","detail":"not approved"}}',
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
