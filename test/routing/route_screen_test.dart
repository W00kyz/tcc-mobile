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
import 'package:route_monitor/forms/form_draft_store.dart';
import 'package:route_monitor/forms/form_providers.dart';
import 'package:route_monitor/forms/form_schema.dart';
import 'package:route_monitor/forms/form_screen.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
import 'package:route_monitor/routing/blocked_sync_screen.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/map_screen.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/route_screen.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/sync/sync_worker.dart';

import '../support/in_memory_database.dart';
import 'no_tiles_tile_provider.dart';

/// A [SyncWorker] that records every `syncRoute` kick and never drains — the
/// repository fires this fire-and-forget after each enqueue (spec Ruling 2);
/// RouteScreen tests only care that the enqueue happened, not the network.
class _RecordingSyncWorker implements SyncWorker {
  _RecordingSyncWorker({this.statusStream});

  final Stream<RouteSyncStatus>? statusStream;
  final List<String> syncedRoutes = [];
  final List<String> unblocked = [];
  int syncAllCount = 0;

  @override
  Future<void> syncRoute(String routeId) async => syncedRoutes.add(routeId);

  @override
  Future<void> syncAll() async => syncAllCount++;

  @override
  Stream<RouteSyncStatus> statusFor(String routeId) =>
      statusStream ?? const Stream.empty();

  @override
  Future<void> unblock(String operationId) async => unblocked.add(operationId);

  @override
  Future<void> dispose() async {}
}

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
    required DateTime startedAt,
  }) async {
    throw UnimplementedError('not exercised in this test');
  }
}

/// In-memory [SyncMetaStore] — RouteScreen watches
/// `routeStartedLocallyProvider` on every render now (Etapa 6 Task 9), so
/// every test needs this instead of the real Drift-backed store.
class _InMemorySyncMetaStore implements SyncMetaStore {
  double? offset;
  final Map<String, DateTime> routeStartedAt = {};

  @override
  Future<double?> getClockOffsetSeconds() async => offset;

  @override
  Future<void> setClockOffsetSeconds(double seconds) async => offset = seconds;

  @override
  Future<DateTime?> getRouteStartedAt(String routeId) async =>
      routeStartedAt[routeId];

  @override
  Future<void> setRouteStartedAt(String routeId, DateTime startedAt) async =>
      routeStartedAt[routeId] = startedAt;
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
    required DateTime startedAt,
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
    required DateTime startedAt,
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
    required DateTime startedAt,
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

/// A no-op [ExecutionApi] — since Etapa 6 Task 8 the repository never calls
/// the network (spec Ruling 2), so `_screenWith` only uses an instance of
/// this as the trigger that swaps in a test `ExecutionRepository`. The
/// dispatch path itself is covered by sync_worker_test.dart.
class _FakeExecutionApi implements ExecutionApi {
  @override
  Future<({CheckInResult result, DateTime? serverDate})> checkIn({
    required String executionId,
    required String qrPayload,
    required DateTime scannedAt,
    required String idempotencyKey,
    double? latitude,
    double? longitude,
    String? routeStopId,
    double? clientClockOffsetSeconds,
  }) async => (
    result: const CheckInResult(
      routeStopId: 's1',
      executionId: 'exec-1',
      geoValidation: 'INSIDE',
      flags: [],
    ),
    serverDate: null,
  );

  @override
  Future<({CheckOutResult result, DateTime? serverDate})> checkOut({
    required String executionId,
    required String qrPayload,
    required DateTime scannedAt,
    required String checkoutIdempotencyKey,
    double? latitude,
    double? longitude,
    String? routeStopId,
    double? clientClockOffsetSeconds,
    String? formVersionId,
    List<Map<String, Object?>>? answers,
  }) async => (
    result: CheckOutResult(
      routeStopId: routeStopId ?? 's1',
      executionId: 'exec-1',
      checkedOutAt: DateTime.utc(2026, 8, 25, 8, 40),
      flags: const [],
    ),
    serverDate: null,
  );
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
      attempts: 0,
      nextAttemptAt: null,
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
      attempts: row.attempts,
      nextAttemptAt: row.nextAttemptAt,
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

  @override
  Future<void> markBlocked(String id, String error) async =>
      _setState(id, PendingOpState.blocked, error: error);

