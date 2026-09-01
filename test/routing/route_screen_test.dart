import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/route_screen.dart';

final _unstartedRoute = RouteSummary(
  id: 'r1',
  fieldWorkerName: 'João',
  routeDate: DateTime(2026, 8, 25),
  routeType: 'REGULAR',
  status: 'PLANNED',
  startedAt: null,
  stops: const [
    RouteStopSummary(
      id: 's1',
      orderIndex: 1,
      status: 'PENDING',
      servicePointName: 'Sala 101',
      latitude: -7.21,
      longitude: -35.91,
      pointType: 'REGULAR',
    ),
  ],
);

class _FakeRouteRepository implements RouteRepository {
  @override
  Future<List<RouteSummary>> fetchMyRoutes({DateTime? date}) async => [
    _unstartedRoute,
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

class _FailingStartRouteRepository implements RouteRepository {
  @override
  Future<List<RouteSummary>> fetchMyRoutes({DateTime? date}) async => [
    _unstartedRoute,
  ];

  @override
  Future<RouteSummary> startRoute({
    required String routeId,
    required double latitude,
    required double longitude,
  }) async {
    // Mirrors a real backend rejection (403 route-not-yours, 404, or 409
    // already-started) surfacing as a DioException from dio's own stack —
    // any thrown error must be handled the same way by _startRoute.
    throw DioException(
      requestOptions: RequestOptions(path: '/routes/$routeId/start'),
      response: Response(
        requestOptions: RequestOptions(path: '/routes/$routeId/start'),
        statusCode: 409,
      ),
    );
  }
}

class _FakeLocationService implements LocationService {
  @override
  Future<Coordinates> getCurrentPosition() async =>
      const Coordinates(latitude: -7.23, longitude: -35.88);
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

  testWidgets(
    'shows a snackbar instead of crashing when startRoute fails',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routeRepositoryProvider.overrideWithValue(
              _FailingStartRouteRepository(),
            ),
            locationServiceProvider.overrideWithValue(_FakeLocationService()),
          ],
          child: const MaterialApp(home: RouteScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Iniciar rota'));
      await tester.pumpAndSettle();

      expect(find.text('Não foi possível iniciar a rota.'), findsOneWidget);
    },
  );
}
