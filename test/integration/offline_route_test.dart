// Consecutive `times.add(...)` calls are separated by real awaits and a
// cascade would obscure that ordering; the fake's optional failure config is
// genuinely nullable (unset in the happy-path test).
// ignore_for_file: cascade_invocations
// ignore_for_file: use_late_for_private_fields_and_variables

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/evidence_capture.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/execution_repository.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/route_screen.dart';
import 'package:route_monitor/sync/connectivity.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_triggers.dart';
import 'package:route_monitor/sync/sync_worker.dart';

import '../support/in_memory_database.dart';

/// DELIVERABLE PROOF for Etapa 6 (RF35): a whole batch is executed with the
/// device offline and synced later with the ORIGINAL device timestamps
/// preserved — and only then is the next batch asked for (spec
/// 2026-10-20-alocacao-automatica §6.4: "Iniciar rota" itself is online, so
/// the route is already IN_PROGRESS when the worker walks into the basement).
/// Spec Ruling 11 + §7 open point 4 — this integration test wires the REAL
/// worker + outbox + repository + UI on an in-memory database and
/// fakes only the outermost seams (Connectivity, the two APIs, the route
/// repository, GPS). The true end-to-end (a real camera in a real basement)
/// is the manual field step.
///
/// This is a widget-level integration test that runs headless in the Flutter
/// test VM (`flutter test test/integration/offline_route_test.dart`), NOT via
/// `flutter drive`, so it needs no device or emulator. It lives under `test/`
/// (not `integration_test/`) on purpose: `flutter test` special-cases the
/// `integration_test/` directory and forces on-device mode for anything in it,
/// which would make this deliverable unrunnable in CI without an emulator.
void main() {
  // The scenario drives the REAL SyncWorker + real Drift outbox, whose futures
  // ride the real event loop and real timers. `flutter_test`'s default
  // (fake-async) binding freezes those the moment a Drift-reading widget is
  // mounted; the Live binding runs everything on the real clock, so plain
  // `await` + `tester.pump()` is all that is needed here — no `runAsync`.
  LiveTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a full batch runs offline, syncs later with the original timestamps, '
    'and only then pulls the next batch',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      // ---- Offline phase: 5 actions, nothing may hit the network ----------
      final actionTimes = await fixture.runFullBatchOffline();

      // Nothing reached the "network".
      expect(fixture.executionApi.calls, isEmpty);
      expect(fixture.evidenceApi.calls, isEmpty);

      // 5 outbox rows, all pending.
      final offlineRows = await fixture.store.unsyncedForRoute(_routeId);
      expect(offlineRows, hasLength(5));
      expect(
        offlineRows.map((r) => r.state),
        everyElement(PendingOpState.pending),
      );

      // Both stops are done locally (checked out on device — spec Ruling 3/5).
      expect(
        (await fixture.stopProgress.progressFor(_stop1))?.status,
        StopLocalStatus.done,
      );
      expect(
        (await fixture.stopProgress.progressFor(_stop2))?.status,
        StopLocalStatus.done,
      );

      // Mount the screen; its real _SyncBanner subscribes to the real worker
      // status stream and reports the 5 waiting actions (plural). The batch
      // is finished on the device, so the next one waits for the network.
      await fixture.container.read(myDayProvider.future); // warm: no spinner
      await tester.pumpWidget(fixture.app());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text(AppStrings.routePendingSync(5)),
        findsOneWidget,
      );
      expect(find.text(AppStrings.routeNextBatchOffline), findsOneWidget);
      expect(fixture.routeApi.nextBatchCalls, 0);

      // ---- Timestamp-preservation proof (the RF35 crux) -------------------
      // A real gap: a (wrongly) sync-stamped timestamp would land after
      // `syncStartedAt`; the action-time timestamps in the outbox land before.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final syncStartedAt = _nowUtc();

      // ---- Sync phase: connectivity regained ----------------------------
      // `goOnline` fires SyncTriggers -> syncAll; the explicit await makes the
      // drain deterministic before the assertions.
      fixture.connectivity.goOnline();
      await fixture.worker.syncAll();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // FIFO order, exactly the 5 actions oldest-first — and the next batch
      // only after the server has every one of them.
      expect(fixture.callLog, [
        'checkIn:$_stop1',
        'uploadPhoto',
        'checkOut:$_stop1',
        'checkIn:$_stop2',
        'checkOut:$_stop2',
        'nextBatch',
      ]);

      // Each dispatched call carried the timestamp captured BEFORE that
      // action — never the sync time. Recorded in FIFO/dispatch order:
      // checkIn(s1), uploadPhoto, checkOut(s1), checkIn(s2), checkOut(s2).
      final recorded = <DateTime>[
        fixture.executionApi.scannedAtArgs[0],
        fixture.evidenceApi.capturedAtArgs.single,
        fixture.executionApi.scannedAtArgs[1],
        fixture.executionApi.scannedAtArgs[2],
        fixture.executionApi.scannedAtArgs[3],
      ];
      for (var i = 0; i < 5; i++) {
        expect(
          recorded[i].isBefore(actionTimes[i]),
          isFalse,
          reason: 'call $i timestamp predates its own action',
        );
        expect(
          recorded[i].isBefore(actionTimes[i].add(const Duration(seconds: 2))),
          isTrue,
          reason: 'call $i timestamp is far past its action (sync time?)',
        );
        expect(
          recorded[i].isBefore(syncStartedAt),
          isTrue,
          reason:
              'call $i timestamp is not before the sync — stamped at sync '
              'time, not action time',
        );
        if (i > 0) {
          expect(
            recorded[i].isBefore(recorded[i - 1]),
            isFalse,
            reason: 'timestamps are not monotonically non-decreasing',
          );
        }
      }

      // All 5 rows are now `synced` (state, not deleted — spec Ruling 3).
      final syncedStates = await fixture.rawStates();
      expect(syncedStates, hasLength(5));
      expect(syncedStates, everyElement('synced'));
      expect(await fixture.store.unsyncedForRoute(_routeId), isEmpty);

      // The second batch is on screen and the banner flips to all-clear.
      expect(find.text(AppStrings.routeBatchHeader(2, 2)), findsOneWidget);
      expect(find.text('Sala 201'), findsOneWidget);
      expect(find.text(AppStrings.routeNextBatchOffline), findsNothing);
      expect(find.text(AppStrings.routeAllSynced), findsOneWidget);

      // ---- Idempotent re-drain -----------------------------------------
      await fixture.worker.syncAll();
      await tester.pump(const Duration(milliseconds: 100));
      expect(fixture.callLog, hasLength(6)); // no new calls
    },
  );

  testWidgets(
    'a hard 422 on the stop-2 check-in blocks that row and holds back its own '
    'check-out; the next-batch ask gets the same batch back',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      // The 2nd checkIn dispatch (stop 2) fails hard.
      fixture.executionApi.failCheckInOnCallWith(2, _dio(status: 422));

      await fixture.runFullBatchOffline();
      await fixture.container.read(myDayProvider.future);

      await tester.pumpWidget(fixture.app());
      await tester.pump(const Duration(milliseconds: 100));

      fixture.connectivity.goOnline();
      await fixture.worker.syncAll();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      final byKind = await fixture.statesByKind();
      final blocked = await fixture.store.blockedForRoute(_routeId);
      final stillPending = await fixture.store.unsyncedForRoute(_routeId);

      // stop 1's whole chain synced.
      expect(byKind['checkIn'], containsAll(<String>['synced', 'blocked']));
      expect(byKind['evidencePhoto'], ['synced']);
      // The stop-2 check-in is blocked (hard 422, not retried forever).
      expect(blocked, hasLength(1));
      expect(blocked.single.kind, PendingOpKind.checkIn);
      expect(blocked.single.payload['route_stop_id'], _stop2);
      // The stop-2 check-out never dispatched — FIFO halted behind the block.
      expect(stillPending, hasLength(1));
      expect(stillPending.single.kind, PendingOpKind.checkOut);
      expect(stillPending.single.payload['route_stop_id'], _stop2);
      // The held check-out is no network's to deliver, so the pull still
      // asks — and the server, which never got stop 2, hands back batch 1.
      expect(fixture.callLog, [
        'checkIn:$_stop1',
        'uploadPhoto',
        'checkOut:$_stop1',
        'checkIn:$_stop2', // attempted, threw 422
        'nextBatch',
      ]);
      expect(fixture.routeApi.batchesHandedOut, 0);

      // Banner shows the blocked state.
      expect(
        find.textContaining('Sincronização bloqueada'),
        findsOneWidget,
      );
    },
  );
}

