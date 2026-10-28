import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/checkin/checkin_providers.dart';
import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/execution/evidence_capture.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/execution_repository.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/routing/building_card_model.dart';
import 'package:route_monitor/routing/floor_actions.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/ui/app_theme.dart';

import '../support/fake_day_log_store.dart';
import '../support/in_memory_database.dart';
import 'map_home_fakes.dart';

RouteStopSummary _stop(
  String id,
  int order, {
  String floorId = 'f1',
  String status = 'PENDING',
}) => RouteStopSummary(
  id: id,
  orderIndex: order,
  batchNumber: 1,
  status: status,
  servicePointName: 'Sala $id',
  buildingId: 'b1',
  buildingName: 'Prédio',
  floorLabel: 'Andar $floorId',
  floorId: floorId,
  latitude: -7.2,
  longitude: -35.9,
);

RouteSummary _route(List<RouteStopSummary> stops) => RouteSummary(
  id: 'r1',
  fieldWorkerName: 'João',
  routeDate: DateTime(2026, 10, 28),
  status: 'IN_PROGRESS',
  startedAt: null,
  currentBatch: 1,
  stops: stops,
);

const _entryQr = 'v1.f1.1.sig';

void main() {
  late AppDatabase db;
  late DriftStopProgressStore progress;
  late InMemoryLocalWriteStore store;
  late RecordingSyncWorker worker;
  late ExecutionRepository repository;

  setUp(() {
    db = inMemoryDatabase();
    addTearDown(db.close);
    progress = DriftStopProgressStore(db);
    store = InMemoryLocalWriteStore();
    worker = RecordingSyncWorker();
    repository = ExecutionRepository(
      store,
      progress,
      worker,
      database: db,
      dayLog: RecordingDayLogStore(),
    );
  });

  /// A button that runs [action]; returns the container for assertions.
  Future<ProviderContainer> pumpHost(
    WidgetTester tester,
    Future<void> Function(BuildContext, WidgetRef) action,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localWriteStoreProvider.overrideWithValue(store),
          stopProgressStoreProvider.overrideWithValue(progress),
          syncWorkerProvider.overrideWithValue(worker),
          executionRepositoryProvider.overrideWithValue(repository),
          qrVerifierProvider.overrideWithValue(FakeQrVerifier()),
          locationServiceProvider.overrideWithValue(FakeLocationService()),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => action(context, ref),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    return ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
  }

  /// Taps the host button and answers the pushed scanner with [rawValue].
  Future<void> scanWith(WidgetTester tester, String rawValue) async {
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(ScanScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(ScanScreen))).pop(rawValue);
    await tester.pumpAndSettle();
  }

  Future<List<PendingOperationRow>> rowsOf(PendingOpKind kind) async => [
    for (final row in await store.unsyncedForRoute('r1'))
      if (row.kind == kind) row,
  ];

  group('checkInFloor', () {
    final route = _route([
      _stop('s1', 1),
      _stop('s2', 2),
      _stop('s3', 3, floorId: 'f2'),
    ]);

    testWidgets('checks in every open task of the scanned floor with the same '
        'QR and one fresh key each', (tester) async {
      await pumpHost(
        tester,
        (context, ref) => checkInFloor(context, ref, route),
      );

      await scanWith(tester, _entryQr);

      final rows = await rowsOf(PendingOpKind.checkIn);
      expect(rows.map((r) => r.payload['route_stop_id']), ['s1', 's2']);
      expect(rows.map((r) => r.payload['qr_payload']).toSet(), {_entryQr});
      expect(rows.map((r) => r.id).toSet(), hasLength(2));
      expect(rows.first.payload['latitude'], -7.23);
      expect(
        (await progress.progressFor('s1'))?.status,
        StopLocalStatus.inProgress,
      );
      expect(find.text(AppStrings.floorCheckInDone(2)), findsOneWidget);
    });

    testWidgets('a floor with no open task enqueues nothing and says so', (
      tester,
    ) async {
      await pumpHost(
        tester,
        (context, ref) => checkInFloor(context, ref, route),
      );

      await scanWith(tester, 'v1.f-elsewhere.1.sig');

      expect(await store.unsyncedForRoute('r1'), isEmpty);
      expect(find.text(AppStrings.floorHasNoOpenTasks), findsOneWidget);
    });

    testWidgets('a QR that does not verify gets the invalid-QR notice', (
      tester,
    ) async {
      await pumpHost(
        tester,
        (context, ref) => checkInFloor(context, ref, route),
      );

      await scanWith(tester, 'not-a-qr');

      expect(await store.unsyncedForRoute('r1'), isEmpty);
      expect(find.text(AppStrings.scanInvalidQr), findsOneWidget);
    });

    testWidgets('a second scan before the sync does not check a task in '
        'twice', (tester) async {
      await progress.upsertInProgress('s1', 'exec-s1');
      await pumpHost(
        tester,
        (context, ref) => checkInFloor(context, ref, route),
      );

      await scanWith(tester, _entryQr);

      final rows = await rowsOf(PendingOpKind.checkIn);
      expect(rows.map((r) => r.payload['route_stop_id']), ['s2']);
      expect(find.text(AppStrings.floorCheckInDone(1)), findsOneWidget);
    });

    testWidgets('a task reported impossible is not checked in', (tester) async {
      await repository.impedeTask(
        routeId: 'r1',
        routeStopId: 's2',
        reason: 'OTHER',
      );
      await pumpHost(
        tester,
        (context, ref) => checkInFloor(context, ref, route),
      );

      await scanWith(tester, _entryQr);

      final rows = await rowsOf(PendingOpKind.checkIn);
      expect(rows.map((r) => r.payload['route_stop_id']), ['s1']);
    });
  });

  group('checkOutFloor', () {
    testWidgets('checks out each stamped task with its own stored '
        'observation', (tester) async {
      final route = _route([_stop('s1', 1), _stop('s2', 2), _stop('s3', 3)]);
      await progress.upsertInProgress('s1', 'exec-s1');
      await progress.upsertInProgress('s2', 'exec-s2');
      await progress.upsertInProgress('s3', 'exec-s3');
      await progress.markStamped('s1', observation: 'nota um');
      await progress.markStamped('s2');
      // s3 is still being worked: it stays out of the check-out.
      final floor = await _floorOf(route, progress);
      final container = await pumpHost(
        tester,
        (context, ref) => checkOutFloor(context, ref, route, floor),
      );

      await scanWith(tester, 'v1.f1.1.exit');

      final rows = await rowsOf(PendingOpKind.checkOut);
      expect(rows.map((r) => r.payload['route_stop_id']), ['s1', 's2']);
      expect(rows[0].payload['complaints_suggestions'], 'nota um');
      expect(rows[1].payload.containsKey('complaints_suggestions'), isFalse);
      expect(rows.map((r) => r.payload['qr_payload']).toSet(), {
        'v1.f1.1.exit',
      });
      expect(rows.map((r) => r.id).toSet(), hasLength(2));
      expect(
        (await progress.progressFor('s1'))?.status,
        StopLocalStatus.done,
      );
      expect(
        (await progress.progressFor('s3'))?.status,
        StopLocalStatus.inProgress,
      );
      expect(find.text(AppStrings.floorCheckOutDone), findsOneWidget);
      expect(container.read(lastStampedStopProvider), isNull);
    });

    Future<void> scanExitExpectingNoCheckOut(
      WidgetTester tester,
      String rawValue,
      String notice,
    ) async {
      final route = _route([_stop('s1', 1)]);
      await progress.upsertInProgress('s1', 'exec-s1');
      await progress.markStamped('s1');
      final floor = await _floorOf(
        route,
        progress,
        expected: [SlotState.stamped],
      );
      await pumpHost(
        tester,
        (context, ref) => checkOutFloor(context, ref, route, floor),
      );

      await scanWith(tester, rawValue);

      expect(await store.unsyncedForRoute('r1'), isEmpty);
      expect(
        (await progress.progressFor('s1'))?.status,
        StopLocalStatus.stamped,
      );
      expect(find.text(notice), findsOneWidget);
    }

    testWidgets('a QR that does not verify checks nothing out', (tester) async {
      await scanExitExpectingNoCheckOut(
        tester,
        'not-a-qr',
        AppStrings.scanInvalidQr,
      );
    });

    testWidgets("another floor's QR checks nothing out and names the floor", (
      tester,
    ) async {
      await scanExitExpectingNoCheckOut(
        tester,
        'v1.f2.1.exit',
        AppStrings.exitQrWrongFloor('Andar f1'),
      );
    });
  });

  group('task flows', () {
    final route = _route([_stop('s1', 1)]);

    Future<String> takePhoto() => repository.addPhoto(
      routeId: 'r1',
      executionId: 'exec-s1',
      photo: CapturedPhoto(bytes: Uint8List.fromList([1]), sha256: 'h'),
    );

    testWidgets('concludeTask stamps locally and releases the photos', (
      tester,
    ) async {
      await progress.upsertInProgress('s1', 'exec-s1');
      final key = await takePhoto();
      late WidgetRef captured;
      final container = await pumpHost(tester, (context, ref) async {
        captured = ref;
      });
      await tester.tap(find.text('go'));

      await concludeTask(captured, route, route.stops.single, observation: 'x');

      final entry = (await progress.progressFor('s1'))!;
      expect(entry.status, StopLocalStatus.stamped);
      expect(entry.observation, 'x');
      final rows = await store.unsyncedForRoute('r1');
      expect(rows.single.id, key);
      expect(rows.single.state, PendingOpState.pending);
      expect(container.read(lastStampedStopProvider), 's1');
    });

    testWidgets('signalTaskImpossible reports, drops held photos and marks '
        'the stop', (tester) async {
      await progress.upsertInProgress('s1', 'exec-s1');
      await takePhoto();
      late BuildContext capturedContext;
      late WidgetRef captured;
      final container = await pumpHost(tester, (context, ref) async {
        capturedContext = context;
        captured = ref;
      });
      await tester.tap(find.text('go'));

      await signalTaskImpossible(
        capturedContext,
        captured,
        route,
        route.stops.single,
        reason: 'ACCESS_BLOCKED',
        note: 'trancada',
      );
      await tester.pump();

      final rows = await store.unsyncedForRoute('r1');
      expect(rows.single.kind, PendingOpKind.impediment);
      expect(rows.single.payload['scope'], 'STOP');
      expect(rows.single.payload['route_stop_id'], 's1');
      expect(container.read(lastImpededStopProvider), 's1');
      expect(worker.syncedRoutes, contains('r1'));
      expect(find.text(AppStrings.taskImpededDone), findsOneWidget);
    });
  });
}

/// The only floor of [route]'s only building, as the cards would derive it
/// from the device's progress rows.
Future<FloorRow> _floorOf(
  RouteSummary route,
  StopProgressStore progress, {
  List<SlotState> expected = const [
    SlotState.stamped,
    SlotState.stamped,
    SlotState.inProgress,
  ],
}) async {
  final entries = await progress.allForRoute(route.stops.map((s) => s.id));
  final local = {
    for (final e in entries)
      e.routeStopId: LocalStopState(status: e.status, updatedAt: e.updatedAt),
  };
  final floor = buildDayBuildings(route, local, {}, {}).single.floors.single;
  expect(floor.slots.map((s) => s.state), expected);
  return floor;
}
