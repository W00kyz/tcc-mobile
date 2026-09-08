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
}

void main() {
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