const _routeId = 'r1';
const _stop1 = 's1';
const _stop2 = 's2';
const _qr = 'v1.floor.1.sig';

DateTime _nowUtc() => DateTime.now().toUtc();

final _photo = CapturedPhoto(
  bytes: Uint8List.fromList(const [1, 2, 3, 4]),
  sha256: 'a' * 64,
);

DioException _dio({required int status}) {
  final options = RequestOptions(path: '/check-ins');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: options,
      statusCode: status,
      data: 'FLOOR_NOT_ON_ROUTE',
    ),
  );
}

/// Everything the test drives: a real [ProviderContainer] with a real
/// in-memory database, the real [SyncWorker]/[ExecutionRepository]/stores, and
/// recording fakes for the outermost seams only.
class _Fixture {
  _Fixture(
    this.container,
    this.executionApi,
    this.evidenceApi,
    this.routeApi,
    this.connectivity,
    this.callLog,
  );

  final ProviderContainer container;
  final _RecordingExecutionApi executionApi;
  final _RecordingEvidenceApi evidenceApi;
  final _RecordingRouteRepository routeApi;
  final _FakeConnectivity connectivity;
  final List<String> callLog;

  static Future<_Fixture> create() async {
    final callLog = <String>[];
    final executionApi = _RecordingExecutionApi(callLog);
    final evidenceApi = _RecordingEvidenceApi(callLog);
    final routeApi = _RecordingRouteRepository(callLog);
    final connectivity = _FakeConnectivity();
    final db = inMemoryDatabase();

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        connectivityProvider.overrideWithValue(connectivity),
        executionApiProvider.overrideWithValue(executionApi),
        evidenceApiProvider.overrideWithValue(evidenceApi),
        routeRepositoryProvider.overrideWithValue(routeApi),
        locationServiceProvider.overrideWithValue(_FakeLocationService()),
        apiBaseUrlProvider.overrideWithValue('http://test-base'),
      ],
    );
    return _Fixture(
      container,
      executionApi,
      evidenceApi,
      routeApi,
      connectivity,
      callLog,
    );
  }

  ExecutionRepository get repo => container.read(executionRepositoryProvider);
  SyncWorker get worker => container.read(syncWorkerProvider);
  LocalWriteStore get store => container.read(localWriteStoreProvider);
  StopProgressStore get stopProgress =>
      container.read(stopProgressStoreProvider);
  AppDatabase get _db => container.read(appDatabaseProvider);

  Widget app() => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      builder: (context, child) =>
          SyncTriggers(child: child ?? const SizedBox.shrink()),
      home: const RouteScreen(),
    ),
  );

  /// Drives the 5 field actions of the batch through the REAL
  /// [ExecutionRepository] while offline, capturing wall-clock time
  /// immediately before each one. Returns the 5 capture instants in action
  /// order.
  Future<List<DateTime>> runFullBatchOffline() async {
    final times = <DateTime>[];

    times.add(_nowUtc());
    final execution1 = await repo.checkIn(
      routeId: _routeId,
      routeStopId: _stop1,
      qrPayload: _qr,
      latitude: -7.23,
      longitude: -35.88,
    );

    times.add(_nowUtc());
    await repo.addPhoto(
      routeId: _routeId,
      executionId: execution1,
      photo: _photo,
    );

    times.add(_nowUtc());
    await repo.checkOut(
      routeId: _routeId,
      routeStopId: _stop1,
      qrPayload: _qr,
      latitude: -7.23,
      longitude: -35.88,
    );

    times.add(_nowUtc());
    await repo.checkIn(
      routeId: _routeId,
      routeStopId: _stop2,
      qrPayload: _qr,
      latitude: -7.24,
      longitude: -35.89,
    );

    times.add(_nowUtc());
    await repo.checkOut(
      routeId: _routeId,
      routeStopId: _stop2,
      qrPayload: _qr,
      latitude: -7.24,
      longitude: -35.89,
    );

    return times;
  }

  /// The raw `state` column of every outbox row for the route, FIFO order.
  Future<List<String>> rawStates() async {
    final rows =
        await (_db.select(_db.pendingOperations)
              ..where((r) => r.routeId.equals(_routeId))
              ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
            .get();
    return rows.map((r) => r.state).toList();
  }

  Future<Map<String, List<String>>> statesByKind() async {
    final rows = await (_db.select(
      _db.pendingOperations,
    )..where((r) => r.routeId.equals(_routeId))).get();
    final out = <String, List<String>>{};
    for (final r in rows) {
      (out[r.kind] ??= <String>[]).add(r.state);
    }
    return out;
  }

  Future<void> dispose() async {
    // `appDatabaseProvider` is overridden with a value, so its `onDispose`
    // close hook never runs — close the in-memory db here instead, or drift
    // warns about a second AppDatabase on the next test.
    await _db.close();
    container.dispose();
    await connectivity.dispose();
  }
}

