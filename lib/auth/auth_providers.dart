import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/api/api_client.dart';
import 'package:route_monitor/api/env.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/auth/session_storage.dart';

final sessionStorageProvider = Provider<SessionStorage>(
  (ref) => SecureSessionStorage(),
);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final dio = buildDio(baseUrl: apiBaseUrlFromEnvironment());
  return DioAuthRepository(dio);
});

class SessionNotifier extends Notifier<Session?> {
  @override
  Session? build() => null;

  Future<void> login({required String email, required String password}) async {
    final repository = ref.read(authRepositoryProvider);
    final storage = ref.read(sessionStorageProvider);
    final session = await repository.login(email: email, password: password);
    await storage.saveAccessToken(session.accessToken);
    state = session;
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, Session?>(
  SessionNotifier.new,
);
