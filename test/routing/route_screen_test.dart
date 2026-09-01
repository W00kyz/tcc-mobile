import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/map_screen.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/route_screen.dart';

import 'no_tiles_tile_provider.dart';

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

class _StaticRouteRepository implements RouteRepository {
  _StaticRouteRepository(this.routes);

  final List<RouteSummary> routes;

  @override
  Future<List<RouteSummary>> fetchMyRoutes({DateTime? date}) async => routes;

  @override
  Future<RouteSummary> startRoute({
    required String routeId,
    required double latitude,
    required double longitude,
  }) async {
    throw UnimplementedError('not exercised in this test');
  }
}

class _ThrowingRouteRepository implements RouteRepository {
  @override
  Future<List<RouteSummary>> fetchMyRoutes({DateTime? date}) async {
    throw DioException(requestOptions: RequestOptions(path: '/routes/me'));
  }

  @override
  Future<RouteSummary> startRoute({
    required String routeId,
    required double latitude,
    required double longitude,
  }) async {
    throw UnimplementedError('not exercised in this test');
  }
}

class _FakeLocationService implements LocationService {
  @override
  Future<Coordinates> getCurrentPosition() async =>
      const Coordinates(latitude: -7.23, longitude: -35.88);
}

RouteSummary _routeWith({
  required List<RouteStopSummary> stops,
  String routeType = 'REGULAR',
}) => RouteSummary(
  id: 'r1',
  fieldWorkerName: 'João',
  routeDate: DateTime(2026, 8, 25),
  routeType: routeType,
  status: 'PLANNED',
  startedAt: null,
  stops: stops,
);

Widget _screenWith(RouteRepository repository) => ProviderScope(
  overrides: [routeRepositoryProvider.overrideWithValue(repository)],
  child: const MaterialApp(home: RouteScreen()),
);

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

  testWidgets('shows the empty state when there are no routes', (tester) async {
    await tester.pumpWidget(_screenWith(_StaticRouteRepository(const [])));
    await tester.pumpAndSettle();

    expect(find.text('Nenhuma rota atribuída para hoje.'), findsOneWidget);
  });

  testWidgets('shows the error state when the fetch fails', (tester) async {
    await tester.pumpWidget(_screenWith(_ThrowingRouteRepository()));
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível carregar sua rota.'),
      findsOneWidget,
    );
  });

  testWidgets('renders the EVENTUAL chip for an occasional route', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screenWith(
        _StaticRouteRepository([
          _routeWith(
            routeType: 'OCCASIONAL',
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
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Chip, 'EVENTUAL'), findsOneWidget);
  });

  testWidgets('hides the EVENTUAL chip for a regular route', (tester) async {
    await tester.pumpWidget(_screenWith(_FakeRouteRepository()));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Chip, 'EVENTUAL'), findsNothing);
  });

  testWidgets('marks an occasional stop', (tester) async {
    await tester.pumpWidget(
      _screenWith(
        _StaticRouteRepository([
          _routeWith(
            stops: const [
              RouteStopSummary(
                id: 's1',
                orderIndex: 1,
                status: 'PENDING',
                servicePointName: 'Sala 101',
                latitude: -7.21,
                longitude: -35.91,
                pointType: 'OCCASIONAL',
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ponto eventual'), findsOneWidget);
  });

  testWidgets('renders the arrival window when it is set', (tester) async {
    await tester.pumpWidget(
      _screenWith(
        _StaticRouteRepository([
          _routeWith(
            stops: [
              RouteStopSummary(
                id: 's1',
                orderIndex: 1,
                status: 'PENDING',
                servicePointName: 'Sala 101',
                latitude: -7.21,
                longitude: -35.91,
                pointType: 'REGULAR',
                expectedArrivalFrom: DateTime(2026, 8, 25, 8),
                expectedArrivalTo: DateTime(2026, 8, 25, 8, 30),
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('08:00'), findsOneWidget);
    expect(find.textContaining('08:00–08:30'), findsOneWidget);
  });

  testWidgets('renders a one-sided window as a bare HH:MM', (tester) async {
    await tester.pumpWidget(
      _screenWith(
        _StaticRouteRepository([
          _routeWith(
            stops: [
              RouteStopSummary(
                id: 's1',
                orderIndex: 1,
                status: 'PENDING',
                servicePointName: 'Sala 101',
                latitude: -7.21,
                longitude: -35.91,
                pointType: 'REGULAR',
                expectedArrivalFrom: DateTime(2026, 8, 25, 8),
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Janela: 08:00'), findsOneWidget);
    expect(find.textContaining('–'), findsNothing);
  });

  testWidgets('omits the window line when no window is set', (tester) async {
    await tester.pumpWidget(_screenWith(_FakeRouteRepository()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Janela:'), findsNothing);
  });

  testWidgets('renders the travel-from-previous distance and time', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screenWith(
        _StaticRouteRepository([
          _routeWith(
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
              RouteStopSummary(
                id: 's2',
                orderIndex: 2,
                status: 'PENDING',
                servicePointName: 'Sala 102',
                latitude: -7.22,
                longitude: -35.92,
                pointType: 'REGULAR',
                distanceFromPrevM: 120,
                durationFromPrevS: 180,
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('120 m'), findsOneWidget);
    expect(find.textContaining('3 min'), findsOneWidget);
  });

  testWidgets('shows the stop order index', (tester) async {
    await tester.pumpWidget(_screenWith(_FakeRouteRepository()));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(CircleAvatar, '1'), findsOneWidget);
  });

  testWidgets('navigates to the map when "Ver no mapa" is tapped', (
    tester,
  ) async {
    // MapScreen now hosts the real offline map; inject a no-op base-tile
    // provider so navigating to it does not spin up vector_map_tiles' real
    // pipeline (and its pending timers) under flutter_test. The map itself is
    // covered by map_screen_test.dart.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          routeRepositoryProvider.overrideWithValue(_FakeRouteRepository()),
        ],
        child: MaterialApp(
          home: RouteScreen(mapTileProvider: NoTilesTileProvider()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Ver no mapa'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Ver no mapa'));
    await tester.pumpAndSettle();

    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.text('Trajeto da rota'), findsOneWidget);
  });

  testWidgets('still opens the check-in flow from a stop', (tester) async {
    await tester.pumpWidget(_screenWith(_FakeRouteRepository()));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, 'Check-in'), findsOneWidget);
  });

  testWidgets('hides the check-in button for a done stop', (tester) async {
    await tester.pumpWidget(
      _screenWith(
        _StaticRouteRepository([
          _routeWith(
            stops: const [
              RouteStopSummary(
                id: 's1',
                orderIndex: 1,
                status: 'DONE',
                servicePointName: 'Sala 101',
                latitude: -7.21,
                longitude: -35.91,
                pointType: 'REGULAR',
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, 'Check-in'), findsNothing);
  });
}