class _FakeLocationService implements LocationService {
  @override
  Future<Coordinates> getCurrentPosition({
    required LocationPurpose purpose,
  }) async => const Coordinates(latitude: -7.23, longitude: -35.88);
}

/// Fake [Connectivity] starting offline. `onOnlineChanged` only reports the
/// regained edge, exactly like the real `distinct()` + filter pipeline.
class _FakeConnectivity implements Connectivity {
  bool _online = false;
  final _controller = StreamController<bool>.broadcast();

  @override
  Future<bool> get isOnline async => _online;

  @override
  Stream<bool> get onOnlineChanged => _controller.stream;

  void goOnline() {
    _online = true;
    _controller.add(true);
  }

  Future<void> dispose() => _controller.close();
}

/// Records every dispatch and the timestamp arg it received; can be told to
/// throw on the Nth `checkIn` call (hard-error variant).
class _RecordingExecutionApi implements ExecutionApi {
  _RecordingExecutionApi(this._log);

  final List<String> _log;
  final List<DateTime> scannedAtArgs = [];
  int _checkInCalls = 0;
  int? _failCheckInOnCall;
  DioException? _failWith;

  void failCheckInOnCallWith(int call, DioException error) {
    _failCheckInOnCall = call;
    _failWith = error;
  }

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
  }) async {
    _checkInCalls++;
    _log.add('checkIn:$routeStopId');
    scannedAtArgs.add(scannedAt);
    if (_checkInCalls == _failCheckInOnCall) throw _failWith!;
    return (
      result: CheckInResult(
        routeStopId: routeStopId!,
        executionId: executionId,
        geoValidation: 'INSIDE',
        flags: const [],
      ),
      serverDate: null,
    );
  }

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
  }) async {
    _log.add('checkOut:$routeStopId');
    scannedAtArgs.add(scannedAt);
    return (
      result: CheckOutResult(
        routeStopId: routeStopId!,
        executionId: executionId,
        checkedOutAt: DateTime.utc(2026),
        flags: const [],
      ),
      serverDate: null,
    );
  }

  @override
  Future<void> reportImpediment({
    required String routeId,
    required String? routeStopId,
    required String scope,
    required String reason,
    required DateTime reportedAt,
    String? note,
  }) async => throw UnimplementedError();

  List<String> get calls => _log.where((c) => c.startsWith('check')).toList();
}