  @override
  Future<void> markRetryScheduled(
    String id, {
    required int attempts,
    required int nextAttemptAt,
  }) => throw UnimplementedError();

  @override
  Future<List<PendingOperationRow>> blockedForRoute(String routeId) async =>
      _rows.values
          .where(
            (r) => r.routeId == routeId && r.state == PendingOpState.blocked,
          )
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<List<PendingOperationRow>> dueForRoute(
    String routeId, {
    required int now,
  }) => throw UnimplementedError();

  @override
  Future<List<String>> routeIdsWithWork() => throw UnimplementedError();

  @override
  Future<void> resetToPending(String id) async {
    final row = _rows[id]!;
    _rows[id] = PendingOperationRow(
      id: row.id,
      kind: row.kind,
      routeId: row.routeId,
      payload: row.payload,
      createdAt: row.createdAt,
      state: PendingOpState.pending,
      lastError: null,
      attempts: 0,
      nextAttemptAt: null,
    );
  }
}

/// A no-op StopProgressStore — always reports no progress (`null`), so a plain
/// check-in/check-out test never triggers `_StopEvidenceSection` (Ruling 17:
/// `null` hides the evidence buttons entirely). Evidence-specific tests use
/// `_FakeStopProgressStore` instead.
class _NoopStopProgressStore implements StopProgressStore {
  @override
  Future<void> upsertInProgress(String routeStopId, String executionId) async {}

  @override
  Future<void> markDone(String routeStopId) async {}

  @override
  Future<StopProgressEntry?> progressFor(String routeStopId) async => null;

  @override
  Future<List<StopProgressEntry>> allForRoute(
    Iterable<String> routeStopIds,
  ) async => const [];
}

/// An in-memory StopProgressStore for tests that need a stop's evidence
/// section to actually render — pre-seed with `seed` (routeStopId ->
/// executionId); every seeded stop starts `inProgress`.
class _FakeStopProgressStore implements StopProgressStore {
  _FakeStopProgressStore([Map<String, String> seed = const {}]) {
    seed.forEach((routeStopId, executionId) {
      _rows[routeStopId] = StopProgressEntry(
        routeStopId: routeStopId,
        executionId: executionId,
        status: StopLocalStatus.inProgress,
      );
    });
  }

  final Map<String, StopProgressEntry> _rows = {};

  @override
  Future<void> upsertInProgress(
    String routeStopId,
    String executionId,
  ) async {
    _rows[routeStopId] = StopProgressEntry(
      routeStopId: routeStopId,
      executionId: executionId,
      status: StopLocalStatus.inProgress,
    );
  }

  @override
  Future<void> markDone(String routeStopId) async {
    final existing = _rows[routeStopId];
    if (existing == null) return;
    _rows[routeStopId] = StopProgressEntry(
      routeStopId: existing.routeStopId,
      executionId: existing.executionId,
      status: StopLocalStatus.done,
    );
  }

  @override
  Future<StopProgressEntry?> progressFor(String routeStopId) async =>
      _rows[routeStopId];

