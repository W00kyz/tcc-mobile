import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/execution_repository.dart';
import 'package:route_monitor/local/local_write_store.dart';
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

/// GPS is unavailable (e.g. a basement, RF29/RNF13) — every failure shape
/// GeolocatorLocationService can produce maps to the same "proceed without
/// GPS" behavior in RouteScreen, so a single StateError stands in for all.
class _FailingLocationService implements LocationService {
  @override
  Future<Coordinates> getCurrentPosition() async {
    throw StateError('no GPS signal');
  }
}

/// Records every checkIn call instead of hitting the network, and returns or
/// throws whatever the test configures — the seam that lets RouteScreen's
/// post-scan flow (GPS handling, snackbars, AmbiguousRoomException) be
/// exercised without a real Dio client or camera.
class _FakeExecutionApi implements ExecutionApi {
  _FakeExecutionApi({this.error});

  final Exception? error;
  final List<String> qrPayloads = [];
  double? capturedLatitude;
  double? capturedLongitude;

  @override
  Future<CheckInResult> checkIn({
    required String qrPayload,
    required DateTime scannedAt,
    required String idempotencyKey,
    double? latitude,
    double? longitude,
    String? routeStopId,
  }) async {
    qrPayloads.add(qrPayload);
    capturedLatitude = latitude;
    capturedLongitude = longitude;
    if (error != null) throw error!;
    return const CheckInResult(
      routeStopId: 's1',
      geoValidation: 'INSIDE',
      flags: [],
    );
  }
}

/// A no-op stand-in for the local write-ahead log — ExecutionRepository's
/// own enqueue/mark-synced/mark-failed behavior is already proven by
/// execution_repository_test.dart; RouteScreen only needs *some*
/// LocalWriteStore to build a real ExecutionRepository around the fake API.
class _NoopLocalWriteStore implements LocalWriteStore {
  @override
  Future<void> enqueue({
    required String id,
    required PendingOpKind kind,
    required Map<String, dynamic> payload,
    required String routeId,
  }) async {}

  @override
  Future<void> markSynced(String id) async {}

  @override
  Future<void> markFailed(String id, String error) async {}

  @override
  Future<List<PendingOperationRow>> unsyncedForRoute(String routeId) async =>
      [];
}

RouteSummary _routeWith({
  required List<RouteStopSummary> stops,
  String routeType = 'REGULAR',
  String status = 'PLANNED',
  DateTime? startedAt,
}) => RouteSummary(
  id: 'r1',
  fieldWorkerName: 'João',
  routeDate: DateTime(2026, 8, 25),
  routeType: routeType,
  status: status,
  startedAt: startedAt,
  stops: stops,
);

