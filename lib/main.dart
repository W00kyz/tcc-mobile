import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:route_monitor/appeals/appeals_screen.dart';
import 'package:route_monitor/auth/approval_screen.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/auth/login_screen.dart';
import 'package:route_monitor/auth/registration_screen.dart';
import 'package:route_monitor/gamification/profile_screen.dart';
import 'package:route_monitor/monitoring/position_reporting_trigger.dart';
import 'package:route_monitor/privacy/consent_screen.dart';
import 'package:route_monitor/privacy/my_data_screen.dart';
import 'package:route_monitor/routing/map_home_screen.dart';
import 'package:route_monitor/sync/sync_triggers.dart';
import 'package:route_monitor/ui/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: RouteMonitorApp()));
}

const Set<String> _signedOutLocations = {'/entrar', '/cadastro'};
const Set<String> _gateLocations = {
  ..._signedOutLocations,
  '/consentimento',
  '/aguardando-aprovacao',
};

/// Where the router sends [session] asking for [location], or null to let it
/// through. Signed out: only login and sign-up. A worker who may not work
/// (pending, rejected, deactivated) waits on `/aguardando-aprovacao` — before
/// the consent gate, since they collect no data anyway. Past every gate, the
/// gate screens send on to the route.
///
///     redirect: (_, state) => appRedirect(session, state.matchedLocation),
String? appRedirect(Session? session, String location) {
  if (session == null) {
    return _signedOutLocations.contains(location) ? null : '/entrar';
  }
  if (session.workerStanding.blocksWork) {
    return location == '/aguardando-aprovacao' ? null : '/aguardando-aprovacao';
  }
  if (session.consentRequired) {
    return location == '/consentimento' ? null : '/consentimento';
  }
  return _gateLocations.contains(location) ? '/rota' : null;
}

/// The app router, built through Riverpod so `redirect` can read the session
/// (LGPD consent gate, RNF10; approval gate). A [ValueNotifier] bridged from
/// [sessionProvider] is the `refreshListenable`, so login, logout, consent
/// acceptance and a refreshed worker standing all re-run the guard.
final routerProvider = Provider<GoRouter>((ref) {
  final sessionChanges = ValueNotifier<Session?>(ref.read(sessionProvider));
  ref
    ..onDispose(sessionChanges.dispose)
    ..listen<Session?>(
      sessionProvider,
      (_, next) => sessionChanges.value = next,
    );

  return GoRouter(
    initialLocation: '/entrar',
    refreshListenable: sessionChanges,
    redirect: (context, state) =>
        appRedirect(ref.read(sessionProvider), state.matchedLocation),
    routes: [
      GoRoute(
        path: '/entrar',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/cadastro',
        builder: (context, state) => const RegistrationScreen(),
      ),
      GoRoute(
        path: '/aguardando-aprovacao',
        builder: (context, state) => const ApprovalScreen(),
      ),
      GoRoute(
        path: '/consentimento',
        builder: (context, state) => const ConsentScreen(),
      ),
      GoRoute(
        path: '/rota',
        builder: (context, state) => const MapHomeScreen(),
      ),
      GoRoute(
        path: '/meus-dados',
        builder: (context, state) => const MyDataScreen(),
      ),
      GoRoute(
        path: '/recursos',
        builder: (context, state) => const AppealsScreen(),
      ),
      GoRoute(
        path: '/perfil',
        builder: (context, state) => const ProfileScreen(),
      ),
    ],
  );
});

/// Root widget of the field application.
///
/// Kept deliberately thin: later stages wrap it with more providers rather
/// than growing this class.
///
///     runApp(const ProviderScope(child: RouteMonitorApp()));
class RouteMonitorApp extends ConsumerWidget {
  const RouteMonitorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Monitoramento de Rotas',
      theme: buildAppTheme(),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => SyncTriggers(
        child: PositionReportingTrigger(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
