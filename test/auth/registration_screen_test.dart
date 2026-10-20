import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/auth/registration_screen.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/privacy/consent_providers.dart';
import 'package:route_monitor/privacy/consent_repository.dart';

/// Records each sign-up; the failures given are thrown by the next calls, in
/// order.
class _RegisteringAuthRepository implements AuthRepository {
  _RegisteringAuthRepository({List<Exception>? failures})
    : _failures = failures ?? [];

  final List<Exception> _failures;
  final List<Map<String, Object>> registrations = [];
  int companyFetches = 0;

  /// Both companies on the first fetch; "Verde Vivo" is gone afterwards, as
  /// if the manager removed it while the worker filled the form.
  @override
  Future<List<CompanyOption>> publicCompanies() async {
    companyFetches++;
    return [
      const CompanyOption(id: 'c-1', name: 'Limpa Tudo'),
      if (companyFetches == 1)
        const CompanyOption(id: 'c-2', name: 'Verde Vivo'),
    ];
  }

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String companyId,
    required int noticeVersion,
  }) async {
    registrations.add({
      'name': name,
      'email': email,
      'password': password,
      'companyId': companyId,
      'noticeVersion': noticeVersion,
    });
    if (_failures.isNotEmpty) throw _failures.removeAt(0);
  }

  @override
  Future<Session> login({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<RefreshedAccess> refreshAccessToken(String refreshToken) =>
      throw UnimplementedError();

  @override
  Future<void> requestPasswordReset(String email) async {}
}

/// Serves the notices in order, one per fetch (the last one repeats), the way
/// a manager publishing a new version mid-sign-up would.
class _NoticeServingConsentRepository implements ConsentRepository {
  _NoticeServingConsentRepository(this._notices);

  final List<PrivacyNotice> _notices;
  int fetches = 0;

  @override
  Future<PrivacyNotice> currentNotice() async {
    final notice = _notices[fetches.clamp(0, _notices.length - 1)];
    fetches++;
    return notice;
  }

  @override
  Future<ConsentStatus> status() => throw UnimplementedError();

  @override
  Future<void> accept() => throw UnimplementedError();
}

const _noticeV7 = PrivacyNotice(
  version: 7,
  title: 'Aviso de Privacidade',
  body: 'texto-do-aviso-v7',
);
const _noticeV8 = PrivacyNotice(
  version: 8,
  title: 'Aviso de Privacidade',
  body: 'texto-do-aviso-v8',
);

Future<void> _pump(
  WidgetTester tester, {
  required _RegisteringAuthRepository auth,
  _NoticeServingConsentRepository? consent,
}) async {
  final router = GoRouter(
    initialLocation: '/cadastro',
    routes: [
      GoRoute(
        path: '/cadastro',
        builder: (_, _) => const RegistrationScreen(),
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
        authRepositoryProvider.overrideWithValue(auth),
        consentRepositoryProvider.overrideWithValue(
          consent ?? _NoticeServingConsentRepository([_noticeV7]),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fill(
  WidgetTester tester, {
  String email = 'ana@empresa.com',
  String password = 'senha-longa-1',
}) async {
  await tester.enterText(
    find.byKey(const Key('registration-name')),
    'Ana Souza',
  );
  await tester.enterText(find.byKey(const Key('registration-email')), email);
  await tester.enterText(
    find.byKey(const Key('registration-password')),
    password,
  );
  await tester.ensureVisible(find.byKey(const Key('registration-company')));
  await tester.tap(find.byKey(const Key('registration-company')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Verde Vivo').last);
  await tester.pumpAndSettle();
}

Future<void> _acceptAndSubmit(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('registration-accept')));
  await tester.tap(find.byKey(const Key('registration-accept')));
  await tester.pump();
  await tester.ensureVisible(find.byKey(const Key('registration-submit')));
  await tester.tap(find.byKey(const Key('registration-submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the current notice and the companies to choose from', (
    tester,
  ) async {
    await _pump(tester, auth: _RegisteringAuthRepository());

    expect(find.text('texto-do-aviso-v7'), findsOneWidget);
    await tester.tap(find.byKey(const Key('registration-company')));
    await tester.pumpAndSettle();
    expect(find.text('Limpa Tudo'), findsWidgets);
    expect(find.text('Verde Vivo'), findsWidgets);
  });

  testWidgets('cannot be sent before "Li e aceito" is ticked', (tester) async {
    await _pump(tester, auth: _RegisteringAuthRepository());
    await _fill(tester);

    final submit = tester.widget<FilledButton>(
      find.byKey(const Key('registration-submit')),
    );

    expect(submit.onPressed, isNull);
  });

  testWidgets('sends the sign-up with the notice version it showed', (
    tester,
  ) async {
    final auth = _RegisteringAuthRepository();
    await _pump(tester, auth: auth);

    await _fill(tester);
    await _acceptAndSubmit(tester);

    expect(auth.registrations, [
      {
        'name': 'Ana Souza',
        'email': 'ana@empresa.com',
        'password': 'senha-longa-1',
        'companyId': 'c-2',
        'noticeVersion': 7,
      },
    ]);
    expect(find.text(AppStrings.registrationSent), findsOneWidget);
    expect(find.text('entrar-screen'), findsOneWidget);
  });

  testWidgets('refuses a password shorter than 8 characters', (tester) async {
    final auth = _RegisteringAuthRepository();
    await _pump(tester, auth: auth);

    await _fill(tester, password: 'curta');
    await _acceptAndSubmit(tester);

    expect(find.text(AppStrings.registrationPasswordTooShort), findsOneWidget);
    expect(auth.registrations, isEmpty);
  });

  testWidgets('says so when the e-mail is already registered', (tester) async {
    await _pump(
      tester,
      auth: _RegisteringAuthRepository(
        failures: [const EmailTakenException()],
      ),
    );

    await _fill(tester);
    await _acceptAndSubmit(tester);

    expect(find.text(AppStrings.registrationEmailTaken), findsOneWidget);
    expect(find.text('entrar-screen'), findsNothing);
  });

  testWidgets('an outdated notice reloads and must be accepted again', (
    tester,
  ) async {
    final auth = _RegisteringAuthRepository(
      failures: [const NoticeOutdatedException()],
    );
    final consent = _NoticeServingConsentRepository([_noticeV7, _noticeV8]);
    await _pump(tester, auth: auth, consent: consent);

    await _fill(tester);
    await _acceptAndSubmit(tester);

    expect(find.text('texto-do-aviso-v8'), findsOneWidget);
    expect(find.text(AppStrings.registrationNoticeOutdated), findsOneWidget);
    final submit = tester.widget<FilledButton>(
      find.byKey(const Key('registration-submit')),
    );
    expect(submit.onPressed, isNull, reason: 'the new notice is not accepted');

    await _acceptAndSubmit(tester);

    expect(auth.registrations.map((r) => r['noticeVersion']), [7, 8]);
    expect(find.text('entrar-screen'), findsOneWidget);
  });

  testWidgets('refuses an e-mail without a domain suffix', (tester) async {
    final auth = _RegisteringAuthRepository();
    await _pump(tester, auth: auth);

    await _fill(tester, email: 'ana@gmail');
    await _acceptAndSubmit(tester);

    expect(find.text(AppStrings.registrationEmailInvalid), findsOneWidget);
    expect(auth.registrations, isEmpty);
  });

  testWidgets('refuses a password over 128 characters', (tester) async {
    final auth = _RegisteringAuthRepository();
    await _pump(tester, auth: auth);

    await _fill(tester, password: 'a' * 129);
    await _acceptAndSubmit(tester);

    expect(find.text(AppStrings.registrationPasswordTooLong), findsOneWidget);
    expect(auth.registrations, isEmpty);
  });

  testWidgets('counts the password in code points, as the backend does', (
    tester,
  ) async {
    // 100 emoji: 100 code points (accepted by the backend) but 200 UTF-16
    // units, which a `String.length` check would wrongly refuse.
    final auth = _RegisteringAuthRepository();
    await _pump(tester, auth: auth);

    await _fill(tester, password: '🔒' * 100);
    await _acceptAndSubmit(tester);

    expect(auth.registrations, hasLength(1));
  });

  testWidgets('data the server refuses asks the worker to check it', (
    tester,
  ) async {
    await _pump(
      tester,
      auth: _RegisteringAuthRepository(
        failures: [const InvalidRegistrationException()],
      ),
    );

    await _fill(tester);
    await _acceptAndSubmit(tester);

    expect(find.text(AppStrings.registrationInvalidData), findsOneWidget);
    expect(find.text(AppStrings.registrationError), findsNothing);
  });

  testWidgets('a company removed meanwhile reloads the list to choose again', (
    tester,
  ) async {
    final auth = _RegisteringAuthRepository(
      failures: [const UnknownCompanyException()],
    );
    await _pump(tester, auth: auth);

    await _fill(tester);
    await _acceptAndSubmit(tester);

    expect(auth.companyFetches, 2);
    expect(find.text(AppStrings.registrationCompanyGone), findsOneWidget);
    expect(find.text('Verde Vivo'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('registration-submit')));
    await tester.tap(find.byKey(const Key('registration-submit')));
    await tester.pumpAndSettle();

    expect(
      find.text(AppStrings.registrationCompanyRequired),
      findsOneWidget,
      reason: 'the removed company must not stay selected',
    );
    expect(auth.registrations, hasLength(1));
  });

  testWidgets('a server failure is not blamed on the connection', (
    tester,
  ) async {
    final request = RequestOptions(path: '/auth/register');
    await _pump(
      tester,
      auth: _RegisteringAuthRepository(
        failures: [
          DioException(
            requestOptions: request,
            response: Response<void>(requestOptions: request, statusCode: 500),
          ),
        ],
      ),
    );

    await _fill(tester);
    await _acceptAndSubmit(tester);

    expect(find.text(AppStrings.registrationServerError), findsOneWidget);
    expect(find.text(AppStrings.registrationError), findsNothing);
  });

  testWidgets('an unreachable server is reported', (tester) async {
    await _pump(
      tester,
      auth: _RegisteringAuthRepository(
        failures: [
          DioException(requestOptions: RequestOptions(path: '/auth/register')),
        ],
      ),
    );

    await _fill(tester);
    await _acceptAndSubmit(tester);

    expect(find.text(AppStrings.registrationError), findsOneWidget);
  });
}
