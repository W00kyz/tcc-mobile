import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  _ScriptedAuthRepository({this.refreshResult, this.refuse = false});

  final String? refreshResult;
  final bool refuse;
  int refreshCalls = 0;

  @override
  Future<Session> login({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<String> refreshAccessToken(String refreshToken) async {
    refreshCalls++;
    if (refuse) throw const SessionExpiredException();
    final result = refreshResult;
    if (result == null) {
      throw DioException(requestOptions: RequestOptions(path: '/auth/refresh'));
    }
    return result;
  }

  @override
  Future<void> requestPasswordReset(String email) async {}
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

void main() {
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
