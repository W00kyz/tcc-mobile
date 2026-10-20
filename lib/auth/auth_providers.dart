import 'dart:async';

import 'package:dio/dio.dart';
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
  Future<String?>? _inflightRefresh;

  @override
  Session? build() {
    // Starts signed out and restores the persisted session right after: the
    // router's `refreshListenable` moves past /entrar once it lands.
    unawaited(_restore());
    return null;
  }

  Future<void> _restore() async {
    try {
      final stored = await ref.read(sessionStorageProvider).readSession();
      // A login that finished first wins over the stored session.
      if (stored != null && state == null) state = stored;
      // Deliberately broad: a keychain failure (or a test without the
      // platform plugin) must leave the app on the login screen, not crash it.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {}
  }

  Future<void> login({required String email, required String password}) async {
    final repository = ref.read(authRepositoryProvider);
    final session = await repository.login(email: email, password: password);
    await _store(session);
  }

  /// A fresh access token for the current session, or null when there is
  /// none to be had (signed out, offline, or the refresh token was refused —
  /// the last one also signs the user out). Concurrent callers share one
  /// request. Every Dio built by [buildDio] calls this on a 401.
  Future<String?> refreshAccessToken() {
    return _inflightRefresh ??= _refresh().whenComplete(
      () => _inflightRefresh = null,
    );
  }

  Future<String?> _refresh() async {
    final current = state;
    if (current == null) return null;
    try {
      final accessToken = await ref
          .read(authRepositoryProvider)
          .refreshAccessToken(current.refreshToken);
      await _store(current.copyWith(accessToken: accessToken));
      return accessToken;
    } on SessionExpiredException {
      await logout();
      return null;
    } on DioException {
      // Offline: keep the session, the outbox waits for the next sync.
      return null;
    }
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
    final next = current.copyWith(consentRequired: false);
    state = next;
    unawaited(_persist(next));
  }

  Future<void> _store(Session session) async {
    await _persist(session);
    state = session;
  }

  Future<void> _persist(Session session) async {
    try {
      await ref.read(sessionStorageProvider).saveSession(session);
      // Same as `_restore`: losing persistence only costs a re-login later.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {}
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, Session?>(
  SessionNotifier.new,
);

/// Builds the API client for the signed-in worker: bearer token plus the
/// refresh-on-401 hook. Every feature provider goes through here so a token
/// that expires mid-route (15 minutes, JWT_ACCESS_TOKEN_MINUTES) is renewed
/// instead of failing every request — and, worse, blocking the outbox.
Dio buildSessionDio(Ref ref) {
  final session = ref.watch(sessionProvider);
  return buildDio(
    baseUrl: apiBaseUrlFromEnvironment(),
    accessToken: session?.accessToken,
    onUnauthorized: ref.read(sessionProvider.notifier).refreshAccessToken,
  );
}
