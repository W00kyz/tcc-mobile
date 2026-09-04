import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:route_monitor/auth/login_screen.dart';
import 'package:route_monitor/forms/form_reconciliation.dart';
import 'package:route_monitor/routing/route_screen.dart';
import 'package:route_monitor/sync/sync_triggers.dart';

void main() {
  runApp(const ProviderScope(child: RouteMonitorApp()));
}

final _router = GoRouter(
  initialLocation: '/entrar',
  routes: [
    GoRoute(path: '/entrar', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/rota', builder: (context, state) => const RouteScreen()),
  ],
);

/// Root widget of the field application.
///
/// Kept deliberately thin: later stages wrap it with more providers rather
/// than growing this class.
///
///     runApp(const ProviderScope(child: RouteMonitorApp()));
class RouteMonitorApp extends StatelessWidget {
  const RouteMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Monitoramento de Rotas',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B4332)),
        useMaterial3: true,
      ),
      routerConfig: _router,
      builder: (context, child) => SyncTriggers(
        child: FormReconciliationTrigger(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
