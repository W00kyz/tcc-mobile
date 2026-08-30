import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/route_screen.dart';

class _FakeRouteRepository implements RouteRepository {
  @override
  Future<List<RouteSummary>> fetchMyRoutes() async => [
    const RouteSummary(
      id: 'r1',
      fieldWorkerName: 'João',
      startedAt: null,
      stops: [
        RouteStopSummary(
          id: 's1',
          orderIndex: 1,
          status: 'PENDING',
          servicePointName: 'Sala 101',
        ),
      ],
    ),
  ];

  @override
  Future<RouteSummary> startRoute({
    required String routeId,
    required double latitude,
    required double longitude,
  }) async {
    throw UnimplementedError('not exercised in this test');
  }
}

void main() {
  testWidgets('shows the assigned stop and a start button', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          routeRepositoryProvider.overrideWithValue(_FakeRouteRepository()),
        ],
        child: const MaterialApp(home: RouteScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sala 101'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Iniciar rota'), findsOneWidget);
  });
}
