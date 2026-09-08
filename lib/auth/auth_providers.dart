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

  /// Drops the stored session on "Sair" — clears the secure storage so no
  /// access token survives the sign-out, then unauthenticates the app.
  Future<void> logout() async {
    await ref.read(sessionStorageProvider).clear();
    state = null;
  }

  /// Called once the user accepts the consent notice: the backend has recorded
  /// the acceptance, so the router guard should let this session through.
  void clearConsentRequirement() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(consentRequired: false);
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, Session?>(
  SessionNotifier.new,
);