  @override
  Future<List<StopProgressEntry>> allForRoute(
    Iterable<String> routeStopIds,
  ) async => [
    for (final id in routeStopIds) ?_rows[id],
  ];
}

/// A no-op EvidenceApi — `listEvidence` returns no synced items and the
/// uploads never fail, for tests that don't specifically exercise the
/// evidence upload/list path.
class _NoopEvidenceApi implements EvidenceApi {
  @override
  Future<DateTime?> uploadNote({
    required String executionId,
    required String textBody,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async => null;

  @override
  Future<DateTime?> uploadPhoto({
    required String executionId,
    required Uint8List bytes,
    required String sha256,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async => null;

  @override
  Future<List<EvidenceItem>> listEvidence(String executionId) async => [];
}

/// Records upload calls and returns [syncedItems] from `listEvidence` — the
/// seam RouteScreen's evidence-list tests exercise instead of the real
/// network.
class _FakeEvidenceApi implements EvidenceApi {
  _FakeEvidenceApi({this.syncedItems = const []});

  final List<EvidenceItem> syncedItems;
  final List<String> uploadedPhotoExecutionIds = [];
  final List<String> uploadedNoteTexts = [];

  @override
  Future<DateTime?> uploadPhoto({
    required String executionId,
    required Uint8List bytes,
    required String sha256,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async {
    uploadedPhotoExecutionIds.add(executionId);
    return null;
  }

  @override
  Future<DateTime?> uploadNote({
    required String executionId,
    required String textBody,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async {
    uploadedNoteTexts.add(textBody);
    return null;
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
  StopProgressStore? stopProgressStore,
  LocalWriteStore? localWriteStore,
  SyncMetaStore? syncMetaStore,
  SyncWorker? syncWorker,
  FormDraftStore? formDraftStore,
  String? apiBaseUrl,
  Session? session,
}) {
  // Always overridden, regardless of whether the test cares about evidence:
  // any IN_PROGRESS stop builds a _StopEvidenceSection that watches
  // openExecutionForProvider/stopEvidenceProvider/localWriteStoreProvider,
  // and those must never fall through to the real Drift database or a real
  // Dio client under flutter_test (docs/CLAUDE.base.md — never touch the
  // network in a test).
  final resolvedOpenExecutions = stopProgressStore ?? _NoopStopProgressStore();
  final resolvedEvidenceApi = evidenceApi ?? _NoopEvidenceApi();
  final resolvedLocalStore = localWriteStore ?? _InMemoryLocalWriteStore();
  final resolvedSyncMeta = syncMetaStore ?? _InMemorySyncMetaStore();
  // Always overridden too: `formDraftStoreProvider`'s default builds a real
  // `DriftFormDraftStore` backed by the on-device SQLite file
  // (`appDatabaseProvider`) — an in-memory Drift database stands in instead,
  // same discipline as the stores above.
  final resolvedFormDraftStore =
      formDraftStore ??
      (() {
        final db = inMemoryDatabase();
        addTearDown(db.close);
        return DriftFormDraftStore(db);
      })();
  // Always overridden: the sync banner watches `routeSyncStatusProvider` on
  // every render now, and building the real `SyncWorker` reaches
  // `apiBaseUrlFromEnvironment()` (no `--dart-define` under flutter_test).
  final resolvedSyncWorker = syncWorker ?? _RecordingSyncWorker();
  return ProviderScope(
    overrides: [
      routeRepositoryProvider.overrideWithValue(repository),
      syncWorkerProvider.overrideWithValue(resolvedSyncWorker),
      if (locationService != null)
        locationServiceProvider.overrideWithValue(locationService),
      stopProgressStoreProvider.overrideWithValue(resolvedOpenExecutions),
      evidenceApiProvider.overrideWithValue(resolvedEvidenceApi),
      localWriteStoreProvider.overrideWithValue(resolvedLocalStore),
      syncMetaStoreProvider.overrideWithValue(resolvedSyncMeta),
      formDraftStoreProvider.overrideWithValue(resolvedFormDraftStore),
      // Never the real apiBaseUrlFromEnvironment() under flutter_test (no
      // --dart-define here) — a fixed value unless a test needs a specific
      // one (the synced-photo thumbnail URL/header test).
      apiBaseUrlProvider.overrideWithValue(apiBaseUrl ?? 'http://test-base'),
      if (session != null)
        sessionProvider.overrideWith(() => _FixedSession(session)),
      if (evidenceCapture != null)
        evidenceCaptureProvider.overrideWithValue(evidenceCapture),
      // The repository no longer calls the network (spec Ruling 2): it
      // enqueues into `resolvedLocalStore`, updates `resolvedOpenExecutions`,
      // then kicks a (recording, non-draining) SyncWorker. `executionApi` is
      // kept only as the trigger for this override; the dispatch path is
      // covered by sync_worker_test.dart.
      if (executionApi != null)
        executionRepositoryProvider.overrideWithValue(
          ExecutionRepository(
            resolvedLocalStore,
            resolvedOpenExecutions,
            resolvedSyncMeta,
            resolvedSyncWorker,
            resolvedFormDraftStore,
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
    await tester.pumpWidget(_screenWith(_FakeRouteRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Sala 101'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Iniciar rota'), findsOneWidget);
  });

  testWidgets(
    'tapping "Iniciar rota" enqueues a startRoute row and flips the UI to '
    '"iniciada" immediately, without a myRoutesProvider refetch',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      final syncMeta = _InMemorySyncMetaStore();
      final repository = _CountingRouteRepository([_unstartedRoute]);
      await tester.pumpWidget(
        _screenWith(
          repository,
          locationService: _FakeLocationService(),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
          syncMetaStore: syncMeta,
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.fetchCount, 1);

      await tester.tap(find.widgetWithText(FilledButton, 'Iniciar rota'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Iniciar rota'), findsNothing);
      expect(find.text('Rota iniciada'), findsOneWidget);
      expect(repository.fetchCount, 1);

      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.kind, PendingOpKind.startRoute);
      expect(rows.single.payload['latitude'], -7.23);
      expect(await syncMeta.getRouteStartedAt('r1'), isNotNull);
    },
  );

  testWidgets(
    'a GPS failure on "Iniciar rota" shows the location snackbar and '
    'enqueues nothing',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([_unstartedRoute]),
          locationService: _FailingLocationService(),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Iniciar rota'));
      await tester.pumpAndSettle();

      expect(
        find.text('Não foi possível obter sua localização.'),
        findsOneWidget,
      );
      expect(await store.unsyncedForRoute('r1'), isEmpty);
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
          syncMetaStoreProvider.overrideWithValue(_InMemorySyncMetaStore()),
          syncWorkerProvider.overrideWithValue(_RecordingSyncWorker()),
          stopProgressStoreProvider.overrideWithValue(_NoopStopProgressStore()),
          localWriteStoreProvider.overrideWithValue(_InMemoryLocalWriteStore()),
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
      final store = _InMemoryLocalWriteStore();
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressRoute()]),
          locationService: _FakeLocationService(),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      await tapCheckInAndScan(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.kind, PendingOpKind.checkIn);
      expect(rows.single.payload['qr_payload'], 'v1.floor.1.sig');
      expect(rows.single.payload['latitude'], -7.23);
      expect(rows.single.payload['longitude'], -35.88);
      expect(find.text('Check-in registrado.'), findsOneWidget);
    },
  );

  testWidgets(
    'does nothing when the scan screen is popped without a value',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressRoute()]),
          locationService: _FakeLocationService(),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Fazer check-in'));
      await tester.pumpAndSettle();
      final scanScreenContext = tester.element(find.byType(ScanScreen));
      Navigator.of(scanScreenContext).pop();
      await tester.pumpAndSettle();

      expect(await store.unsyncedForRoute('r1'), isEmpty);
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
      final store = _InMemoryLocalWriteStore();
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressRoute()]),
          locationService: _FailingLocationService(),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
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
      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.payload['qr_payload'], 'v1.floor.1.sig');
      expect(rows.single.payload['latitude'], isNull);
      expect(rows.single.payload['longitude'], isNull);
    },
  );

  // The GPS fix _FakeLocationService reports; the stops below are positioned
  // relative to it so the offline room resolution (spec Ruling 4) lands on a
  // known branch.
  RouteSummary oneRoomInRadiusRoute() => _routeWith(
    status: 'IN_PROGRESS',
    startedAt: DateTime(2026, 8, 25, 8),
    stops: const [
      RouteStopSummary(
        id: 's1',
        orderIndex: 1,
        status: 'PENDING',
        servicePointName: 'Sala 101',
        latitude: -7.23,
        longitude: -35.88,
        pointType: 'REGULAR',
      ),
      RouteStopSummary(
        id: 's2',
        orderIndex: 2,
        status: 'PENDING',
        servicePointName: 'Sala 102',
        // ~2.5 km away — well outside the 50 m check radius.
        latitude: -7.25,
        longitude: -35.90,
        pointType: 'REGULAR',
      ),
    ],
  );

  RouteSummary twoRoomsInRadiusRoute() => _routeWith(
    status: 'IN_PROGRESS',
    startedAt: DateTime(2026, 8, 25, 8),
    stops: const [
      RouteStopSummary(
        id: 's1',
        orderIndex: 1,
        status: 'PENDING',
        servicePointName: 'Sala 101',
        latitude: -7.23,
        longitude: -35.88,
        pointType: 'REGULAR',
      ),
      RouteStopSummary(
        id: 's2',
        orderIndex: 2,
        status: 'PENDING',
        servicePointName: 'Sala 102',
        // ~11 m from the GPS fix — inside the radius, but farther than s1.
        latitude: -7.2301,
        longitude: -35.88,
        pointType: 'REGULAR',
      ),
    ],
  );

  testWidgets(
    'check-in with GPS placing one pending stop in radius resolves to it '
    'and enqueues that routeStopId',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([oneRoomInRadiusRoute()]),
          locationService: _FakeLocationService(),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      await tapCheckInAndScan(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      expect(
        find.text('Vários pontos correspondem — escolha o certo:'),
        findsNothing,
      );
      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.kind, PendingOpKind.checkIn);
      expect(rows.single.payload['route_stop_id'], 's1');
      expect(find.text('Check-in registrado.'), findsOneWidget);
    },
  );

  testWidgets(
    'check-in with two pending stops in radius shows the picker (nearest '
    'pre-selected); choosing the second enqueues its routeStopId',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([twoRoomsInRadiusRoute()]),
          locationService: _FakeLocationService(),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      await tapCheckInAndScan(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      expect(
        find.text('Vários pontos correspondem — escolha o certo:'),
        findsOneWidget,
      );
      // Nearest ("Sala 101", s1) renders first and pre-selected; pick the
      // farther one instead. Scope to the sheet — the stop list behind it
      // also renders a "Sala 102" tile.
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Sala 102'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();

      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.payload['route_stop_id'], 's2');
      expect(find.text('Check-in registrado.'), findsOneWidget);
    },
  );

