import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/auth/login_screen.dart';
import 'package:route_monitor/forms/form_reconciliation.dart';
import 'package:route_monitor/monitoring/position_reporting_trigger.dart';
import 'package:route_monitor/privacy/consent_screen.dart';
import 'package:route_monitor/privacy/my_data_screen.dart';
import 'package:route_monitor/routing/route_screen.dart';
import 'package:route_monitor/sync/sync_triggers.dart';

void main() {
  runApp(const ProviderScope(child: RouteMonitorApp()));
}

/// The app router, built through Riverpod so `redirect` can read the session
/// (LGPD consent gate, RNF10). A [ValueNotifier] bridged from [sessionProvider]
/// is the `refreshListenable`, so login, logout and consent acceptance all
/// re-run the guard.
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
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final location = state.matchedLocation;

      if (session == null) {
        return location == '/entrar' ? null : '/entrar';
      }
      if (session.consentRequired) {
        return location == '/consentimento' ? null : '/consentimento';
      }
      if (location == '/entrar' || location == '/consentimento') {
        return '/rota';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/entrar',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/consentimento',
        builder: (context, state) => const ConsentScreen(),
      ),
      GoRoute(path: '/rota', builder: (context, state) => const RouteScreen()),
      GoRoute(
        path: '/meus-dados',
        builder: (context, state) => const MyDataScreen(),
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B4332)),
        useMaterial3: true,
      ),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => SyncTriggers(
        child: FormReconciliationTrigger(
          child: PositionReportingTrigger(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
