import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/evidence_capture.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/execution_repository.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/open_execution_store.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/map_screen.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/route_screen.dart';

import 'no_tiles_tile_provider.dart';

/// A real, decodable 1x1 transparent PNG — used wherever a test needs
/// `Image.memory` to actually succeed instead of throwing mid-decode.
final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
  '42YAAAAASUVORK5CYII=',
);

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

/// Counts `fetchMyRoutes` calls so a check-out test can assert
/// `myRoutesProvider` was actually invalidated (a second fetch happened)
/// rather than only checking the success snackbar.
class _CountingRouteRepository implements RouteRepository {
  _CountingRouteRepository(this.routes);

  final List<RouteSummary> routes;
  int fetchCount = 0;

  @override
  Future<List<RouteSummary>> fetchMyRoutes({DateTime? date}) async {
    fetchCount++;
    return routes;
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
/// Records every checkIn/checkOut call instead of hitting the network, and
/// returns or throws whatever the test configures — the seam that lets
/// RouteScreen's post-scan flow (GPS handling, snackbars,
/// AmbiguousRoomException, the room picker) be exercised without a real Dio
/// client or camera. [error]/[checkOutError] are consumed once: after the
/// first call they stop throwing, so a picker-driven retry within the same
/// tap can be configured to succeed on its second call.
class _FakeExecutionApi implements ExecutionApi {
  _FakeExecutionApi({this.error, this.checkOutError});

  Exception? error;
  Exception? checkOutError;
  final List<String> qrPayloads = [];
  final List<String?> checkInRouteStopIds = [];
  final List<String> checkInIdempotencyKeys = [];
  final List<String> checkOutIdempotencyKeys = [];
  double? capturedLatitude;
  double? capturedLongitude;
  String? lastCheckOutRouteStopId;

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
    checkInRouteStopIds.add(routeStopId);
    checkInIdempotencyKeys.add(idempotencyKey);
    capturedLatitude = latitude;
    capturedLongitude = longitude;
    if (error != null) {
      final toThrow = error!;
      error = null;
      throw toThrow;
    }
    return const CheckInResult(
      routeStopId: 's1',
      executionId: 'exec-1',
      geoValidation: 'INSIDE',
      flags: [],
    );
  }

  @override
  Future<CheckOutResult> checkOut({
    required String qrPayload,
    required DateTime scannedAt,
    required String checkoutIdempotencyKey,
    double? latitude,
    double? longitude,
    String? routeStopId,
  }) async {
    qrPayloads.add(qrPayload);
    checkOutIdempotencyKeys.add(checkoutIdempotencyKey);
    lastCheckOutRouteStopId = routeStopId;
    capturedLatitude = latitude;
    capturedLongitude = longitude;
    if (checkOutError != null) {
      final toThrow = checkOutError!;
      checkOutError = null;
      throw toThrow;
    }
    return CheckOutResult(
      routeStopId: routeStopId ?? 's1',
      executionId: 'exec-1',
      checkedOutAt: DateTime.utc(2026, 8, 25, 8, 40),
      flags: const [],
    );
  }
}

/// An in-memory stand-in for the local write-ahead log —
/// ExecutionRepository's own enqueue/mark-synced/mark-failed behavior is
/// already proven by execution_repository_test.dart, but RouteScreen also
/// needs a *shared* instance here: `stopEvidenceProvider` reads
/// `localWriteStoreProvider` directly, so a photo/note added through
/// `ExecutionRepository` in one test must be visible to the evidence list
/// through the same store instance — a pure no-op store would never
/// surface it.
class _InMemoryLocalWriteStore implements LocalWriteStore {
  final Map<String, PendingOperationRow> _rows = {};

  @override
  Future<void> enqueue({
    required String id,
    required PendingOpKind kind,
    required Map<String, dynamic> payload,
    required String routeId,
  }) async {
    _rows[id] = PendingOperationRow(
      id: id,
      kind: kind,
      routeId: routeId,
      payload: payload,
      createdAt: _rows.length,
      state: PendingOpState.pending,
      lastError: null,
    );
  }

  @override
  Future<void> markSynced(String id) async =>
      _setState(id, PendingOpState.synced);

