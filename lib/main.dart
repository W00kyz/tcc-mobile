import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

void main() {
  runApp(const ProviderScope(child: RouteMonitorApp()));
}

final _router = GoRouter(
  initialLocation: '/entrar',
  routes: [
    // LoginScreen arrives in Task 15; RouteScreen in Task 16.
    GoRoute(
      path: '/entrar',
      builder: (context, state) => const _PlaceholderScreen(),
    ),
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
    );
  }
}

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Monitoramento de Rotas')));
  }
}
