import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/auth/session_storage.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/privacy/consent_providers.dart';
import 'package:route_monitor/privacy/consent_repository.dart';
import 'package:route_monitor/privacy/consent_screen.dart';

class _FakeConsentRepository implements ConsentRepository {
  bool accepted = false;

  @override
  Future<ConsentStatus> status() async =>
      const ConsentStatus(consentRequired: true);

  @override
  Future<void> accept() async => accepted = true;

  @override
  Future<PrivacyNotice> currentNotice() => throw UnimplementedError();
}

GoRouter _router() => GoRouter(
  initialLocation: '/consentimento',
  routes: [
    GoRoute(
      path: '/consentimento',
      builder: (_, _) => const ConsentScreen(),
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

Future<void> _pump(
  WidgetTester tester, {
  required _FakeConsentRepository repository,
  required SessionStorage storage,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        consentRepositoryProvider.overrideWithValue(repository),
        sessionStorageProvider.overrideWithValue(storage),
        consentStatusProvider.overrideWith(
          (ref) async => const ConsentStatus(
            consentRequired: true,
            noticeTitle: 'Antes de continuar',
            noticeBody: 'corpo-do-aviso-visivel',
          ),
        ),
        sessionProvider.overrideWithBuild(
          (ref, notifier) => const Session(
            accessToken: 'a-token',
            refreshToken: 'r-token',
            role: 'FIELD_WORKER',
            consentRequired: true,
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the notice body', (tester) async {
    await _pump(
      tester,
      repository: _FakeConsentRepository(),
      storage: InMemorySessionStorage(),
    );

    expect(find.text('corpo-do-aviso-visivel'), findsOneWidget);
  });

  testWidgets('accepting calls accept() and navigates to /rota', (
    tester,
  ) async {
    final repository = _FakeConsentRepository();
    await _pump(
      tester,
      repository: repository,
      storage: InMemorySessionStorage(),
    );

    await tester.tap(find.text(AppStrings.consentAcceptButton));
    await tester.pumpAndSettle();

    expect(repository.accepted, isTrue);
    expect(find.text('rota-screen'), findsOneWidget);
  });

  testWidgets('tapping "Sair" clears the session and returns to /entrar', (
    tester,
  ) async {
    final storage = InMemorySessionStorage();
    await storage.saveSession(
      const Session(
        accessToken: 'a-token',
        refreshToken: 'r',
        role: 'FIELD_WORKER',
      ),
    );
    await _pump(
      tester,
      repository: _FakeConsentRepository(),
      storage: storage,
    );

    await tester.tap(find.text(AppStrings.consentExitButton));
    await tester.pumpAndSettle();

    expect(await storage.readSession(), isNull);
    expect(find.text('entrar-screen'), findsOneWidget);
  });
}