  @override
  Future<void> markFailed(String id, String error) async =>
      _setState(id, PendingOpState.failed, error: error);

  void _setState(String id, PendingOpState state, {String? error}) {
    final row = _rows[id]!;
    _rows[id] = PendingOperationRow(
      id: row.id,
      kind: row.kind,
      routeId: row.routeId,
      payload: row.payload,
      createdAt: row.createdAt,
      state: state,
      lastError: error,
    );
  }

  @override
  Future<List<PendingOperationRow>> unsyncedForRoute(String routeId) async =>
      _rows.values
          .where(
            (r) => r.routeId == routeId && r.state != PendingOpState.synced,
          )
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
}

/// A no-op OpenExecutionStore — always reports no open execution (`null`),
/// so a plain check-in/check-out test never triggers `_StopEvidenceSection`
/// (Ruling 17: `null` hides the evidence buttons entirely). Evidence-specific
/// tests use `_FakeOpenExecutionStore` instead.
class _NoopOpenExecutionStore implements OpenExecutionStore {
  @override
  Future<void> recordOpenExecution(
    String routeStopId,
    String executionId,
  ) async {}

  @override
  Future<void> clearOpenExecution(String routeStopId) async {}

  @override
  Future<String?> openExecutionFor(String routeStopId) async => null;
}

/// An in-memory OpenExecutionStore for tests that need a stop's evidence
/// section to actually render — pre-seed with `seed` (routeStopId ->
/// executionId).
class _FakeOpenExecutionStore implements OpenExecutionStore {
  _FakeOpenExecutionStore([Map<String, String> seed = const {}])
    : _open = Map.of(seed);

  final Map<String, String> _open;

  @override
  Future<void> recordOpenExecution(
    String routeStopId,
    String executionId,
  ) async {
    _open[routeStopId] = executionId;
  }

  @override
  Future<void> clearOpenExecution(String routeStopId) async {
    _open.remove(routeStopId);
  }

  @override
  Future<String?> openExecutionFor(String routeStopId) async =>
      _open[routeStopId];
}

/// A no-op EvidenceApi — `listEvidence` returns no synced items and the
/// uploads never fail, for tests that don't specifically exercise the
/// evidence upload/list path.
class _NoopEvidenceApi implements EvidenceApi {
  @override
  Future<void> uploadNote({
    required String executionId,
    required String textBody,
    required DateTime capturedAt,
  }) async {}

  @override
  Future<void> uploadPhoto({
    required String executionId,
    required Uint8List bytes,
    required String sha256,
    required DateTime capturedAt,
  }) async {}

  @override
  Future<List<EvidenceItem>> listEvidence(String executionId) async => [];
}

/// Records upload calls and returns [syncedItems] from `listEvidence` — the
/// seam RouteScreen's evidence-list tests exercise instead of the real
/// network.
class _FakeEvidenceApi implements EvidenceApi {
  _FakeEvidenceApi({
    this.syncedItems = const [],
    this.uploadPhotoError,
    this.uploadNoteError,
  });

  final List<EvidenceItem> syncedItems;
  Exception? uploadPhotoError;
  Exception? uploadNoteError;
  final List<String> uploadedPhotoExecutionIds = [];
  final List<String> uploadedNoteTexts = [];

  @override
  Future<void> uploadPhoto({
    required String executionId,
    required Uint8List bytes,
    required String sha256,
    required DateTime capturedAt,
  }) async {
    uploadedPhotoExecutionIds.add(executionId);
    if (uploadPhotoError != null) {
      final toThrow = uploadPhotoError!;
      uploadPhotoError = null;
      throw toThrow;
    }
  }

  @override
  Future<void> uploadNote({
    required String executionId,
    required String textBody,
    required DateTime capturedAt,
  }) async {
    uploadedNoteTexts.add(textBody);
    if (uploadNoteError != null) {
      final toThrow = uploadNoteError!;
      uploadNoteError = null;
      throw toThrow;
    }
  }

  @override
  Future<List<EvidenceItem>> listEvidence(String executionId) async =>
      syncedItems;
}

/// A fake camera — returns [photo] (or throws [error]) instead of opening
/// the real camera app.
class _FakeEvidenceCapture implements EvidenceCapture {
  _FakeEvidenceCapture({this.photo, this.error});

