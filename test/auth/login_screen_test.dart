// test/auth/login_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/auth/login_screen.dart';
import 'package:route_monitor/l10n/strings.dart';

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.shouldFail = false});
  final bool shouldFail;

  @override
  Future<Session> login({
    required String email,
    required String password,
  }) async {
    if (shouldFail) throw const InvalidCredentialsException();
    // Realistic header.payload.signature shape — Session.role is supplied
    // directly here, so the token itself is never decoded in this test.
    return const Session(
      accessToken: 'a.eyJyb2xlIjoiRklFTERfV09SS0VSIn0.c',
      refreshToken: 'r',
      role: 'FIELD_WORKER',
    );
  }

  @override
  Future<RefreshedAccess> refreshAccessToken(String refreshToken) async =>
      const RefreshedAccess(accessToken: 'fresh');

  @override
  Future<List<CompanyOption>> publicCompanies() async => const [];

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String companyId,
    required int noticeVersion,
  }) async {}

  @override
  Future<void> requestPasswordReset(String email) async {
    resetRequestedFor = email;
  }

  String? resetRequestedFor;
}

void main() {
  forgotPasswordTests();

  testWidgets('"Criar conta" opens the sign-up screen', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const LoginScreen()),
        GoRoute(
          path: '/cadastro',
          builder: (_, _) => const Scaffold(body: Text('cadastro-screen')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.tap(find.text(AppStrings.loginCreateAccount));
    await tester.pumpAndSettle();

    expect(find.text('cadastro-screen'), findsOneWidget);
  });

  testWidgets('shows an error message on invalid credentials', (tester) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const LoginScreen())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(shouldFail: true),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('email-field')),
      'joao@empresa.com',
    );
    await tester.enterText(
      find.byKey(const Key('password-field')),
      'senha-errada',
    );
    await tester.tap(find.byKey(const Key('login-button')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.loginInvalidCredentials), findsOneWidget);
  });
}

void forgotPasswordTests() {
  testWidgets('"Esqueci minha senha" requests a reset link (RF03)', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const LoginScreen())],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('email-field')),
      'joao@empresa.com',
    );
    await tester.tap(find.byKey(const Key('forgot-password-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forgot-password-send')));
    await tester.pumpAndSettle();

    expect(repository.resetRequestedFor, 'joao@empresa.com');
    expect(find.text(AppStrings.forgotPasswordSent), findsOneWidget);
  });
}