  testWidgets(
    'dismissing the room picker enqueues nothing and shows no snackbar',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([twoRoomsInRadiusRoute()]),
          locationService: _FakeLocationService(),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      await tapCheckInAndScan(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await tester.pumpAndSettle();

      expect(await store.unsyncedForRoute('r1'), isEmpty);
      expect(find.text('Check-in registrado.'), findsNothing);
    },
  );

  testWidgets(
    'no GPS with a single pending stop resolves to it and enqueues the '
    'check-in with a null distance',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      // A route with a single PENDING stop — with no GPS the resolution
      // falls to the "lone pending stop resolves anyway" path (Ruling 4 /
      // validation.py:117).
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressRoute()]),
          locationService: _FailingLocationService(),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      await tapCheckInAndScan(tester, 'v1.floor.1.sig');
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.text('Vários pontos correspondem — escolha o certo:'),
        findsNothing,
      );
      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.payload['route_stop_id'], 's1');
      expect(rows.single.payload['latitude'], isNull);
    },
  );

  // NOTE (Etapa 6 Task 8, updated Task 10): Task 8 deleted seven
  // server-`409`-driven widget tests here. Task 10 moved room resolution onto
  // the device (spec Ruling 4), so it restored the four that map to the local
  // flow: one-stop-in-radius auto-resolve, two-stops-in-radius picker,
  // picker-dismissed, and no-GPS lone-stop resolve (all just above). The
  // three "generic network failure snackbar" tests (check-in, check-out,
  // check-out 422-not-picker) genuinely can't come back — the enqueue can't
  // fail that way; failure classification is a `SyncWorker` concern now,
  // covered by sync_worker_test.dart.

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
      final store = _InMemoryLocalWriteStore();
      final repository = _CountingRouteRepository([inProgressStopRoute()]);
      await tester.pumpWidget(
        _screenWith(
          repository,
          locationService: _FakeLocationService(),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.fetchCount, 1);

      await tapConcluirAndScan(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.kind, PendingOpKind.checkOut);
      expect(rows.single.payload['qr_payload'], 'v1.floor.1.sig');
      expect(rows.single.payload['route_stop_id'], 's1');
      expect(find.text('Check-out registrado.'), findsOneWidget);
      expect(repository.fetchCount, 2);
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
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
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
    'renders all three stop states side by side with the right affordances '
    '(Task 20): DONE gets the check icon and no actions, IN_PROGRESS gets '
    '"Concluir" plus evidence actions, PENDING gets neither and only the '
    'route-level "Fazer check-in" entry applies',
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
                RouteStopSummary(
                  id: 's2',
                  orderIndex: 2,
                  status: 'IN_PROGRESS',
                  servicePointName: 'Sala 102',
                  latitude: -7.22,
                  longitude: -35.92,
                  pointType: 'REGULAR',
                ),
                RouteStopSummary(
                  id: 's3',
                  orderIndex: 3,
                  status: 'PENDING',
                  servicePointName: 'Sala 103',
                  latitude: -7.23,
                  longitude: -35.93,
                  pointType: 'REGULAR',
                ),
              ],
            ),
          ]),
          stopProgressStore: _FakeStopProgressStore({'s2': 'exec-1'}),
        ),
      );
      await tester.pumpAndSettle();

      // All three stops render.
      expect(find.text('Sala 101'), findsOneWidget);
      expect(find.text('Sala 102'), findsOneWidget);
      expect(find.text('Sala 103'), findsOneWidget);

      // DONE (s1): check icon, no Concluir on its tile, no evidence actions
      // for it — only s2 (IN_PROGRESS) resolves an OpenExecutions row above.
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      // IN_PROGRESS (s2): "Concluir" plus both evidence actions, and exactly
      // one of each across the whole list — s1/s3 get neither.
      expect(find.widgetWithText(TextButton, 'Concluir'), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'Adicionar foto'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextButton, 'Adicionar observação'),
        findsOneWidget,
      );

      // PENDING (s3) and IN_PROGRESS (s2) both fall back to the scan icon;
      // only DONE (s1) gets the check icon.
      expect(find.byIcon(Icons.qr_code_scanner), findsNWidgets(2));

      // PENDING stop has a route-level entry point, not a per-stop button —
      // the single "Fazer check-in" button below the list.
      expect(
        find.widgetWithText(FilledButton, 'Fazer check-in'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tapping "Adicionar foto" captures, enqueues the photo and shows success',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressStopRoute()]),
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
          evidenceCapture: _FakeEvidenceCapture(
            // A real (1x1) PNG — the pending row renders as an Image.memory
            // thumbnail in the evidence list, which decodes eagerly.
            photo: CapturedPhoto(bytes: _onePixelPng, sha256: 'abc123'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Adicionar foto'));
      await tester.pumpAndSettle();

      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.kind, PendingOpKind.evidencePhoto);
      expect(rows.single.payload['execution_id'], 'exec-1');
      expect(rows.single.payload['sha256'], 'abc123');
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
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
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

  // NOTE (Etapa 6 Task 8): "failure snackbar when the photo/note upload
  // fails" tests were removed — the repository enqueues and returns, it no
  // longer awaits the upload, so an upload failure can't surface here. The
  // SyncWorker classifies and surfaces dispatch failures now
  // (sync_worker_test.dart); Task 10 adds the per-stop "blocked" indicator.

  testWidgets(
    'shows a failure snackbar when the camera itself throws (e.g. '
    'compression failed)',
    (tester) async {
      final evidenceApi = _FakeEvidenceApi();
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressStopRoute()]),
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
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
    'tapping "Adicionar observação" opens a dialog and "Salvar" enqueues '
    'the note',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressStopRoute()]),
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
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

      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.kind, PendingOpKind.evidenceNote);
      expect(rows.single.payload['text_body'], 'Sala trancada.');
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
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
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
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
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
            stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
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
            stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
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

  RouteSyncStatus statusOf({
    RouteSyncState state = RouteSyncState.idle,
    int pending = 0,
    int blocked = 0,
  }) => RouteSyncStatus(
    routeId: 'r1',
    state: state,
    pending: pending,
    blocked: blocked,
  );

  testWidgets(
    'a local IN_PROGRESS StopProgress overrides a server PENDING stop — the '
    'tile renders the in-progress affordances (Concluir + evidence)',
    (tester) async {
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressRoute()]),
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextButton, 'Concluir'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Adicionar foto'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    },
  );

  testWidgets(
    'two pending outbox rows render the "aguardando sincronização" banner and '
    '"Sincronizar agora" calls syncAll',
    (tester) async {
      final worker = _RecordingSyncWorker(
        statusStream: Stream<RouteSyncStatus>.value(statusOf(pending: 2)),
      );
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressRoute()]),
          syncWorker: worker,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('2 ações aguardando sincronização'),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Sincronizar agora'),
      );
      await tester.pumpAndSettle();
      expect(worker.syncAllCount, 1);
    },
  );

  testWidgets(
    'an idle status with nothing pending renders "Tudo sincronizado" and no '
    'waiting banner',
    (tester) async {
      final worker = _RecordingSyncWorker(
        statusStream: Stream<RouteSyncStatus>.value(statusOf()),
      );
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressRoute()]),
          syncWorker: worker,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tudo sincronizado'), findsOneWidget);
      expect(find.textContaining('aguardando sincronização'), findsNothing);
    },
  );

  testWidgets(
    'a blocked status renders the "Sincronização bloqueada" banner and '
    'tapping it pushes BlockedSyncScreen',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await store.enqueue(
        id: 'op-1',
        kind: PendingOpKind.checkIn,
        routeId: 'r1',
        payload: {'route_stop_id': 's1'},
      );
      await store.markBlocked('op-1', 'HTTP 422');
      final worker = _RecordingSyncWorker(
        statusStream: Stream<RouteSyncStatus>.value(
          statusOf(state: RouteSyncState.blocked, blocked: 1),
        ),
      );
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressRoute()]),
          syncWorker: worker,
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Sincronização bloqueada — toque para ver'),
        findsOneWidget,
      );
      await tester.tap(find.text('Sincronização bloqueada — toque para ver'));
      await tester.pumpAndSettle();
      expect(find.byType(BlockedSyncScreen), findsOneWidget);
    },
  );

  testWidgets(
    'a stop with a pending check-in row shows the "Pendente" chip; a stop '
    'with no rows shows none',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await store.enqueue(
        id: 'op-1',
        kind: PendingOpKind.checkIn,
        routeId: 'r1',
        payload: {'route_stop_id': 's1'},
      );
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
                RouteStopSummary(
                  id: 's2',
                  orderIndex: 2,
                  status: 'PENDING',
                  servicePointName: 'Sala 102',
                  latitude: -7.22,
                  longitude: -35.92,
                  pointType: 'REGULAR',
                ),
              ],
            ),
          ]),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pendente'), findsOneWidget);
      expect(find.text('Bloqueado'), findsNothing);
    },
  );

  testWidgets(
    'a stop with a pending evidence row (matched by its StopProgress '
    'executionId) shows the "Pendente" chip',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await store.enqueue(
        id: 'op-photo',
        kind: PendingOpKind.evidencePhoto,
        routeId: 'r1',
        payload: {'execution_id': 'exec-1'},
      );
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressStopRoute()]),
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pendente'), findsOneWidget);
    },
  );

  testWidgets(
    'a stop whose only outbox row is blocked shows the "Bloqueado" chip',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await store.enqueue(
        id: 'op-1',
        kind: PendingOpKind.checkIn,
        routeId: 'r1',
        payload: {'route_stop_id': 's1'},
      );
      await store.markBlocked('op-1', 'HTTP 422');
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressRoute()]),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bloqueado'), findsOneWidget);
      expect(find.text('Pendente'), findsNothing);
    },
  );

  testWidgets(
    'a stop with both a blocked and a pending row shows "Bloqueado" — '
    'blocked wins pending',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await store.enqueue(
        id: 'op-checkin',
        kind: PendingOpKind.checkIn,
        routeId: 'r1',
        payload: {'route_stop_id': 's1'},
      );
      await store.markBlocked('op-checkin', 'HTTP 422');
      await store.enqueue(
        id: 'op-photo',
        kind: PendingOpKind.evidencePhoto,
        routeId: 'r1',
        payload: {'execution_id': 'exec-1'},
      );
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressStopRoute()]),
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bloqueado'), findsOneWidget);
      expect(find.text('Pendente'), findsNothing);
    },
  );

  testWidgets(
    'the waiting banner uses the singular "ação" for a single pending row',
    (tester) async {
      final worker = _RecordingSyncWorker(
        statusStream: Stream<RouteSyncStatus>.value(statusOf(pending: 1)),
      );
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressRoute()]),
          syncWorker: worker,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 ação aguardando sincronização'), findsOneWidget);
    },
  );

  // --- Task 13: form fill step gates check-out ---------------------------

  FormSchema oneTextQuestionSchema() => const FormSchema(
    formVersionId: 'v1',
    questions: [
      FormQuestion(
        stableKey: 'k1',
        orderIndex: 0,
        prompt: 'Observação',
        type: QuestionType.text,
        required: true,
        options: [],
        contentHash: 'h1',
      ),
    ],
  );

  RouteSummary inProgressStopWithFormRoute() => _routeWith(
    status: 'IN_PROGRESS',
    startedAt: DateTime(2026, 8, 25, 8),
    stops: [
      RouteStopSummary(
        id: 's1',
        orderIndex: 1,
        status: 'IN_PROGRESS',
        servicePointName: 'Sala 101',
        latitude: -7.21,
        longitude: -35.91,
        pointType: 'REGULAR',
        form: oneTextQuestionSchema(),
      ),
    ],
  );

  testWidgets(
    'an IN_PROGRESS stop with a form and an incomplete draft disables '
    '"Concluir", shows "Preencher formulário" and the incomplete hint',
    (tester) async {
      final db = inMemoryDatabase();
      addTearDown(db.close);
      final formStore = DriftFormDraftStore(db);
      await formStore.snapshotFrom('exec-1', 's1', oneTextQuestionSchema());

      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressStopWithFormRoute()]),
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
          formDraftStore: formStore,
        ),
      );
      await tester.pumpAndSettle();

      final concluir = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Concluir'),
      );
      expect(concluir.onPressed, isNull);
      expect(
        find.widgetWithText(TextButton, 'Preencher formulário'),
        findsOneWidget,
      );
      expect(
        find.text('Preencha o formulário para concluir.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tapping "Preencher formulário" pushes FormScreen; completing the '
    'required question and returning enables "Concluir"',
    (tester) async {
      final db = inMemoryDatabase();
      addTearDown(db.close);
      final formStore = DriftFormDraftStore(db);
      await formStore.snapshotFrom('exec-1', 's1', oneTextQuestionSchema());

      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressStopWithFormRoute()]),
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
          formDraftStore: formStore,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(TextButton, 'Preencher formulário'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FormScreen), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'Tudo certo.');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Voltar'));
      await tester.pumpAndSettle();

      final concluir = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Concluir'),
      );
      expect(concluir.onPressed, isNotNull);
      expect(
        find.text('Preencha o formulário para concluir.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'an IN_PROGRESS stop with no form keeps "Concluir" enabled as before '
    'this task, with no "Preencher formulário" button',
    (tester) async {
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([inProgressStopRoute()]),
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
        ),
      );
      await tester.pumpAndSettle();

      final concluir = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Concluir'),
      );
      expect(concluir.onPressed, isNotNull);
      expect(
        find.widgetWithText(TextButton, 'Preencher formulário'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'checking in on a stop with a form snapshots its questions under the '
    'returned executionId',
    (tester) async {
      final db = inMemoryDatabase();
      addTearDown(db.close);
      final formStore = DriftFormDraftStore(db);
      final store = _InMemoryLocalWriteStore();
      // ExecutionRepository generates the executionId itself (spec Ruling
      // 4 — no server 201 to learn it from offline); a real StopProgressStore
      // captures whatever id it picks so the test can key its assertion on
      // the same value the snapshot was written under.
      final progressStore = _FakeStopProgressStore();
      final route = _routeWith(
        status: 'IN_PROGRESS',
        startedAt: DateTime(2026, 8, 25, 8),
        stops: [
          RouteStopSummary(
            id: 's1',
            orderIndex: 1,
            status: 'PENDING',
            servicePointName: 'Sala 101',
            latitude: -7.21,
            longitude: -35.91,
            pointType: 'REGULAR',
            form: oneTextQuestionSchema(),
          ),
        ],
      );
      await tester.pumpWidget(
        _screenWith(
          _StaticRouteRepository([route]),
          locationService: _FakeLocationService(),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
          formDraftStore: formStore,
          stopProgressStore: progressStore,
        ),
      );
      await tester.pumpAndSettle();

      await tapCheckInAndScan(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      final executionId = (await progressStore.progressFor('s1'))!.executionId;
      final items = await formStore.itemsFor(executionId);
      expect(items, hasLength(1));
      expect(items.single.stableKey, 'k1');
    },
  );
}