  final CapturedPhoto? photo;

  /// `Error?`, not `Exception?`: the real `DeviceEvidenceCapture.takePhoto`
  /// can throw a `StateError` (a compression failure), so this fake must be
  /// able to reproduce that too.
  final Error? error;

  @override
  Future<CapturedPhoto?> takePhoto() async {
    if (error != null) throw error!;
    return photo;
  }
}

/// Makes every `NetworkImage` load inside [body] resolve to [bytes] instead
/// of hitting the real (fake-400-under-`flutter_test`) network — installed
/// via Flutter's own `debugNetworkImageHttpClientProvider` test hook.
/// Without this, a synced photo's `NetworkImage` throws a
/// `NetworkImageLoadException` mid-test (flutter_test's default `HttpClient`
/// returns 400 for everything). Reset happens in a `finally`, synchronously
/// before this function returns — `addTearDown` runs too late here:
/// `TestWidgetsFlutterBinding._verifyInvariants` (which asserts every debug
/// painting variable is back to null) runs right after the test body
/// returns but before `package:test`'s own tearDown queue.
Future<void> _withMockedNetworkImages(
  Uint8List bytes,
  Future<void> Function() body,
) async {
  debugNetworkImageHttpClientProvider = () => _FakeHttpClient(bytes);
  try {
    await body();
  } finally {
    debugNetworkImageHttpClientProvider = null;
  }
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._bytes);
  final Uint8List _bytes;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeHttpClientRequest(_bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this._bytes);
  final Uint8List _bytes;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse(_bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  void add(
    String name,
    Object value, {
    bool preserveHeaderCase = false,
  }) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse(this._bytes);
  final Uint8List _bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  EvidenceApi? evidenceApi,
  EvidenceCapture? evidenceCapture,
  OpenExecutionStore? openExecutionStore,
  LocalWriteStore? localWriteStore,
  String? apiBaseUrl,
  Session? session,
}) {
  // Always overridden, regardless of whether the test cares about evidence:
  // any IN_PROGRESS stop builds a _StopEvidenceSection that watches
  // openExecutionForProvider/stopEvidenceProvider/localWriteStoreProvider,
  // and those must never fall through to the real Drift database or a real
  // Dio client under flutter_test (docs/CLAUDE.base.md — never touch the
  // network in a test).
  final resolvedOpenExecutions =
      openExecutionStore ?? _NoopOpenExecutionStore();
  final resolvedEvidenceApi = evidenceApi ?? _NoopEvidenceApi();
  final resolvedLocalStore = localWriteStore ?? _InMemoryLocalWriteStore();
  return ProviderScope(
    overrides: [
      routeRepositoryProvider.overrideWithValue(repository),
      if (locationService != null)
        locationServiceProvider.overrideWithValue(locationService),
      openExecutionStoreProvider.overrideWithValue(resolvedOpenExecutions),
      evidenceApiProvider.overrideWithValue(resolvedEvidenceApi),
      localWriteStoreProvider.overrideWithValue(resolvedLocalStore),
      // Never the real apiBaseUrlFromEnvironment() under flutter_test (no
      // --dart-define here) — a fixed value unless a test needs a specific
      // one (the synced-photo thumbnail URL/header test).
      apiBaseUrlProvider.overrideWithValue(apiBaseUrl ?? 'http://test-base'),
      if (session != null)
        sessionProvider.overrideWith(() => _FixedSession(session)),
      if (evidenceCapture != null)
        evidenceCaptureProvider.overrideWithValue(evidenceCapture),
      if (executionApi != null)
        executionRepositoryProvider.overrideWithValue(
          ExecutionRepository(
            executionApi,
            resolvedLocalStore,
            resolvedEvidenceApi,
            resolvedOpenExecutions,
          ),
        ),
    ],
    child: const MaterialApp(home: RouteScreen()),
  );
}

/// Overrides `sessionProvider` with a fixed, non-null `Session` — the
/// synced-photo thumbnail test needs a real access token to assert the
/// `Authorization` header.
class _FixedSession extends SessionNotifier {
  _FixedSession(this._session);
  final Session _session;