class _RecordingEvidenceApi implements EvidenceApi {
  _RecordingEvidenceApi(this._log);

  final List<String> _log;
  final List<DateTime> capturedAtArgs = [];

  @override
  Future<DateTime?> uploadPhoto({
    required String executionId,
    required Uint8List bytes,
    required String sha256,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async {
    _log.add('uploadPhoto');
    capturedAtArgs.add(capturedAt);
    return null;
  }

  @override
  Future<DateTime?> uploadNote({
    required String executionId,
    required String textBody,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async {
    _log.add('uploadNote');
    capturedAtArgs.add(capturedAt);
    return null;
  }

  @override
  Future<List<EvidenceItem>> listEvidence(String executionId) async => const [];

  List<String> get calls => _log.where((c) => c.contains('pload')).toList();
}

/// The server side of the day: batch 1 (stops 1 and 2) until it has both
/// check-outs and the next batch is asked for, batch 2 (one new stop) from
/// then on. Asked earlier, it hands batch 1 back unchanged, like B3.
class _RecordingRouteRepository implements RouteRepository {
  _RecordingRouteRepository(this._log);

  final List<String> _log;
  int nextBatchCalls = 0;
  int batchesHandedOut = 0;

  RouteSummary _route() => RouteSummary(
    id: _routeId,
    fieldWorkerName: 'João',
    routeDate: DateTime(2026, 9, 3),
    status: 'IN_PROGRESS',
    startedAt: DateTime.utc(2026, 9, 3, 8),
    currentBatch: batchesHandedOut == 0 ? 1 : 2,
    stops: [
      RouteStopSummary(
        id: _stop1,
        orderIndex: 1,
        batchNumber: 1,
        status: batchesHandedOut == 0 ? 'PENDING' : 'DONE',
        servicePointName: 'Sala 101',
        latitude: -7.23,
        longitude: -35.88,
      ),
      RouteStopSummary(
        id: _stop2,
        orderIndex: 2,
        batchNumber: 1,
        status: batchesHandedOut == 0 ? 'PENDING' : 'DONE',
        servicePointName: 'Sala 102',
        latitude: -7.24,
        longitude: -35.89,
      ),
      if (batchesHandedOut > 0)
        const RouteStopSummary(
          id: 's3',
          orderIndex: 3,
          batchNumber: 2,
          status: 'PENDING',
          servicePointName: 'Sala 201',
          latitude: -7.25,
          longitude: -35.9,
        ),
    ],
  );

  @override
  Future<MyDay> fetchMyDay() async => MyDay(
    serviceDay: true,
    route: _route(),
    positionIntervalSeconds: 60,
    silenceWarningMinutes: 30,
    silenceReleaseMinutes: 45,
  );

  @override
  Future<AllocationResult> startOrResume({
    required double lat,
    required double lng,
    required DateTime capturedAt,
  }) async => throw UnimplementedError('the route is already started');

  @override
  Future<AllocationResult> nextBatch(
    String routeId, {
    required double lat,
    required double lng,
    required DateTime capturedAt,
  }) async {
    _log.add('nextBatch');
    nextBatchCalls++;
    final batchDone =
        _log.contains('checkOut:$_stop1') && _log.contains('checkOut:$_stop2');
    if (batchDone) batchesHandedOut++;
    return AllocationResult(route: _route(), poolEmpty: false);
  }
}
