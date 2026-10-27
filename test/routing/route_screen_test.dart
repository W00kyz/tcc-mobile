import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/appeals/appeal_api.dart';
import 'package:route_monitor/appeals/appeal_form_screen.dart';
import 'package:route_monitor/appeals/appeal_providers.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/evidence_capture.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/execution_repository.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/released_stop_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
import 'package:route_monitor/monitoring/location_mode.dart';
import 'package:route_monitor/monitoring/monitoring_api.dart';
import 'package:route_monitor/monitoring/monitoring_providers.dart';
import 'package:route_monitor/monitoring/notifications_screen.dart';
import 'package:route_monitor/monitoring/silence_watchdog.dart';
import 'package:route_monitor/routing/blocked_sync_screen.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/map_screen.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/route_screen.dart';
import 'package:route_monitor/sync/connectivity.dart';
import 'package:route_monitor/sync/stop_release.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/sync/sync_worker.dart';

import '../appeals/fake_appeal_api.dart';
import '../support/fake_connectivity.dart';
import '../support/fake_route_repository.dart';
import '../support/in_memory_database.dart';
import 'no_tiles_tile_provider.dart';

/// A [SyncWorker] that records every `syncRoute` kick and never drains — the
/// repository fires this fire-and-forget after each enqueue (spec Ruling 2);
/// RouteScreen tests only care that the enqueue happened, not the network.
class _RecordingSyncWorker implements SyncWorker {
  _RecordingSyncWorker({this.statusStream, this.drains});

  final Stream<RouteSyncStatus>? statusStream;

  /// When set, each `syncRoute` (and `syncAll`, for route `r1`) also
  /// delivers every unsynced row of that store — the server accepted them
  /// all. Null = the server never gets them.
  LocalWriteStore? drains;
  final List<String> syncedRoutes = [];
  final List<String> unblocked = [];
  int syncAllCount = 0;

  @override
  Future<void> syncRoute(String routeId) async {
    syncedRoutes.add(routeId);
    await _deliver(routeId);
  }

  @override
  Future<void> syncAll() async {
    syncAllCount++;
    await _deliver('r1');
  }

  Future<void> _deliver(String routeId) async {
    final store = drains;
    if (store == null) return;
    for (final row in await store.unsyncedForRoute(routeId)) {
      await store.markSynced(row.id);
    }
  }

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

/// Batch 1 of today's route, open: one PENDING stop.
final RouteSummary _openBatchRoute = routeWith(
  stops: [stopWith(id: 's1', servicePointName: 'Sala 101')],
);

/// A [FakeRouteRepository] whose `GET /routes/me` holds [route] (none yet
/// when null).
FakeRouteRepository _repositoryWith(RouteSummary? route) =>
    FakeRouteRepository(myDayWith(route));

/// In-memory [SyncMetaStore], so no test reaches the real Drift-backed
/// store.
class _InMemorySyncMetaStore implements SyncMetaStore {
  double? offset;

  @override
  Future<double?> getClockOffsetSeconds() async => offset;

  @override
  Future<void> setClockOffsetSeconds(double seconds) async => offset = seconds;
}

class _FakeLocationService implements LocationService {
  @override
  Future<Coordinates> getCurrentPosition({
    required LocationPurpose purpose,
  }) async => const Coordinates(latitude: -7.23, longitude: -35.88);
}

/// GPS is unavailable (e.g. a basement, RF29/RNF13) — every failure shape
/// GeolocatorLocationService can produce maps to the same "proceed without
/// GPS" behavior in RouteScreen, so a single StateError stands in for all.
class _FailingLocationService implements LocationService {
  @override
  Future<Coordinates> getCurrentPosition({
    required LocationPurpose purpose,
  }) async {
    throw StateError('no GPS signal');
  }
}

/// A stub [MonitoringApi] — the route screen's notification bell watches
/// `unreadCountProvider`, and navigating to `NotificationsScreen` watches
/// `notificationsProvider`; both must stay off the real Dio client under
/// flutter_test.
class _FakeMonitoringApi implements MonitoringApi {
  _FakeMonitoringApi({this.unread = 0});

  final int unread;

  @override
  Future<List<AppNotification>> fetchNotifications({int limit = 30}) async =>
      const [];

