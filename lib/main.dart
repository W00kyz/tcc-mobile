import 'package:flutter/material.dart';

void main() {
  runApp(const RouteMonitorApp());
}

/// Root widget of the field application.
///
/// Kept deliberately thin: later stages wrap it with the Riverpod provider
/// scope and the router rather than growing this class.
///
///     runApp(const RouteMonitorApp());
class RouteMonitorApp extends StatelessWidget {
  const RouteMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monitoramento de Rotas',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6E4F)),
        useMaterial3: true,
      ),
      home: const _HomeScreen(),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Monitoramento de Rotas'),
              SizedBox(height: 8),
              Text('Prefeitura Universitária — UFCG'),
            ],
          ),
        ),
      ),
    );
  }
}
