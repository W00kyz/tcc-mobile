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
  WorkerStanding? _standingAfterRefusal;

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
  /// the last one also signs the user out). Also brings the worker standing
  /// up to date, so the router re-evaluates the approval gate ("Atualizar").
  /// Concurrent callers share one request. Every Dio built by
  /// [buildSessionDio] calls this on a 401.
  Future<String?> refreshAccessToken() {
    return _inflightRefresh ??= _refresh().whenComplete(
      () => _inflightRefresh = null,
    );
  }

  Future<String?> _refresh() async {
    final current = state;
    if (current == null) return null;
    try {
      final refreshed = await ref
          .read(authRepositoryProvider)
          .refreshAccessToken(current.refreshToken);
      await _store(
        current.copyWith(
          accessToken: refreshed.accessToken,
          workerStanding: refreshed.workerStanding,
        ),
      );
      return refreshed.accessToken;
    } on SessionExpiredException {
      await logout();
      return null;
    } on DioException {
      // Offline: keep the session, the outbox waits for the next sync.
      return null;
    }
  }

  /// A worker-only call was refused with 403 `WORKER_NOT_APPROVED`: refresh
  /// so the standing it brings back sends the worker to the waiting screen.
  ///
  /// WARNING: skipped when the session already holds the worker back, or when
  /// it still carries the standing a previous 403 refresh brought (the server
  /// refuses a worker it reports as able to work — e.g. a worker account
  /// without a worker profile). The route watchers re-fetch on every session
  /// change, so refreshing again would mean 403, refresh, re-fetch, forever.
  Future<void> refreshWorkerStanding() async {
    final standing = state?.workerStanding;
    if (standing == null ||
        standing.blocksWork ||
        identical(standing, _standingAfterRefusal)) {
      return;
    }
    await refreshAccessToken();
    _standingAfterRefusal = state?.workerStanding;
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
/// instead of failing every request — and, worse, blocking the outbox. A 403
/// `WORKER_NOT_APPROVED` refreshes the worker standing, which sends the worker
/// to the waiting screen.
Dio buildSessionDio(Ref ref) {
  final session = ref.watch(sessionProvider);
  final notifier = ref.read(sessionProvider.notifier);
  return buildDio(
    baseUrl: apiBaseUrlFromEnvironment(),
    accessToken: session?.accessToken,
    onUnauthorized: notifier.refreshAccessToken,
    onWorkerNotApproved: notifier.refreshWorkerStanding,
  );
}

/// [buildSessionDio] for a client held by a long-lived loop (the position
/// reporter, spec 2026-10-20-alocacao-automatica §7.3): rebuilt only when the
/// signed-in user changes, and the bearer token is read from the session at
/// each request. With [buildSessionDio], every token refresh (15 minutes)
/// rebuilt the client and everything holding it — stopping the background
/// stream with the screen locked, where no widget build starts it again.
///
///     final dio = buildUserScopedSessionDio(ref, baseUrl: url);
Dio buildUserScopedSessionDio(Ref ref, {required String baseUrl}) {
  ref.watch(sessionProvider.select((session) => session?.userId));
  final notifier = ref.read(sessionProvider.notifier);
  return buildDio(
    baseUrl: baseUrl,
    readAccessToken: () => ref.read(sessionProvider)?.accessToken,
    onUnauthorized: notifier.refreshAccessToken,
    onWorkerNotApproved: notifier.refreshWorkerStanding,
  );
}

/// The companies offered on the sign-up screen.
final FutureProvider<List<CompanyOption>> publicCompaniesProvider =
    FutureProvider.autoDispose<List<CompanyOption>>(
      (ref) => ref.watch(authRepositoryProvider).publicCompanies(),
    );
