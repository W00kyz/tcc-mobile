import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/appeals/appeal_providers.dart';
import 'package:route_monitor/appeals/appeals_screen.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/gamification/profile_screen.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/main.dart';

import 'appeals/fake_appeal_api.dart';
import 'support/fake_day_log_store.dart';

Session _worker(WorkerStanding standing, {bool consentRequired = false}) =>
    Session(
      accessToken: 'a',
      refreshToken: 'r',
      role: 'FIELD_WORKER',
      consentRequired: consentRequired,
      workerStanding: standing,
    );

const _pending = WorkerStanding(
  status: WorkerStatus.pendingApproval,
  active: true,
);
const _rejected = WorkerStanding(status: WorkerStatus.rejected, active: true);
const _approved = WorkerStanding(status: WorkerStatus.approved, active: true);
const _deactivated = WorkerStanding(
  status: WorkerStatus.approved,
  active: false,
);

void main() {
  group('signed out', () {
    test('only the login and sign-up screens are reachable', () {
      expect(appRedirect(null, '/entrar'), isNull);
      expect(appRedirect(null, '/cadastro'), isNull);
      expect(appRedirect(null, '/rota'), '/entrar');
      expect(appRedirect(null, '/aguardando-aprovacao'), '/entrar');
    });
  });

  group('approval gate', () {
    test('a pending worker waits for approval wherever they go', () {
      expect(appRedirect(_worker(_pending), '/rota'), '/aguardando-aprovacao');
      expect(
        appRedirect(_worker(_pending), '/meus-dados'),
        '/aguardando-aprovacao',
      );
      expect(appRedirect(_worker(_pending), '/aguardando-aprovacao'), isNull);
    });

    test('a rejected or deactivated worker lands on the same screen', () {
      expect(appRedirect(_worker(_rejected), '/rota'), '/aguardando-aprovacao');
      expect(
        appRedirect(_worker(_deactivated), '/rota'),
        '/aguardando-aprovacao',
      );
    });

    test('the gate comes before the consent screen', () {
      expect(
        appRedirect(_worker(_pending, consentRequired: true), '/rota'),
        '/aguardando-aprovacao',
      );
    });

    test('an approved, active worker moves on to the route', () {
      expect(appRedirect(_worker(_approved), '/aguardando-aprovacao'), '/rota');
      expect(appRedirect(_worker(_approved), '/cadastro'), '/rota');
      expect(appRedirect(_worker(_approved), '/rota'), isNull);
      expect(
        appRedirect(_worker(_approved, consentRequired: true), '/rota'),
        '/consentimento',
      );
    });

    test('a session without a standing is not held back', () {
      // Stored before the backend sent a status; a 403 refreshes it.
      expect(appRedirect(_worker(const WorkerStanding()), '/rota'), isNull);
    });
  });

  testWidgets('the app router shows the waiting screen to a pending worker', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWithBuild((ref, notifier) => _worker(_pending)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: container.read(routerProvider)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.approvalPendingMessage), findsOneWidget);
  });

  testWidgets('"/recursos" opens the appeals of an approved worker', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWithBuild(
          (ref, notifier) => _worker(_approved),
        ),
        appealApiProvider.overrideWithValue(RecordingAppealApi()),
      ],
    );
    addTearDown(container.dispose);
    // Straight there: the route screen on the way would reach the network.
    final router = container.read(routerProvider)..go('/recursos');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppealsScreen), findsOneWidget);
    expect(
      appRedirect(_worker(_pending), '/recursos'),
      '/aguardando-aprovacao',
    );
  });

  testWidgets('"/perfil" opens the profile of an approved worker', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWithBuild(
          (ref, notifier) => _worker(_approved),
        ),
        dayLogStoreProvider.overrideWithValue(RecordingDayLogStore()),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider)..go('/perfil');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(appRedirect(_worker(_pending), '/perfil'), '/aguardando-aprovacao');
  });
}