  @override
  Session? build() => _session;
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

  testWidgets(
    'hides the check-in button when the only remaining stop is already '
    'IN_PROGRESS (checked in, awaiting checkout — Task 18), not PENDING',
    (tester) async {
      // Regression: _canCheckIn used to accept any stop.status != 'DONE',
      // so it stayed visible here — the backend has no PENDING candidate to
      // resolve on that floor any more, so scanning again would only get a
      // confusing 422 FLOOR_NOT_ON_ROUTE dead end (task-17 review).
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
                  status: 'IN_PROGRESS',
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

  // This pushes a real, uncontrolled ScanScreen() — no test controller, so
  // MobileScanner builds its own default (autoStart: true) controller and
  // tries to start the real camera. That is safe under flutter_test, but not
  // because the platform-channel call fails and gets caught: it never
  // resolves at all. MobileScanner._initializeController fires
  // unawaited(controller.start()), which calls MethodChannelMobileScanner's
  // _requestCameraPermission() -> methodChannel.invokeMethod(...) against a
  // channel flutter_test never mocks; that call just hangs forever (traced
  // and confirmed empirically in task-17 review — a direct `await
  // controller.start()` times out rather than throwing or completing). It's
  // safe here only because nothing in these tests ever awaits or observes
  // that leaked future — a future mobile_scanner/engine version that changes
  // channel-buffer draining could turn this into a real
  // MissingPluginException surfacing mid-test.
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

  Future<void> tapConcluirAndScan(WidgetTester tester, String rawValue) async {
    await tester.tap(find.widgetWithText(TextButton, 'Concluir'));
    await tester.pumpAndSettle();

    expect(find.byType(ScanScreen), findsOneWidget);
    final scanScreenContext = tester.element(find.byType(ScanScreen));
    Navigator.of(scanScreenContext).pop(rawValue);
  }

  RouteSummary inProgressStopRoute() => _routeWith(
    status: 'IN_PROGRESS',
    startedAt: DateTime(2026, 8, 25, 8),
    stops: const [
      RouteStopSummary(
        id: 's1',
        orderIndex: 1,
        status: 'IN_PROGRESS',
        servicePointName: 'Sala 101',
        latitude: -7.21,
        longitude: -35.91,
        pointType: 'REGULAR',
      ),
    ],
  );

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
    'on AmbiguousRoomException from check-in, shows the room picker and '
    'retries checkIn with the chosen routeStopId and the same '
    'idempotencyKey',
    (tester) async {
      final api = _FakeExecutionApi(
        error: const AmbiguousRoomException([
          RoomCandidate(
            routeStopId: 's1',
            servicePointId: 'sp1',
            name: 'Sala 101',
            distanceM: 3.2,
          ),
          RoomCandidate(
            routeStopId: 's2',
            servicePointId: 'sp2',
            name: 'Sala 102',
            distanceM: 8,
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

      // The picker is up, nearest ("Sala 101") pre-selected; choose the
      // farther one instead, then confirm.
      expect(
        find.text('Vários pontos correspondem — escolha o certo:'),
        findsOneWidget,
      );
      await tester.tap(find.text('Sala 102'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();

      expect(api.checkInRouteStopIds, [null, 's2']);
      expect(api.checkInIdempotencyKeys, hasLength(2));
      expect(api.checkInIdempotencyKeys[0], api.checkInIdempotencyKeys[1]);
      expect(find.text('Check-in registrado.'), findsOneWidget);
    },
  );

  testWidgets(
    'dismissing the room picker without choosing leaves the failed check-in '
    'as-is',
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

      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await tester.pumpAndSettle();

      // Only the first (failed) attempt happened — no retry.
      expect(api.checkInRouteStopIds, [null]);
      expect(find.text('Check-in registrado.'), findsNothing);
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

  testWidgets(
    'shows a "Concluir" action only for an IN_PROGRESS stop, not a PENDING '
    'one',
    (tester) async {
      await tester.pumpWidget(_screenWith(_FakeRouteRepository()));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextButton, 'Concluir'), findsNothing);
    },
  );

  testWidgets(
    'runs the check-out flow end-to-end: scans, checks out, invalidates '
    'myRoutesProvider and shows success',
    (tester) async {
      final api = _FakeExecutionApi();
      final repository = _CountingRouteRepository([inProgressStopRoute()]);
      await tester.pumpWidget(
        _screenWith(
          repository,
          locationService: _FakeLocationService(),
          executionApi: api,
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.fetchCount, 1);

      await tapConcluirAndScan(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      expect(api.qrPayloads, ['v1.floor.1.sig']);
      expect(api.lastCheckOutRouteStopId, 's1');
      expect(find.text('Check-out registrado.'), findsOneWidget);
      expect(repository.fetchCount, 2);
    },
  );

  testWidgets(
    'shows a generic failure message when check-out fails with a plain '
    'DioException (e.g. the 422 NO_OPEN_CHECKIN case), not the room picker',
    (tester) async {
      final api = _FakeExecutionApi(
        checkOutError: DioException(
          requestOptions: RequestOptions(path: '/check-outs'),
          response: Response(
            requestOptions: RequestOptions(path: '/check-outs'),
            statusCode: 422,
          ),
        ),
      );
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressStopRoute()]),
          locationService: _FakeLocationService(),
          executionApi: api,
        ),
      );
      await tester.pumpAndSettle();

      await tapConcluirAndScan(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      expect(
        find.text('Não foi possível registrar o check-out.'),
        findsOneWidget,
      );
      expect(
        find.text('Vários pontos correspondem — escolha o certo:'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'on AmbiguousRoomException from check-out, shows the room picker and '
    'retries with the chosen routeStopId and the same '
    'checkoutIdempotencyKey',
    (tester) async {
      // Ruling 16: rare in practice (check-out already sends its own stop
      // as routeStopId from the first attempt) but handled the same as
      // check-in's ambiguity by defense in depth.
      final api = _FakeExecutionApi(
        checkOutError: const AmbiguousRoomException([
          RoomCandidate(
            routeStopId: 's1',
            servicePointId: 'sp1',
            name: 'Sala 101',
            distanceM: 1,
          ),
        ]),
      );
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressStopRoute()]),
          locationService: _FakeLocationService(),
          executionApi: api,
        ),
      );
      await tester.pumpAndSettle();

      await tapConcluirAndScan(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      expect(
        find.text('Vários pontos correspondem — escolha o certo:'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();

      expect(api.checkOutIdempotencyKeys, hasLength(2));
      expect(api.checkOutIdempotencyKeys[0], api.checkOutIdempotencyKeys[1]);
      expect(find.text('Check-out registrado.'), findsOneWidget);
    },
  );

  testWidgets(
    'hides the evidence buttons for an IN_PROGRESS stop with no '
    'OpenExecutions row (Ruling 17 cold-start gap)',
    (tester) async {
      await tester.pumpWidget(
        _screenWith(_StaticRouteRepository([inProgressStopRoute()])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Adicionar foto'), findsNothing);
      expect(find.text('Adicionar observação'), findsNothing);
    },
  );

  testWidgets(
    'shows the evidence buttons for an IN_PROGRESS stop once its '
    'OpenExecutions row resolves',
    (tester) async {
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressStopRoute()]),
          openExecutionStore: _FakeOpenExecutionStore({'s1': 'exec-1'}),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TextButton, 'Adicionar foto'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextButton, 'Adicionar observação'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tapping "Adicionar foto" captures, uploads the photo and shows success',
    (tester) async {
      final evidenceApi = _FakeEvidenceApi();
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressStopRoute()]),
          openExecutionStore: _FakeOpenExecutionStore({'s1': 'exec-1'}),
          executionApi: _FakeExecutionApi(),
          evidenceApi: evidenceApi,
          evidenceCapture: _FakeEvidenceCapture(
            photo: CapturedPhoto(
              bytes: Uint8List.fromList([1, 2, 3]),
              sha256: 'abc123',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Adicionar foto'));
      await tester.pumpAndSettle();

      expect(evidenceApi.uploadedPhotoExecutionIds, ['exec-1']);
      expect(find.text('Foto adicionada.'), findsOneWidget);
    },
  );

  testWidgets(
    'does nothing when the field worker cancels the camera (takePhoto '
    'returns null)',
    (tester) async {
      final evidenceApi = _FakeEvidenceApi();
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressStopRoute()]),
          openExecutionStore: _FakeOpenExecutionStore({'s1': 'exec-1'}),
          executionApi: _FakeExecutionApi(),
          evidenceApi: evidenceApi,
          evidenceCapture: _FakeEvidenceCapture(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Adicionar foto'));
      await tester.pumpAndSettle();

      expect(evidenceApi.uploadedPhotoExecutionIds, isEmpty);
      expect(find.text('Foto adicionada.'), findsNothing);
      expect(
        find.text('Não foi possível adicionar a foto.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'shows a failure snackbar when the photo upload fails',
    (tester) async {
      final evidenceApi = _FakeEvidenceApi(
        uploadPhotoError: DioException(
          requestOptions: RequestOptions(
            path: '/executions/exec-1/evidence/photo',
          ),
        ),
      );
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressStopRoute()]),
          openExecutionStore: _FakeOpenExecutionStore({'s1': 'exec-1'}),
          executionApi: _FakeExecutionApi(),
          evidenceApi: evidenceApi,
          evidenceCapture: _FakeEvidenceCapture(
            photo: CapturedPhoto(
              bytes: Uint8List.fromList([1, 2, 3]),
              sha256: 'abc123',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Adicionar foto'));
      await tester.pumpAndSettle();

      expect(find.text('Não foi possível adicionar a foto.'), findsOneWidget);
    },
  );

  testWidgets(
    'shows a failure snackbar when the camera itself throws (e.g. '
    'compression failed)',
    (tester) async {
      final evidenceApi = _FakeEvidenceApi();
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressStopRoute()]),
          openExecutionStore: _FakeOpenExecutionStore({'s1': 'exec-1'}),
          executionApi: _FakeExecutionApi(),
          evidenceApi: evidenceApi,
          evidenceCapture: _FakeEvidenceCapture(
            error: StateError('Photo compression failed for "x.jpg".'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Adicionar foto'));
      await tester.pumpAndSettle();

      expect(evidenceApi.uploadedPhotoExecutionIds, isEmpty);
      expect(find.text('Não foi possível adicionar a foto.'), findsOneWidget);
    },
  );

  testWidgets(
    'shows a failure snackbar when the note upload fails',
    (tester) async {
      final evidenceApi = _FakeEvidenceApi(
        uploadNoteError: DioException(
          requestOptions: RequestOptions(
            path: '/executions/exec-1/evidence/note',
          ),
        ),
      );
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressStopRoute()]),
          openExecutionStore: _FakeOpenExecutionStore({'s1': 'exec-1'}),
          executionApi: _FakeExecutionApi(),
          evidenceApi: evidenceApi,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(TextButton, 'Adicionar observação'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sala trancada.');
      await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
      await tester.pumpAndSettle();

      expect(
        find.text('Não foi possível adicionar a observação.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tapping "Adicionar observação" opens a dialog and "Salvar" uploads the '
    'note',
    (tester) async {
      final evidenceApi = _FakeEvidenceApi();
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressStopRoute()]),
          openExecutionStore: _FakeOpenExecutionStore({'s1': 'exec-1'}),
          executionApi: _FakeExecutionApi(),
          evidenceApi: evidenceApi,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(TextButton, 'Adicionar observação'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Sala trancada.');
      await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
      await tester.pumpAndSettle();

      expect(evidenceApi.uploadedNoteTexts, ['Sala trancada.']);
      expect(find.text('Observação adicionada.'), findsOneWidget);
    },
  );

  testWidgets(
    'cancelling the note dialog uploads nothing',
    (tester) async {
      final evidenceApi = _FakeEvidenceApi();
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressStopRoute()]),
          openExecutionStore: _FakeOpenExecutionStore({'s1': 'exec-1'}),
          evidenceApi: evidenceApi,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(TextButton, 'Adicionar observação'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'not saved');
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await tester.pumpAndSettle();

      expect(evidenceApi.uploadedNoteTexts, isEmpty);
      expect(find.text('Observação adicionada.'), findsNothing);
    },
  );

  testWidgets(
    'renders a synced note from the backend and a pending local photo '
    'together, each with its own sync icon',
    (tester) async {
      final localStore = _InMemoryLocalWriteStore();
      await localStore.enqueue(
        id: 'op-photo-1',
        kind: PendingOpKind.evidencePhoto,
        routeId: 'r1',
        payload: {
          'execution_id': 'exec-1',
          // A real (1x1) PNG, not arbitrary bytes: Image.memory decodes this
          // eagerly, and flutter_test surfaces a decode failure as an
          // uncaught test error rather than a rendering glitch.
          'bytes_b64': base64Encode(_onePixelPng),
          'sha256': 'abc123',
          'captured_at': '2026-08-25T08:05:00.000Z',
        },
      );
      final evidenceApi = _FakeEvidenceApi(
        syncedItems: [
          EvidenceItem(
            id: 'e1',
            kind: 'NOTE',
            textBody: 'Sala trancada.',
            capturedAt: DateTime.utc(2026, 8, 25, 8),
            createdAt: DateTime.utc(2026, 8, 25, 8, 1),
          ),
        ],
      );
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressStopRoute()]),
          openExecutionStore: _FakeOpenExecutionStore({'s1': 'exec-1'}),
          evidenceApi: evidenceApi,
          localWriteStore: localStore,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sala trancada.'), findsOneWidget);
      expect(find.text('Foto'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done), findsOneWidget);
      expect(find.byIcon(Icons.cloud_upload), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    },
  );

  testWidgets(
    'renders a synced PHOTO evidence item as a NetworkImage built from the '
    'configured base URL + contentUrl, with a bearer-token Authorization '
    'header',
    (tester) async {
      await _withMockedNetworkImages(_onePixelPng, () async {
        final evidenceApi = _FakeEvidenceApi(
          syncedItems: [
            EvidenceItem(
              id: 'e1',
              kind: 'PHOTO',
              capturedAt: DateTime.utc(2026, 8, 25, 8),
              createdAt: DateTime.utc(2026, 8, 25, 8, 1),
              contentUrl: '/evidence/e1/content',
            ),
          ],
        );
        await tester.pumpWidget(
          _screenWith(
            _StaticRouteRepository([inProgressStopRoute()]),
            openExecutionStore: _FakeOpenExecutionStore({'s1': 'exec-1'}),
            evidenceApi: evidenceApi,
            apiBaseUrl: 'http://test-base',
            session: const Session(
              accessToken: 'test-token',
              refreshToken: 'test-refresh-token',
              role: 'FIELD_WORKER',
            ),
          ),
        );
        await tester.pumpAndSettle();

        final image = tester.widget<Image>(find.byType(Image));
        final provider = image.image as NetworkImage;
        expect(provider.url, 'http://test-base/evidence/e1/content');
        expect(provider.headers, {'Authorization': 'Bearer test-token'});
      });
    },
  );

  testWidgets(
    'renders a synced PHOTO evidence item with no headers when there is no '
    'session (no Authorization key, not a null-token crash)',
    (tester) async {
      await _withMockedNetworkImages(_onePixelPng, () async {
        final evidenceApi = _FakeEvidenceApi(
          syncedItems: [
            EvidenceItem(
              id: 'e1',
              kind: 'PHOTO',
              capturedAt: DateTime.utc(2026, 8, 25, 8),
              createdAt: DateTime.utc(2026, 8, 25, 8, 1),
              contentUrl: '/evidence/e1/content',
            ),
          ],
        );
        await tester.pumpWidget(
          _screenWith(
            _StaticRouteRepository([inProgressStopRoute()]),
            openExecutionStore: _FakeOpenExecutionStore({'s1': 'exec-1'}),
            evidenceApi: evidenceApi,
            apiBaseUrl: 'http://test-base',
          ),
        );
        await tester.pumpAndSettle();

        final image = tester.widget<Image>(find.byType(Image));
        final provider = image.image as NetworkImage;
        expect(provider.url, 'http://test-base/evidence/e1/content');
        expect(provider.headers, isNull);
      });
    },
  );
}
