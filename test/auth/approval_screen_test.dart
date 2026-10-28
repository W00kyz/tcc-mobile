import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:route_monitor/auth/approval_screen.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/auth/session_storage.dart';
import 'package:route_monitor/l10n/strings.dart';

/// Answers a refresh with [standing], or as if offline when it is null.
class _RefreshingAuthRepository implements AuthRepository {
  _RefreshingAuthRepository([this.standing]);

  final WorkerStanding? standing;
  int refreshCalls = 0;

  @override
  Future<RefreshedAccess> refreshAccessToken(String refreshToken) async {
    refreshCalls++;
    final next = standing;
    if (next == null) {
      throw DioException(requestOptions: RequestOptions(path: '/auth/refresh'));
    }
    return RefreshedAccess(accessToken: 'fresh', workerStanding: next);
  }

  @override
  Future<Session> login({required String email, required String password}) =>
      throw UnimplementedError();

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

const _pending = WorkerStanding(
  status: WorkerStatus.pendingApproval,
  active: true,
);

Future<void> _pump(
  WidgetTester tester, {
  required WorkerStanding standing,
  _RefreshingAuthRepository? auth,
  SessionStorage? storage,
}) async {
  final router = GoRouter(
    initialLocation: '/aguardando-aprovacao',
    routes: [
      GoRoute(
        path: '/aguardando-aprovacao',
        builder: (_, _) => const ApprovalScreen(),
      ),
      GoRoute(
        path: '/rota',
        builder: (_, _) => const Scaffold(body: Text('rota-screen')),
      ),
      GoRoute(
        path: '/entrar',
        builder: (_, _) => const Scaffold(body: Text('entrar-screen')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          auth ?? _RefreshingAuthRepository(),
        ),
        sessionStorageProvider.overrideWithValue(
          storage ?? InMemorySessionStorage(),
        ),
        sessionProvider.overrideWithBuild(
          (ref, notifier) => Session(
            accessToken: 'a',
            refreshToken: 'r',
            role: 'FIELD_WORKER',
            workerStanding: standing,
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a pending worker sees the wait message and can refresh', (
    tester,
  ) async {
    await _pump(tester, standing: _pending);

    expect(find.text(AppStrings.approvalPendingMessage), findsOneWidget);
    expect(find.text(AppStrings.approvalRefreshButton), findsOneWidget);
    expect(find.text(AppStrings.approvalExitButton), findsOneWidget);
  });

  testWidgets('a pending worker sees an empty card that says it is coming', (
    tester,
  ) async {
    await _pump(tester, standing: _pending);

    expect(
      find.text('Seu cartão chega quando a gestora aprovar o cadastro'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('approval-empty-card')), findsOneWidget);
  });

  testWidgets('a rejected worker sees no empty card', (tester) async {
    await _pump(
      tester,
      standing: const WorkerStanding(status: WorkerStatus.rejected),
    );

    expect(find.byKey(const Key('approval-empty-card')), findsNothing);
  });

  testWidgets('"Atualizar" moves on to the route once approved', (
    tester,
  ) async {
    final auth = _RefreshingAuthRepository(
      const WorkerStanding(status: WorkerStatus.approved, active: true),
    );
    await _pump(tester, standing: _pending, auth: auth);

    await tester.tap(find.text(AppStrings.approvalRefreshButton));
    await tester.pumpAndSettle();

    expect(auth.refreshCalls, 1);
    expect(find.text('rota-screen'), findsOneWidget);
  });

  testWidgets('"Atualizar" while still pending says so and stays', (
    tester,
  ) async {
    await _pump(
      tester,
      standing: _pending,
      auth: _RefreshingAuthRepository(_pending),
    );

    await tester.tap(find.text(AppStrings.approvalRefreshButton));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.approvalStillPending), findsOneWidget);
    expect(find.text(AppStrings.approvalPendingMessage), findsOneWidget);
  });

  testWidgets('"Atualizar" offline reports the missing connection', (
    tester,
  ) async {
    await _pump(tester, standing: _pending, auth: _RefreshingAuthRepository());

    await tester.tap(find.text(AppStrings.approvalRefreshButton));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.approvalNetworkError), findsOneWidget);
    expect(find.text(AppStrings.approvalPendingMessage), findsOneWidget);
  });

  testWidgets('"Atualizar" shows a rejection that happened meanwhile', (
    tester,
  ) async {
    await _pump(
      tester,
      standing: _pending,
      auth: _RefreshingAuthRepository(
        const WorkerStanding(
          status: WorkerStatus.rejected,
          rejectionReason: 'Documento ilegível',
          active: true,
        ),
      ),
    );

    await tester.tap(find.text(AppStrings.approvalRefreshButton));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.approvalRejectedMessage), findsOneWidget);
    expect(
      find.text(AppStrings.approvalRejectionReason('Documento ilegível')),
      findsOneWidget,
    );
  });

  testWidgets('a rejected worker sees the reason and can only leave', (
    tester,
  ) async {
    await _pump(
      tester,
      standing: const WorkerStanding(
        status: WorkerStatus.rejected,
        rejectionReason: 'Empresa não reconhecida',
        active: true,
      ),
    );

    expect(find.text(AppStrings.approvalRejectedMessage), findsOneWidget);
    expect(
      find.text(AppStrings.approvalRejectionReason('Empresa não reconhecida')),
      findsOneWidget,
    );
    expect(find.text(AppStrings.approvalRefreshButton), findsNothing);
    expect(find.text(AppStrings.approvalExitButton), findsOneWidget);
  });

  testWidgets('a rejection without a reason shows no reason line', (
    tester,
  ) async {
    await _pump(
      tester,
      standing: const WorkerStanding(
        status: WorkerStatus.rejected,
        active: true,
      ),
    );

    expect(find.text(AppStrings.approvalRejectedMessage), findsOneWidget);
    expect(find.textContaining('Motivo'), findsNothing);
  });

  testWidgets('a deactivated worker is told the manager switched them off', (
    tester,
  ) async {
    await _pump(
      tester,
      standing: const WorkerStanding(
        status: WorkerStatus.approved,
        active: false,
      ),
    );

    expect(find.text(AppStrings.approvalDeactivatedMessage), findsOneWidget);
    expect(find.text(AppStrings.approvalRefreshButton), findsNothing);
    expect(find.text(AppStrings.approvalExitButton), findsOneWidget);
  });

  testWidgets('"Sair" clears the session and returns to /entrar', (
    tester,
  ) async {
    final storage = InMemorySessionStorage();
    await storage.saveSession(
      const Session(
        accessToken: 'a',
        refreshToken: 'r',
        role: 'FIELD_WORKER',
        workerStanding: _pending,
      ),
    );
    await _pump(tester, standing: _pending, storage: storage);

    await tester.tap(find.text(AppStrings.approvalExitButton));
    await tester.pumpAndSettle();

    expect(await storage.readSession(), isNull);
    expect(find.text('entrar-screen'), findsOneWidget);
  });
}