Widget _screenWith(
  RouteRepository repository, {
  LocationService? locationService,
  ExecutionApi? executionApi,
}) => ProviderScope(
  overrides: [
    routeRepositoryProvider.overrideWithValue(repository),
    if (locationService != null)
      locationServiceProvider.overrideWithValue(locationService),
    if (executionApi != null)
      executionRepositoryProvider.overrideWithValue(
        ExecutionRepository(executionApi, _NoopLocalWriteStore()),
      ),
  ],
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

  testWidgets(
    'hides the check-in button when the route has not started',
    (tester) async {
      await tester.pumpWidget(_screenWith(_FakeRouteRepository()));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(FilledButton, 'Fazer check-in'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'shows the check-in button when the route is in progress with a '
    'pending stop',
    (tester) async {
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([
            _routeWith(
              status: 'IN_PROGRESS',
              startedAt: DateTime(2026, 8, 25, 8),
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

      expect(
        find.widgetWithText(FilledButton, 'Fazer check-in'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'hides the check-in button when every stop is already done',
    (tester) async {
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([
            _routeWith(
              status: 'IN_PROGRESS',
              startedAt: DateTime(2026, 8, 25, 8),
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

      expect(
        find.widgetWithText(FilledButton, 'Fazer check-in'),
        findsNothing,
      );
    },
  );

  RouteSummary inProgressRoute() => _routeWith(
    status: 'IN_PROGRESS',
    startedAt: DateTime(2026, 8, 25, 8),
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

  Future<void> tapCheckInAndScan(
    WidgetTester tester,
    String rawValue,
  ) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Fazer check-in'));
    await tester.pumpAndSettle();

    expect(find.byType(ScanScreen), findsOneWidget);
    final scanScreenContext = tester.element(find.byType(ScanScreen));
    Navigator.of(scanScreenContext).pop(rawValue);
  }

  testWidgets(
    'runs the check-in flow end-to-end: scans, checks in and shows success',
    (tester) async {
      final api = _FakeExecutionApi();
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressRoute()]),
          locationService: _FakeLocationService(),
          executionApi: api,
        ),
      );
      await tester.pumpAndSettle();

      await tapCheckInAndScan(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      expect(api.qrPayloads, ['v1.floor.1.sig']);
      expect(api.capturedLatitude, -7.23);
      expect(api.capturedLongitude, -35.88);
      expect(find.text('Check-in registrado.'), findsOneWidget);
    },
  );

  testWidgets(
    'does nothing when the scan screen is popped without a value',
    (tester) async {
      final api = _FakeExecutionApi();
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressRoute()]),
          locationService: _FakeLocationService(),
          executionApi: api,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Fazer check-in'));
      await tester.pumpAndSettle();
      final scanScreenContext = tester.element(find.byType(ScanScreen));
      Navigator.of(scanScreenContext).pop();
      await tester.pumpAndSettle();

      expect(api.qrPayloads, isEmpty);
      expect(
        find.widgetWithText(FilledButton, 'Fazer check-in'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tolerates a GPS failure during check-in and still checks in with '
    'null coordinates',
    (tester) async {
      final api = _FakeExecutionApi();
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressRoute()]),
          locationService: _FailingLocationService(),
          executionApi: api,
        ),
      );
      await tester.pumpAndSettle();

      await tapCheckInAndScan(tester, 'v1.floor.1.sig');
      // A single pump catches the GPS-failure snackbar before the queued
      // "Check-in registrado." success snackbar replaces it — asserting the
      // final state here would race the ScaffoldMessenger's own dismiss
      // timer instead of RouteScreen's logic.
      await tester.pump();

      expect(
        find.text(
          'Não foi possível obter sua localização; check-in seguirá sem GPS.',
        ),
        findsWidgets,
      );

      await tester.pumpAndSettle();
      expect(api.qrPayloads, ['v1.floor.1.sig']);
      expect(api.capturedLatitude, isNull);
      expect(api.capturedLongitude, isNull);
    },
  );

  testWidgets(
    'shows a placeholder message on AmbiguousRoomException from check-in',
    (tester) async {
      final api = _FakeExecutionApi(
        error: const AmbiguousRoomException([
          RoomCandidate(
            routeStopId: 's1',
            servicePointId: 'sp1',
            name: 'Sala 101',
            distanceM: 3.2,
          ),
        ]),
      );
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressRoute()]),
          locationService: _FakeLocationService(),
          executionApi: api,
        ),
      );
      await tester.pumpAndSettle();

      await tapCheckInAndScan(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      expect(
        find.text('Ambiguidade de sala: escolha o ponto correto (Tarefa 18).'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'shows a generic failure message when check-in fails for another reason',
    (tester) async {
      final api = _FakeExecutionApi(
        error: DioException(requestOptions: RequestOptions(path: '/check-ins')),
      );
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressRoute()]),
          locationService: _FakeLocationService(),
          executionApi: api,
        ),
      );
      await tester.pumpAndSettle();

      await tapCheckInAndScan(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      expect(
        find.text('Não foi possível registrar o check-in.'),
        findsOneWidget,
      );
    },
  );
}