  @override
  Future<int> unreadCount() async => unread;

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> reportPosition({
    required String routeId,
    required double latitude,
    required double longitude,
    required DateTime reportedAt,
    double? accuracyM,
  }) async => throw UnimplementedError();
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
  }) async => (
    result: CheckOutResult(
      routeStopId: routeStopId ?? 's1',
      executionId: 'exec-1',
      checkedOutAt: DateTime.utc(2026, 8, 25, 8, 40),
      flags: const [],
    ),
    serverDate: null,
  );

  @override
  Future<void> reportImpediment({
    required String routeId,
    required String? routeStopId,
    required String scope,
    required String reason,
    required DateTime reportedAt,
    String? note,
  }) async => throw UnimplementedError();
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
  Future<void> markStopReleased(
    String id, {
    required String routeStopId,
    required String error,
  }) => throw UnimplementedError();

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
  String status = 'IN_PROGRESS',
  DateTime? startedAt,
}) => RouteSummary(
  id: 'r1',
  fieldWorkerName: 'João',
  routeDate: DateTime(2026, 8, 25),
  status: status,
  startedAt: startedAt,
  currentBatch: 1,
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
  String? apiBaseUrl,
  Session? session,
  MonitoringApi? monitoringApi,
  Connectivity? connectivity,
  PermissionPort? permissions,
  BackgroundAskStore? backgroundAsked,
  SilenceWatchdog? silenceWatchdog,
  AppealApi? appealApi,
  ReleasedStopStore? releasedStopStore,
}) {
  final resolvedMonitoringApi = monitoringApi ?? _FakeMonitoringApi();
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
  // Always overridden: the sync banner watches `routeSyncStatusProvider` on
  // every render now, and building the real `SyncWorker` reaches
  // `apiBaseUrlFromEnvironment()` (no `--dart-define` under flutter_test).
  final resolvedSyncWorker = syncWorker ?? _RecordingSyncWorker();
  // Always overridden: the app bar's appeals entry counts the contestable
  // points on every render, and the released-stop snackbar reads the
  // device's notices — never a real Dio client or the on-device database
  // (and no second in-memory one beside a test's own: drift warns).
  final resolvedReleasedStops = releasedStopStore ?? _NoReleasedStops();
  return ProviderScope(
    overrides: [
      routeRepositoryProvider.overrideWithValue(repository),
      monitoringApiProvider.overrideWithValue(resolvedMonitoringApi),
      appealApiProvider.overrideWithValue(appealApi ?? RecordingAppealApi()),
      releasedStopStoreProvider.overrideWithValue(resolvedReleasedStops),
      syncWorkerProvider.overrideWithValue(resolvedSyncWorker),
      locationServiceProvider.overrideWithValue(
        locationService ?? _FakeLocationService(),
      ),
      // Online unless a test says otherwise: the next-batch controller the
      // screen mounts must never reach the real connectivity_plus plugin.
      connectivityProvider.overrideWithValue(
        connectivity ?? FakeConnectivity(isOnline: true),
      ),
      stopProgressStoreProvider.overrideWithValue(resolvedOpenExecutions),
      evidenceApiProvider.overrideWithValue(resolvedEvidenceApi),
      localWriteStoreProvider.overrideWithValue(resolvedLocalStore),
      syncMetaStoreProvider.overrideWithValue(resolvedSyncMeta),
      // Never the real apiBaseUrlFromEnvironment() under flutter_test (no
      // --dart-define here) — a fixed value unless a test needs a specific
      // one (the synced-photo thumbnail URL/header test).
      apiBaseUrlProvider.overrideWithValue(apiBaseUrl ?? 'http://test-base'),
      // "Iniciar rota" settles the location mode first: never the real
      // permission_handler under flutter_test, and — unless a test is about
      // that flow — the "always" question already asked, so no dialog.
      permissionPortProvider.overrideWithValue(
        permissions ?? _FakePermissions(),
      ),
      backgroundAskStoreProvider.overrideWithValue(
        backgroundAsked ?? _InMemoryAskStore(asked: true),
      ),
      if (silenceWatchdog != null)
        silenceWatchdogProvider.overrideWithValue(silenceWatchdog),
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
            resolvedSyncWorker,
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
  testWidgets('shows the error state when the fetch fails', (tester) async {
    await tester.pumpWidget(
      _screenWith(
        FakeRouteRepository()
          ..fetchError = DioException(
            requestOptions: RequestOptions(path: '/routes/me'),
          ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.routeLoadError), findsOneWidget);
  });

  group('before the first batch', () {
    Finder startButton() =>
        find.widgetWithText(FilledButton, AppStrings.routeStartButton);

    /// No route yet; "Iniciar rota" hands out a one-stop batch.
    FakeRouteRepository startableRepository() {
      final repository = _repositoryWith(null);
      final firstBatch = routeWith(stops: [stopWith(id: 's1')]);
      repository.allocate = () {
        repository.day = myDayWith(firstBatch);
        return AllocationResult(route: firstBatch, poolEmpty: false);
      };
      return repository;
    }

    testWidgets('a non-service day says so and offers no start', (
      tester,
    ) async {
      await tester.pumpWidget(
        _screenWith(FakeRouteRepository(myDayWith(null, serviceDay: false))),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.routeNotServiceDay), findsOneWidget);
      expect(startButton(), findsNothing);
    });

    testWidgets(
      '"Iniciar rota" allocates from the current position and shows the '
      'batch under its header',
      (tester) async {
        final repository = _repositoryWith(null);
        final firstBatch = routeWith(
          stops: [
            stopWith(id: 's1', servicePointName: 'Sala 101'),
            stopWith(id: 's2', orderIndex: 2, servicePointName: 'Sala 102'),
          ],
        );
        repository.allocate = () {
          repository.day = myDayWith(firstBatch);
          return AllocationResult(route: firstBatch, poolEmpty: false);
        };
        await tester.pumpWidget(_screenWith(repository));
        await tester.pumpAndSettle();

        await tester.tap(startButton());
        await tester.pumpAndSettle();

        expect(repository.allocationCalls, ['start']);
        expect(repository.lastPosition, (lat: -7.23, lng: -35.88));
        expect(find.text(AppStrings.routeBatchHeader(1, 0)), findsOneWidget);
        expect(find.text('Sala 101'), findsOneWidget);
        expect(find.text('Sala 102'), findsOneWidget);
        expect(startButton(), findsNothing);
      },
    );

    testWidgets(
      'the first "Iniciar rota" explains and asks for "always" location',
      (tester) async {
        final permissions = _FakePermissions(grantsAlways: true);
        final asked = _InMemoryAskStore();
        final repository = startableRepository();
        await tester.pumpWidget(
          _screenWith(
            repository,
            permissions: permissions,
            backgroundAsked: asked,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(startButton());
        await tester.pumpAndSettle();
        expect(find.text(AppStrings.locationAlwaysRationale), findsOneWidget);
        expect(repository.allocationCalls, isEmpty);

        await tester.tap(find.text(AppStrings.locationPromptContinue));
        await tester.pumpAndSettle();

        expect(permissions.alwaysRequests, 1);
        expect(asked.asked, isTrue);
        expect(repository.allocationCalls, ['start']);
      },
    );

    testWidgets('a refused "always" leaves a one-time note, then starts', (
      tester,
    ) async {
      final repository = startableRepository();
      await tester.pumpWidget(
        _screenWith(repository, backgroundAsked: _InMemoryAskStore()),
      );
      await tester.pumpAndSettle();

      await tester.tap(startButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.locationPromptContinue));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.locationForegroundOnlyNote), findsOneWidget);
      await tester.tap(find.text(AppStrings.locationPromptUnderstood));
      await tester.pumpAndSettle();

      expect(repository.allocationCalls, ['start']);
    });

    testWidgets('a permission plugin failure never swallows the start', (
      tester,
    ) async {
      final repository = startableRepository();
      await tester.pumpWidget(
        _screenWith(repository, permissions: _ThrowingPermissions()),
      );
      await tester.pumpAndSettle();

      await tester.tap(startButton());
      await tester.pumpAndSettle();

      expect(repository.allocationCalls, ['start']);
    });

    testWidgets('offline, "Iniciar rota" asks for a connection', (
      tester,
    ) async {
      final repository = _repositoryWith(null);
      await tester.pumpWidget(
        _screenWith(repository, connectivity: FakeConnectivity()),
      );
      await tester.pumpAndSettle();

      await tester.tap(startButton());
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.routeStartOffline), findsOneWidget);
      expect(repository.allocationCalls, isEmpty);
    });

    final refusals = <String, (Exception, String)>{
      'outside the campus': (
        const OutsideCampusException(),
        AppStrings.routeOutsideCampus,
      ),
      'after the workday': (
        const WorkdayOverException(),
        AppStrings.routeWorkdayOver,
      ),
      'on a non-service day': (
        const NotAServiceDayException(),
        AppStrings.routeNotServiceDay,
      ),
      'with the route already done': (
        const RouteDoneException(),
        AppStrings.routeNoMorePoints,
      ),
      'with the privacy notice still owed (plain 403)': (
        DioException(
          requestOptions: RequestOptions(path: '/routes/start'),
          response: Response<Object>(
            requestOptions: RequestOptions(path: '/routes/start'),
            statusCode: 403,
          ),
        ),
        AppStrings.routeStartFailed,
      ),
    };
    for (final MapEntry(key: situation, value: (error, message))
        in refusals.entries) {
      testWidgets('"Iniciar rota" $situation shows "$message"', (tester) async {
        final repository = _repositoryWith(null)..allocate = () => throw error;
        await tester.pumpWidget(_screenWith(repository));
        await tester.pumpAndSettle();

        await tester.tap(startButton());
        await tester.pumpAndSettle();

        expect(find.text(message), findsOneWidget);
        expect(startButton(), findsOneWidget);
      });
    }

    testWidgets('an empty pool on "Iniciar rota" says there is nothing left', (
      tester,
    ) async {
      final done = routeWith(status: 'DONE', stops: const []);
      final repository = _repositoryWith(null);
      repository.allocate = () {
        repository.day = myDayWith(done);
        return AllocationResult(route: done, poolEmpty: true);
      };
      await tester.pumpWidget(_screenWith(repository));
      await tester.pumpAndSettle();

      await tester.tap(startButton());
      await tester.pumpAndSettle();

      // The snackbar and the finished-route state both say it.
      expect(find.text(AppStrings.routeNoMorePoints), findsNWidgets(2));
    });

    testWidgets(
      'a GPS failure on "Iniciar rota" shows the location snackbar and asks '
      'the server for nothing',
      (tester) async {
        final repository = _repositoryWith(null);
        await tester.pumpWidget(
          _screenWith(repository, locationService: _FailingLocationService()),
        );
        await tester.pumpAndSettle();

        await tester.tap(startButton());
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.routeLocationUnavailable), findsOneWidget);
        expect(repository.allocationCalls, isEmpty);
      },
    );
  });

  group('route states', () {
    testWidgets(
      'shows only the current batch under the done count of the whole day, a '
      'released stop as released and with no action',
      (tester) async {
        final route = routeWith(
          currentBatch: 2,
          stops: [
            stopWith(id: 'a', status: 'DONE', servicePointName: 'Sala Velha'),
            stopWith(
              id: 'b',
              orderIndex: 2,
              batchNumber: 2,
              status: 'RELEASED',
              releaseReason: 'IMPEDIMENT',
              servicePointName: 'Sala Impedida',
            ),
            stopWith(
              id: 'c',
              orderIndex: 3,
              batchNumber: 2,
              servicePointName: 'Sala Nova',
            ),
          ],
        );
        await tester.pumpWidget(_screenWith(_repositoryWith(route)));
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.routeBatchHeader(2, 1)), findsOneWidget);
        expect(find.text('Lote 2 · 1 ponto feito hoje'), findsOneWidget);
        expect(find.text('Sala Nova'), findsOneWidget);
        expect(find.text('Sala Velha'), findsNothing);
        expect(find.text('Sala Impedida'), findsOneWidget);
        expect(
          find.text(
            AppStrings.routeStopReleased(
              AppStrings.releaseReasonLabel('IMPEDIMENT'),
            ),
          ),
          findsOneWidget,
        );
        // Only "Sala Nova" can still be signalled.
        expect(
          find.widgetWithText(
            TextButton,
            AppStrings.routeSignalImpossibilityButton,
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a paused route explains why and "Iniciar rota" resumes it',
      (tester) async {
        final paused = routeWith(
          status: 'PAUSED',
          stops: [
            stopWith(
              id: 's1',
              status: 'RELEASED',
              releaseReason: 'LEFT_CAMPUS',
              servicePointName: 'Sala 101',
            ),
          ],
        );
        final repository = _repositoryWith(paused);
        await tester.pumpWidget(_screenWith(repository));
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.routePausedTitle), findsOneWidget);
        expect(
          find.text(
            AppStrings.routePausedReason(
              AppStrings.releaseReasonLabel('LEFT_CAMPUS'),
            ),
          ),
          findsOneWidget,
        );
        expect(find.text('Sala 101'), findsNothing);
        expect(
          find.widgetWithText(
            TextButton,
            AppStrings.routeSignalImpossibilityButton,
          ),
          findsNothing,
        );

        await tester.tap(
          find.widgetWithText(FilledButton, AppStrings.routeStartButton),
        );
        await tester.pumpAndSettle();

        expect(repository.allocationCalls, ['start']);
      },
    );

    Finder checkAgainButton() =>
        find.widgetWithText(FilledButton, AppStrings.routeCheckAgainButton);

    testWidgets('a finished route says there are no points now and offers to '
        'check again', (tester) async {
      final done = routeWith(
        status: 'DONE',
        stops: [stopWith(id: 's1', status: 'DONE')],
      );
      await tester.pumpWidget(_screenWith(_repositoryWith(done)));
      await tester.pumpAndSettle();

      expect(find.text('Não há mais pontos agora.'), findsOneWidget);
      expect(checkAgainButton(), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, AppStrings.routeStartButton),
        findsNothing,
      );
    });

    testWidgets('"Verificar de novo" takes the points released since', (
      tester,
    ) async {
      // Spec §1: a colleague's point went back to the pool after this route
      // ran out; asking again reopens the route with it.
      final done = routeWith(
        status: 'DONE',
        stops: [stopWith(id: 's1', status: 'DONE')],
      );
      final reopened = routeWith(
        currentBatch: 2,
        stops: [
          stopWith(id: 's1', status: 'DONE'),
          stopWith(
            id: 's2',
            orderIndex: 2,
            batchNumber: 2,
            servicePointName: 'Sala 205',
          ),
        ],
      );
      final repository = _repositoryWith(done);
      repository.allocate = () {
        repository.day = myDayWith(reopened);
        return AllocationResult(route: reopened, poolEmpty: false);
      };
      await tester.pumpWidget(_screenWith(repository));
      await tester.pumpAndSettle();

      await tester.tap(checkAgainButton());
      await tester.pumpAndSettle();

      expect(repository.allocationCalls, ['start']);
      expect(find.text('Sala 205'), findsOneWidget);
      expect(checkAgainButton(), findsNothing);
    });

    testWidgets('"Verificar de novo" with the pool still empty says so', (
      tester,
    ) async {
      final done = routeWith(status: 'DONE', stops: const []);
      final repository = _repositoryWith(done)
        ..allocate = () => AllocationResult(route: done, poolEmpty: true);
      await tester.pumpWidget(_screenWith(repository));
      await tester.pumpAndSettle();

      await tester.tap(checkAgainButton());
      await tester.pumpAndSettle();

      expect(repository.allocationCalls, ['start']);
      // The snackbar and the finished-route state both say it.
      expect(find.text(AppStrings.routeNoMorePoints), findsNWidgets(2));
      expect(checkAgainButton(), findsOneWidget);
    });
  });

  testWidgets('shows the stop order index', (tester) async {
    await tester.pumpWidget(_screenWith(_repositoryWith(_openBatchRoute)));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(CircleAvatar, '1'), findsOneWidget);
  });

  testWidgets('renders the travel-from-previous distance and time', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screenWith(
        _repositoryWith(
          _routeWith(
            stops: const [
              RouteStopSummary(
                id: 's1',
                orderIndex: 1,
                batchNumber: 1,
                status: 'PENDING',
                servicePointName: 'Sala 101',
                latitude: -7.21,
                longitude: -35.91,
              ),
              RouteStopSummary(
                id: 's2',
                orderIndex: 2,
                batchNumber: 1,
                status: 'PENDING',
                servicePointName: 'Sala 102',
                latitude: -7.22,
                longitude: -35.92,
                distanceFromPrevM: 120,
                durationFromPrevS: 180,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('120 m'), findsOneWidget);
    expect(find.textContaining('3 min'), findsOneWidget);
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
          routeRepositoryProvider.overrideWithValue(
            _repositoryWith(_openBatchRoute),
          ),
          connectivityProvider.overrideWithValue(FakeConnectivity()),
          monitoringApiProvider.overrideWithValue(_FakeMonitoringApi()),
          syncMetaStoreProvider.overrideWithValue(_InMemorySyncMetaStore()),
          syncWorkerProvider.overrideWithValue(_RecordingSyncWorker()),
          stopProgressStoreProvider.overrideWithValue(_NoopStopProgressStore()),
          localWriteStoreProvider.overrideWithValue(_InMemoryLocalWriteStore()),
          // The appeals badge reads both: never the network or the device DB.
          appealApiProvider.overrideWithValue(RecordingAppealApi()),
          releasedStopStoreProvider.overrideWithValue(_NoReleasedStops()),
        ],
        child: MaterialApp(
          home: RouteScreen(mapTileProvider: NoTilesTileProvider()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(FilledButton, AppStrings.routeViewMapButton),
      findsOneWidget,
    );

    await tester.tap(
      find.widgetWithText(FilledButton, AppStrings.routeViewMapButton),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.text(AppStrings.mapAppBarTitle), findsOneWidget);
  });

  testWidgets(
    'shows the check-in button when the route is in progress with a '
    'pending stop',
    (tester) async {
      await tester.pumpWidget(
        _screenWith(
          _repositoryWith(
            _routeWith(
              startedAt: DateTime(2026, 8, 25, 8),
              stops: const [
                RouteStopSummary(
                  id: 's1',
                  orderIndex: 1,
                  batchNumber: 1,
                  status: 'PENDING',
                  servicePointName: 'Sala 101',
                  latitude: -7.21,
                  longitude: -35.91,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(FilledButton, AppStrings.routeCheckInButton),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'hides the check-in button when every stop is already done',
    (tester) async {
      await tester.pumpWidget(
        _screenWith(
          _repositoryWith(
            _routeWith(
              startedAt: DateTime(2026, 8, 25, 8),
              stops: const [
                RouteStopSummary(
                  id: 's1',
                  orderIndex: 1,
                  batchNumber: 1,
                  status: 'DONE',
                  servicePointName: 'Sala 101',
                  latitude: -7.21,
                  longitude: -35.91,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(FilledButton, AppStrings.routeCheckInButton),
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
          _repositoryWith(
            _routeWith(
              startedAt: DateTime(2026, 8, 25, 8),
              stops: const [
                RouteStopSummary(
                  id: 's1',
                  orderIndex: 1,
                  batchNumber: 1,
                  status: 'IN_PROGRESS',
                  servicePointName: 'Sala 101',
                  latitude: -7.21,
                  longitude: -35.91,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(FilledButton, AppStrings.routeCheckInButton),
        findsNothing,
      );
    },
  );

  RouteSummary inProgressRoute() => _routeWith(
    startedAt: DateTime(2026, 8, 25, 8),
    stops: const [
      RouteStopSummary(
        id: 's1',
        orderIndex: 1,
        batchNumber: 1,
        status: 'PENDING',
        servicePointName: 'Sala 101',
        latitude: -7.21,
        longitude: -35.91,
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
    await tester.tap(
      find.widgetWithText(FilledButton, AppStrings.routeCheckInButton),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ScanScreen), findsOneWidget);
    final scanScreenContext = tester.element(find.byType(ScanScreen));
    Navigator.of(scanScreenContext).pop(rawValue);
  }

  Future<void> tapConcluirAndScan(WidgetTester tester, String rawValue) async {
    await tester.tap(
      find.widgetWithText(TextButton, AppStrings.routeConcludeButton),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ScanScreen), findsOneWidget);
    final scanScreenContext = tester.element(find.byType(ScanScreen));
    Navigator.of(scanScreenContext).pop(rawValue);
  }

  RouteSummary inProgressStopRoute() => _routeWith(
    startedAt: DateTime(2026, 8, 25, 8),
    stops: const [
      RouteStopSummary(
        id: 's1',
        orderIndex: 1,
        batchNumber: 1,
        status: 'IN_PROGRESS',
        servicePointName: 'Sala 101',
        latitude: -7.21,
        longitude: -35.91,
      ),
    ],
  );

  testWidgets(
    'runs the check-in flow end-to-end: scans, checks in and shows success',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await tester.pumpWidget(
        _screenWith(
          _repositoryWith(inProgressRoute()),
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
      expect(find.text(AppStrings.routeCheckInDone), findsOneWidget);
    },
  );

  testWidgets(
    'does nothing when the scan screen is popped without a value',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await tester.pumpWidget(
        _screenWith(
          _repositoryWith(inProgressRoute()),
          locationService: _FakeLocationService(),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(FilledButton, AppStrings.routeCheckInButton),
      );
      await tester.pumpAndSettle();
      final scanScreenContext = tester.element(find.byType(ScanScreen));
      Navigator.of(scanScreenContext).pop();
      await tester.pumpAndSettle();

      expect(await store.unsyncedForRoute('r1'), isEmpty);
      expect(
        find.widgetWithText(FilledButton, AppStrings.routeCheckInButton),
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
          _repositoryWith(inProgressRoute()),
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
    startedAt: DateTime(2026, 8, 25, 8),
    stops: const [
      RouteStopSummary(
        id: 's1',
        orderIndex: 1,
        batchNumber: 1,
        status: 'PENDING',
        servicePointName: 'Sala 101',
        latitude: -7.23,
        longitude: -35.88,
      ),
      RouteStopSummary(
        id: 's2',
        orderIndex: 2,
        batchNumber: 1,
        status: 'PENDING',
        servicePointName: 'Sala 102',
        // ~2.5 km away — well outside the 50 m check radius.
        latitude: -7.25,
        longitude: -35.90,
      ),
    ],
  );

  RouteSummary twoRoomsInRadiusRoute() => _routeWith(
    startedAt: DateTime(2026, 8, 25, 8),
    stops: const [
      RouteStopSummary(
        id: 's1',
        orderIndex: 1,
        batchNumber: 1,
        status: 'PENDING',
        servicePointName: 'Sala 101',
        latitude: -7.23,
        longitude: -35.88,
      ),
      RouteStopSummary(
        id: 's2',
        orderIndex: 2,
        batchNumber: 1,
        status: 'PENDING',
        servicePointName: 'Sala 102',
        // ~11 m from the GPS fix — inside the radius, but farther than s1.
        latitude: -7.2301,
        longitude: -35.88,
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
          _repositoryWith(oneRoomInRadiusRoute()),
          locationService: _FakeLocationService(),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      await tapCheckInAndScan(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.roomPickerPrompt),
        findsNothing,
      );
      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.kind, PendingOpKind.checkIn);
      expect(rows.single.payload['route_stop_id'], 's1');
      expect(find.text(AppStrings.routeCheckInDone), findsOneWidget);
    },
  );

  testWidgets(
    'check-in with two pending stops in radius shows the picker (nearest '
    'pre-selected); choosing the second enqueues its routeStopId',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await tester.pumpWidget(
        _screenWith(
          _repositoryWith(twoRoomsInRadiusRoute()),
          locationService: _FakeLocationService(),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      await tapCheckInAndScan(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.roomPickerPrompt),
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
      expect(find.text(AppStrings.routeCheckInDone), findsOneWidget);
    },
  );

  testWidgets(
    'dismissing the room picker enqueues nothing and shows no snackbar',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await tester.pumpWidget(
        _screenWith(
          _repositoryWith(twoRoomsInRadiusRoute()),
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
      expect(find.text(AppStrings.routeCheckInDone), findsNothing);
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
          _repositoryWith(inProgressRoute()),
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
        find.text(AppStrings.roomPickerPrompt),
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
      await tester.pumpWidget(_screenWith(_repositoryWith(_openBatchRoute)));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TextButton, AppStrings.routeConcludeButton),
        findsNothing,
      );
    },
  );

  group('the silence clock (spec §7.3)', () {
    final t0 = DateTime.utc(2026, 10, 20, 8);
    late DateTime now;
    late SilenceWatchdog watchdog;

    setUp(() {
      now = t0;
      watchdog = SilenceWatchdog(
        clock: () => now,
        scheduler: _NoopScheduler(),
        warningMinutes: 30,
        releaseMinutes: 45,
      )..startWatching();
    });

    // The server counts a scan only once it arrives (by its `scanned_at`):
    // a check-in written offline, e.g. underground, must not quiet the
    // app's warning. The sync delivery reports it (sync_worker_test.dart).
    testWidgets('a check-in written locally does not reset the clock', (
      tester,
    ) async {
      await tester.pumpWidget(
        _screenWith(
          _repositoryWith(inProgressRoute()),
          executionApi: _FakeExecutionApi(),
          silenceWatchdog: watchdog,
        ),
      );
      await tester.pumpAndSettle();
      now = t0.add(const Duration(minutes: 29));

      await tapCheckInAndScan(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      now = t0.add(const Duration(minutes: 31));
      expect(watchdog.currentWarning(), isNotNull);
    });

    testWidgets('a check-out written locally does not reset the clock', (
      tester,
    ) async {
      await tester.pumpWidget(
        _screenWith(
          _repositoryWith(inProgressStopRoute()),
          executionApi: _FakeExecutionApi(),
          silenceWatchdog: watchdog,
        ),
      );
      await tester.pumpAndSettle();
      now = t0.add(const Duration(minutes: 29));

      await tapConcluirAndScan(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      now = t0.add(const Duration(minutes: 31));
      expect(watchdog.currentWarning(), isNotNull);
    });

    testWidgets('a silent worker sees the warning banner', (tester) async {
      now = t0.add(const Duration(minutes: 32));
      await tester.pumpWidget(
        _screenWith(
          _repositoryWith(inProgressRoute()),
          silenceWatchdog: watchdog,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.silenceWarning(32, 13)), findsOneWidget);
    });
  });

  testWidgets(
    'runs the check-out flow end-to-end: scans, checks out, reloads the '
    'day and shows success',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      final repository = _repositoryWith(inProgressStopRoute());
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
      expect(find.text(AppStrings.routeCheckOutDone), findsOneWidget);
      expect(repository.fetchCount, 2);
    },
  );

  testWidgets(
    'hides the evidence buttons for an IN_PROGRESS stop with no '
    'OpenExecutions row (Ruling 17 cold-start gap)',
    (tester) async {
      await tester.pumpWidget(
        _screenWith(_repositoryWith(inProgressStopRoute())),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.routeAddPhotoButton), findsNothing);
      expect(find.text(AppStrings.routeAddNoteButton), findsNothing);
    },
  );

  testWidgets(
    'shows the evidence buttons for an IN_PROGRESS stop once its '
    'OpenExecutions row resolves',
    (tester) async {
      await tester.pumpWidget(
        _screenWith(
          _repositoryWith(inProgressStopRoute()),
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TextButton, AppStrings.routeAddPhotoButton),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextButton, AppStrings.routeAddNoteButton),
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
          _repositoryWith(
            _routeWith(
              startedAt: DateTime(2026, 8, 25, 8),
              stops: const [
                RouteStopSummary(
                  id: 's1',
                  orderIndex: 1,
                  batchNumber: 1,
                  status: 'DONE',
                  servicePointName: 'Sala 101',
                  latitude: -7.21,
                  longitude: -35.91,
                ),
                RouteStopSummary(
                  id: 's2',
                  orderIndex: 2,
                  batchNumber: 1,
                  status: 'IN_PROGRESS',
                  servicePointName: 'Sala 102',
                  latitude: -7.22,
                  longitude: -35.92,
                ),
                RouteStopSummary(
                  id: 's3',
                  orderIndex: 3,
                  batchNumber: 1,
                  status: 'PENDING',
                  servicePointName: 'Sala 103',
                  latitude: -7.23,
                  longitude: -35.93,
                ),
              ],
            ),
          ),
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
      expect(
        find.widgetWithText(TextButton, AppStrings.routeConcludeButton),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextButton, AppStrings.routeAddPhotoButton),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextButton, AppStrings.routeAddNoteButton),
        findsOneWidget,
      );

      // PENDING (s3) and IN_PROGRESS (s2) both fall back to the scan icon;
      // only DONE (s1) gets the check icon.
      expect(find.byIcon(Icons.qr_code_scanner), findsNWidgets(2));

      // PENDING stop has a route-level entry point, not a per-stop button —
      // the single "Fazer check-in" button below the list.
      expect(
        find.widgetWithText(FilledButton, AppStrings.routeCheckInButton),
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
          _repositoryWith(inProgressStopRoute()),
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

      await tester.tap(
        find.widgetWithText(TextButton, AppStrings.routeAddPhotoButton),
      );
      await tester.pumpAndSettle();

      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.kind, PendingOpKind.evidencePhoto);
      expect(rows.single.payload['execution_id'], 'exec-1');
      expect(rows.single.payload['sha256'], 'abc123');
      expect(find.text(AppStrings.routePhotoAdded), findsOneWidget);
    },
  );

  testWidgets(
    'does nothing when the field worker cancels the camera (takePhoto '
    'returns null)',
    (tester) async {
      final evidenceApi = _FakeEvidenceApi();
      await tester.pumpWidget(
        _screenWith(
          _repositoryWith(inProgressStopRoute()),
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
          executionApi: _FakeExecutionApi(),
          evidenceApi: evidenceApi,
          evidenceCapture: _FakeEvidenceCapture(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(TextButton, AppStrings.routeAddPhotoButton),
      );
      await tester.pumpAndSettle();

      expect(evidenceApi.uploadedPhotoExecutionIds, isEmpty);
      expect(find.text(AppStrings.routePhotoAdded), findsNothing);
      expect(
        find.text(AppStrings.routePhotoAddError),
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
          _repositoryWith(inProgressStopRoute()),
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
          executionApi: _FakeExecutionApi(),
          evidenceApi: evidenceApi,
          evidenceCapture: _FakeEvidenceCapture(
            error: StateError('Photo compression failed for "x.jpg".'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(TextButton, AppStrings.routeAddPhotoButton),
      );
      await tester.pumpAndSettle();

      expect(evidenceApi.uploadedPhotoExecutionIds, isEmpty);
      expect(find.text(AppStrings.routePhotoAddError), findsOneWidget);
    },
  );

  testWidgets(
    'tapping "Adicionar observação" opens a dialog and "Salvar" enqueues '
    'the note',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await tester.pumpWidget(
        _screenWith(
          _repositoryWith(inProgressStopRoute()),
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(TextButton, AppStrings.routeAddNoteButton),
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
      expect(find.text(AppStrings.routeNoteAdded), findsOneWidget);
    },
  );

  testWidgets(
    'cancelling the note dialog uploads nothing',
    (tester) async {
      final evidenceApi = _FakeEvidenceApi();
      await tester.pumpWidget(
        _screenWith(
          _repositoryWith(inProgressStopRoute()),
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
          evidenceApi: evidenceApi,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(TextButton, AppStrings.routeAddNoteButton),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'not saved');
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await tester.pumpAndSettle();

      expect(evidenceApi.uploadedNoteTexts, isEmpty);
      expect(find.text(AppStrings.routeNoteAdded), findsNothing);
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
          _repositoryWith(inProgressStopRoute()),
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
          evidenceApi: evidenceApi,
          localWriteStore: localStore,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sala trancada.'), findsOneWidget);
      expect(find.text(AppStrings.routeEvidencePhotoLabel), findsOneWidget);
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
            _repositoryWith(inProgressStopRoute()),
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
            _repositoryWith(inProgressStopRoute()),
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
          _repositoryWith(inProgressRoute()),
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TextButton, AppStrings.routeConcludeButton),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextButton, AppStrings.routeAddPhotoButton),
        findsOneWidget,
      );
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
          _repositoryWith(inProgressRoute()),
          syncWorker: worker,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.routePendingSync(2)),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(FilledButton, AppStrings.routeSyncNowButton),
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
          _repositoryWith(inProgressRoute()),
          syncWorker: worker,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.routeAllSynced), findsOneWidget);
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
          _repositoryWith(inProgressRoute()),
          syncWorker: worker,
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.routeSyncBlockedBanner),
        findsOneWidget,
      );
      await tester.tap(find.text(AppStrings.routeSyncBlockedBanner));
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
          _repositoryWith(
            _routeWith(
              startedAt: DateTime(2026, 8, 25, 8),
              stops: const [
                RouteStopSummary(
                  id: 's1',
                  orderIndex: 1,
                  batchNumber: 1,
                  status: 'PENDING',
                  servicePointName: 'Sala 101',
                  latitude: -7.21,
                  longitude: -35.91,
                ),
                RouteStopSummary(
                  id: 's2',
                  orderIndex: 2,
                  batchNumber: 1,
                  status: 'PENDING',
                  servicePointName: 'Sala 102',
                  latitude: -7.22,
                  longitude: -35.92,
                ),
              ],
            ),
          ),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.routeChipPending), findsOneWidget);
      expect(find.text(AppStrings.routeChipBlocked), findsNothing);
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
          _repositoryWith(inProgressStopRoute()),
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.routeChipPending), findsOneWidget);
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
          _repositoryWith(inProgressRoute()),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.routeChipBlocked), findsOneWidget);
      expect(find.text(AppStrings.routeChipPending), findsNothing);
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
          _repositoryWith(inProgressStopRoute()),
          stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.routeChipBlocked), findsOneWidget);
      expect(find.text(AppStrings.routeChipPending), findsNothing);
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
          _repositoryWith(inProgressRoute()),
          syncWorker: worker,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.routePendingSync(1)), findsOneWidget);
    },
  );

  testWidgets('an IN_PROGRESS stop offers "Concluir"', (tester) async {
    await tester.pumpWidget(
      _screenWith(
        _repositoryWith(inProgressStopRoute()),
        stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
      ),
    );
    await tester.pumpAndSettle();

    final concluir = tester.widget<TextButton>(
      find.widgetWithText(TextButton, AppStrings.routeConcludeButton),
    );
    expect(concluir.onPressed, isNotNull);
  });

  // --- Task 10: "Sinalizar impossibilidade" -----------------------------

  RouteSummary inProgressStopWithTwoPendingRoute() => _routeWith(
    startedAt: DateTime(2026, 8, 25, 8),
    stops: const [
      RouteStopSummary(
        id: 's1',
        orderIndex: 1,
        batchNumber: 1,
        status: 'IN_PROGRESS',
        servicePointName: 'Sala 101',
        latitude: -7.21,
        longitude: -35.91,
      ),
      RouteStopSummary(
        id: 's2',
        orderIndex: 2,
        batchNumber: 1,
        status: 'PENDING',
        servicePointName: 'Sala 102',
        latitude: -7.22,
        longitude: -35.92,
      ),
      RouteStopSummary(
        id: 's3',
        orderIndex: 3,
        batchNumber: 1,
        status: 'PENDING',
        servicePointName: 'Sala 103',
        latitude: -7.23,
        longitude: -35.93,
      ),
    ],
  );

  testWidgets(
    'tapping "Sinalizar impossibilidade" on an IN_PROGRESS stop, picking a '
    'reason and confirming enqueues an impediment row scoped to that stop',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await tester.pumpWidget(
        _screenWith(
          _repositoryWith(inProgressStopRoute()),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(
          TextButton,
          AppStrings.routeSignalImpossibilityButton,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.impedimentReasonAccessBlocked),
        findsOneWidget,
      );
      expect(find.text('Não consigo fazer este ponto'), findsOneWidget);
      // Offered even on the last stop: "can't go on today" is how the worker
      // ends the day — a STOP impediment there would pull the next batch.
      expect(find.text('Não consigo continuar hoje'), findsOneWidget);

      // Regression: the note field is capped at the backend `note` column
      // (`String(500)`) so an over-long note can't poison the route sync queue.
      expect(tester.widget<TextField>(find.byType(TextField)).maxLength, 500);

      await tester.tap(find.text(AppStrings.impedimentReasonSiteRefusal));
      await tester.enterText(find.byType(TextField), 'Portão fechado.');
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();

      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.kind, PendingOpKind.impediment);
      expect(rows.single.payload['scope'], 'STOP');
      expect(rows.single.payload['route_stop_id'], 's1');
      expect(rows.single.payload['reason'], 'SITE_REFUSAL');
      expect(rows.single.payload['note'], 'Portão fechado.');
      expect(find.text(AppStrings.routeImpedimentReported), findsOneWidget);
    },
  );

  testWidgets(
    'with two or more PENDING stops left, flipping the "resto da rota" switch '
    'enqueues a ROUTE_REMAINDER impediment with a null route_stop_id',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await tester.pumpWidget(
        _screenWith(
          _repositoryWith(inProgressStopWithTwoPendingRoute()),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      // s1 (IN_PROGRESS) plus s2/s3 (PENDING) each carry the action now — the
      // first is s1, the stop this report is about.
      await tester.tap(
        find
            .widgetWithText(
              TextButton,
              AppStrings.routeSignalImpossibilityButton,
            )
            .first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.impedimentReasonHealthIssue));
      await tester.tap(find.text(AppStrings.impedimentRemainderSwitch));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();

      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.payload['scope'], 'ROUTE_REMAINDER');
      expect(rows.single.payload['route_stop_id'], isNull);
      expect(rows.single.payload['reason'], 'HEALTH_ISSUE');
      expect(rows.single.payload['note'], isNull);
    },
  );

  testWidgets(
    'cancelling the impediment dialog enqueues nothing',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await tester.pumpWidget(
        _screenWith(
          _repositoryWith(inProgressStopRoute()),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(
          TextButton,
          AppStrings.routeSignalImpossibilityButton,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await tester.pumpAndSettle();

      expect(await store.unsyncedForRoute('r1'), isEmpty);
      expect(find.text(AppStrings.routeImpedimentReported), findsNothing);
    },
  );

  RouteSummary pendingStopOnInProgressRoute() => _routeWith(
    startedAt: DateTime(2026, 8, 25, 8),
    stops: const [
      RouteStopSummary(
        id: 's1',
        orderIndex: 1,
        batchNumber: 1,
        status: 'PENDING',
        servicePointName: 'Sala 101',
        latitude: -7.21,
        longitude: -35.91,
      ),
    ],
  );

  testWidgets(
    'tapping "Sinalizar impossibilidade" on a not-yet-reached (PENDING) stop '
    'enqueues a STOP-scoped impediment for that stop — a worker who cannot '
    'reach the stop to scan the QR must still be able to signal it',
    (tester) async {
      final store = _InMemoryLocalWriteStore();
      await tester.pumpWidget(
        _screenWith(
          _repositoryWith(pendingStopOnInProgressRoute()),
          executionApi: _FakeExecutionApi(),
          localWriteStore: store,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(
          TextButton,
          AppStrings.routeSignalImpossibilityButton,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.impedimentReasonAccessBlocked));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();

      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.kind, PendingOpKind.impediment);
      expect(rows.single.payload['scope'], 'STOP');
      expect(rows.single.payload['route_stop_id'], 's1');
      expect(find.text(AppStrings.routeImpedimentReported), findsOneWidget);
    },
  );

  group('next batch', () {
    RouteSummary lastStopInProgress() => routeWith(
      stops: [
        stopWith(id: 's1', status: 'IN_PROGRESS', servicePointName: 'Sala 101'),
      ],
    );

    RouteSummary secondBatch() => routeWith(
      currentBatch: 2,
      stops: [
        stopWith(id: 's1', status: 'DONE', servicePointName: 'Sala 101'),
        stopWith(
          id: 's2',
          orderIndex: 2,
          batchNumber: 2,
          servicePointName: 'Sala 202',
        ),
      ],
    );

    void handOutSecondBatch(FakeRouteRepository repository) {
      repository.allocate = () {
        repository.day = myDayWith(secondBatch());
        return AllocationResult(route: secondBatch(), poolEmpty: false);
      };
    }

    testWidgets(
      'checking out the last open stop delivers it and pulls the next batch',
      (tester) async {
        final store = _InMemoryLocalWriteStore();
        final repository = _repositoryWith(lastStopInProgress());
        handOutSecondBatch(repository);
        await tester.pumpWidget(
          _screenWith(
            repository,
            executionApi: _FakeExecutionApi(),
            localWriteStore: store,
            stopProgressStore: _FakeStopProgressStore({'s1': 'exec-1'}),
            syncWorker: _RecordingSyncWorker(drains: store),
          ),
        );
        await tester.pumpAndSettle();
        expect(repository.allocationCalls, isEmpty);

        await tapConcluirAndScan(tester, 'v1.floor.1.sig');
        await tester.pumpAndSettle();

        expect(repository.allocationCalls, ['nextBatch:r1']);
        expect(await store.unsyncedForRoute('r1'), isEmpty);
        expect(find.text(AppStrings.routeBatchHeader(2, 1)), findsOneWidget);
        expect(find.text('Sala 202'), findsOneWidget);
      },
    );

    testWidgets(
      'offline, a finished batch shows the reconnect banner and pulls the '
      'next batch once the connection is back',
      (tester) async {
        final connectivity = FakeConnectivity();
        addTearDown(connectivity.dispose);
        final progress = _FakeStopProgressStore({'s1': 'exec-1'});
        await progress.markDone('s1');
        final repository = _repositoryWith(lastStopInProgress());
        handOutSecondBatch(repository);
        await tester.pumpWidget(
          _screenWith(
            repository,
            connectivity: connectivity,
            stopProgressStore: progress,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.routeNextBatchOffline), findsOneWidget);
        expect(repository.allocationCalls, isEmpty);

        connectivity.goOnline();
        await tester.pumpAndSettle();

        expect(repository.allocationCalls, ['nextBatch:r1']);
        expect(find.text(AppStrings.routeNextBatchOffline), findsNothing);
        expect(find.text('Sala 202'), findsOneWidget);
      },
    );
  });

  group('next batch, other triggers', () {
    RouteSummary secondBatch() => routeWith(
      currentBatch: 2,
      stops: [
        stopWith(id: 's1', status: 'DONE', servicePointName: 'Sala 101'),
        stopWith(
          id: 's2',
          orderIndex: 2,
          batchNumber: 2,
          servicePointName: 'Sala 202',
        ),
      ],
    );

    void handOutSecondBatch(FakeRouteRepository repository) {
      repository.allocate = () {
        repository.day = myDayWith(secondBatch());
        return AllocationResult(route: secondBatch(), poolEmpty: false);
      };
    }

    testWidgets(
      'an impediment on the last open stop reloads the day once it synced, '
      'and the released stop lets the next batch in',
      (tester) async {
        final store = _InMemoryLocalWriteStore();
        final repository = _repositoryWith(
          routeWith(
            stops: [stopWith(id: 's1', servicePointName: 'Sala 101')],
          ),
        );
        handOutSecondBatch(repository);
        await tester.pumpWidget(
          _screenWith(
            repository,
            executionApi: _FakeExecutionApi(),
            localWriteStore: store,
            syncWorker: _RecordingSyncWorker(drains: store),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.widgetWithText(
            TextButton,
            AppStrings.routeSignalImpossibilityButton,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(AppStrings.impedimentReasonAccessBlocked));
        await tester.pumpAndSettle();
        // What the server reports once it has the impediment.
        repository.day = myDayWith(
          routeWith(
            stops: [
              stopWith(
                id: 's1',
                status: 'RELEASED',
                releaseReason: 'IMPEDIMENT',
                servicePointName: 'Sala 101',
              ),
            ],
          ),
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
        await tester.pumpAndSettle();

        expect(repository.allocationCalls, ['nextBatch:r1']);
        expect(find.text('Sala 202'), findsOneWidget);
      },
    );

    testWidgets(
      '"Sincronizar agora" drains the outbox and then re-runs the pull that '
      'was waiting on it',
      (tester) async {
        final store = _InMemoryLocalWriteStore();
        await store.enqueue(
          id: 'checkout-s1',
          kind: PendingOpKind.checkOut,
          payload: const {'route_stop_id': 's1'},
          routeId: 'r1',
        );
        final progress = _FakeStopProgressStore({'s1': 'exec-1'});
        await progress.markDone('s1');
        final status = StreamController<RouteSyncStatus>.broadcast();
        addTearDown(status.close);
        final worker = _RecordingSyncWorker(statusStream: status.stream);
        final repository = _repositoryWith(
          routeWith(
            stops: [
              stopWith(
                id: 's1',
                status: 'IN_PROGRESS',
                servicePointName: 'Sala 101',
              ),
            ],
          ),
        );
        handOutSecondBatch(repository);
        await tester.pumpWidget(
          _screenWith(
            repository,
            localWriteStore: store,
            stopProgressStore: progress,
            syncWorker: worker,
          ),
        );
        await tester.pumpAndSettle();
        status.add(
          const RouteSyncStatus(
            routeId: 'r1',
            state: RouteSyncState.idle,
            pending: 1,
            blocked: 0,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(AppStrings.routeNextBatchOffline), findsOneWidget);
        expect(repository.allocationCalls, isEmpty);

        // The server is reachable again; the worker taps "Sincronizar agora".
        worker.drains = store;
        await tester.tap(
          find.widgetWithText(FilledButton, AppStrings.routeSyncNowButton),
        );
        await tester.pumpAndSettle();

        expect(worker.syncAllCount, 1);
        expect(repository.allocationCalls, ['nextBatch:r1']);
        expect(find.text('Sala 202'), findsOneWidget);
      },
    );
  });

  testWidgets('shows the unread count on the notification bell badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screenWith(
        _repositoryWith(_openBatchRoute),
        monitoringApi: _FakeMonitoringApi(unread: 3),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(Badge), matching: find.text('3')),
      findsOneWidget,
    );
  });

  testWidgets('shows no badge when there are no unread notifications', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screenWith(_repositoryWith(_openBatchRoute)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Badge), findsNothing);
  });

  testWidgets('tapping the bell opens the notifications screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screenWith(
        _repositoryWith(_openBatchRoute),
        monitoringApi: _FakeMonitoringApi(unread: 1),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationsScreen), findsOneWidget);
  });

  group('released stops (spec 2026-10-20-alocacao-automatica §7.5)', () {
    final route = routeWith(
      stops: [
        stopWith(
          id: 's1',
          status: 'RELEASED',
          releaseReason: 'LOCATION_SILENCE',
          servicePointName: 'Sala 101',
        ),
        stopWith(id: 's2', orderIndex: 2, servicePointName: 'Sala 102'),
      ],
    );

    /// The device's database, holding an appealable notice for s1.
    Future<AppDatabase> dbWithNotice() async {
      final db = inMemoryDatabase();
      addTearDown(db.close);
      await DriftReleasedStopStore(db).record(
        routeStopId: 's1',
        releaseReason: 'LOCATION_SILENCE',
        appealable: true,
      );
      return db;
    }

    void announce(WidgetTester tester, {required bool appealable}) {
      ProviderScope.containerOf(tester.element(find.byType(RouteScreen)))
          .read(stopReleaseAnnouncementsProvider.notifier)
          .announce(
            StopRelease(
              routeStopId: 's1',
              releaseReason: 'LOCATION_SILENCE',
              appealable: appealable,
            ),
          );
    }

    testWidgets(
      'an appealable release shows the snackbar, and "Recorrer" opens the '
      "stop's appeal form",
      (tester) async {
        final db = await dbWithNotice();
        await tester.pumpWidget(
          _screenWith(
            _repositoryWith(route),
            releasedStopStore: DriftReleasedStopStore(db),
          ),
        );
        await tester.pumpAndSettle();

        announce(tester, appealable: true);
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.releasedStopsSnackbar), findsOneWidget);
        await tester.tap(find.text(AppStrings.releasedStopsSnackbarAction));
        await tester.pumpAndSettle();

        final form = tester.widget<AppealFormScreen>(
          find.byType(AppealFormScreen),
        );
        expect(form.routeStopId, 's1');
        expect(form.servicePointName, 'Sala 101');
      },
    );

    testWidgets('a release the worker cannot appeal shows no snackbar', (
      tester,
    ) async {
      await tester.pumpWidget(_screenWith(_repositoryWith(route)));
      await tester.pumpAndSettle();

      announce(tester, appealable: false);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.releasedStopsSnackbar), findsNothing);
    });

    testWidgets(
      'a reload of the day refreshes the appeals badge: the server may have '
      'released points meanwhile',
      (tester) async {
        final appealApi = RecordingAppealApi();
        await tester.pumpWidget(
          _screenWith(_repositoryWith(route), appealApi: appealApi),
        );
        await tester.pumpAndSettle();
        final callsAfterLoad = appealApi.eligibleCalls;

        ProviderScope.containerOf(
          tester.element(find.byType(RouteScreen)),
        ).invalidate(myDayProvider);
        await tester.pumpAndSettle();

        expect(appealApi.eligibleCalls, callsAfterLoad + 1);
      },
    );

    testWidgets('a released stop without a reason reads just "Liberado"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _screenWith(
          _repositoryWith(
            routeWith(
              stops: [
                stopWith(id: 's1', status: 'RELEASED', servicePointName: 'X'),
                stopWith(id: 's2', orderIndex: 2),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Liberado'), findsOneWidget);
      expect(find.textContaining('Liberado · '), findsNothing);
    });

    testWidgets('the app bar counts the points the worker can contest', (
      tester,
    ) async {
      await tester.pumpWidget(
        _screenWith(
          _repositoryWith(route),
          appealApi: RecordingAppealApi(
            eligibleStops: [
              AppealableStop(
                routeStopId: 's1',
                servicePointName: 'Sala 101',
                buildingName: 'Bloco CAA',
                floorLabel: 'Térreo',
                releaseReason: 'LOCATION_SILENCE',
                deadline: DateTime.utc(2026, 10, 22, 14),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip(AppStrings.appealsTooltip), findsOneWidget);
      expect(find.widgetWithText(Badge, '1'), findsOneWidget);
    });
  });
}

/// Location permissions as the device would answer them: "while in use"
/// granted, "always" as the test says.
class _FakePermissions implements PermissionPort {
  _FakePermissions({this.grantsAlways = false});

  @override
  bool get supportsBackground => true;

  final bool grantsAlways;
  bool _always = false;
  int alwaysRequests = 0;

  @override
  Future<bool> requestWhileInUse() async => true;

  @override
  Future<bool> isAlwaysGranted() async => _always;

  @override
  Future<bool> requestAlways() async {
    alwaysRequests++;
    return _always = grantsAlways;
  }

  @override
  Future<void> requestNotifications() async {}
}

/// permission_handler failing on the platform side (e.g. a request already
/// running).
class _ThrowingPermissions implements PermissionPort {
  @override
  bool get supportsBackground => true;

  @override
  Future<bool> requestWhileInUse() =>
      throw PlatformException(code: 'ERROR_ALREADY_REQUESTING_PERMISSIONS');

  @override
  Future<bool> isAlwaysGranted() async => false;

  @override
  Future<bool> requestAlways() async => false;

  @override
  Future<void> requestNotifications() async {}
}

/// A device that never saw a stop released.
class _NoReleasedStops implements ReleasedStopStore {
  @override
  Future<bool> record({
    required String routeStopId,
    required String releaseReason,
    required bool appealable,
  }) async => false;

  @override
  Future<ReleasedStopNotice?> noticeFor(String routeStopId) async => null;

  @override
  Future<List<ReleasedStopNotice>> allNotices() async => const [];

  @override
  Future<void> discardStop(String routeStopId) async {}
}

class _InMemoryAskStore implements BackgroundAskStore {
  _InMemoryAskStore({this.asked = false});

  bool asked;

  @override
  Future<bool> wasAsked() async => asked;

  @override
  Future<void> markAsked() async => asked = true;
}

class _NoopScheduler implements LocalScheduler {
  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancel(int id) async {}
}
