import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/appeals/appeal_api.dart';
import 'package:route_monitor/appeals/appeal_providers.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/evidence_camera.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/execution_repository.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/day_log_store.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/released_stop_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/monitoring/location_mode.dart';
import 'package:route_monitor/monitoring/monitoring_api.dart';
import 'package:route_monitor/monitoring/monitoring_providers.dart';
import 'package:route_monitor/monitoring/silence_watchdog.dart';
import 'package:route_monitor/routing/approach_api.dart';
import 'package:route_monitor/routing/live_approach.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/map_home_screen.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/connectivity.dart';
import 'package:route_monitor/sync/sync_notifications.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/sync/sync_worker.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/batch_card.dart';
import 'package:route_monitor/ui/stamp_slot.dart';

import '../appeals/fake_appeal_api.dart';
import '../support/fake_connectivity.dart';
import '../support/fake_day_log_store.dart';
import '../support/fake_sync_notification_taps.dart';
import '../support/in_memory_database.dart';
import 'fake_approach_api.dart';
import 'map_home_fakes.dart';
import 'no_tiles_tile_provider.dart';

export '../support/fake_sync_notification_taps.dart';
export 'map_home_fakes.dart';

/// The map home under test, every outer seam faked: never the network, the
/// device database, a GPS or the real tile pipeline.
Widget homeWith(
  RouteRepository repository, {
  LocationService? locationService,
  bool realExecutionRepository = true,
  EvidenceApi? evidenceApi,
  EvidenceCamera? evidenceCamera,
  StopProgressStore? stopProgressStore,
  LocalWriteStore? localWriteStore,
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
  SyncNotificationTaps? notificationTaps,
  DayLogStore? dayLogStore,
  ApproachApi? approachApi,
}) {
  final progress = stopProgressStore ?? FakeStopProgressStore();
  final store = localWriteStore ?? InMemoryLocalWriteStore();
  final worker = syncWorker ?? RecordingSyncWorker();
  final dayLog = dayLogStore ?? RecordingDayLogStore();
  // In memory, never the device file: the check-out opens its transaction
  // here, and the full card looks up the batch's first check-in.
  final db = inMemoryDatabase();
  addTearDown(db.close);
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      dayLogStoreProvider.overrideWithValue(dayLog),
      routeRepositoryProvider.overrideWithValue(repository),
      monitoringApiProvider.overrideWithValue(
        monitoringApi ?? FakeMonitoringApi(),
      ),
      appealApiProvider.overrideWithValue(appealApi ?? RecordingAppealApi()),
      releasedStopStoreProvider.overrideWithValue(
        releasedStopStore ?? NoReleasedStops(),
      ),
      syncWorkerProvider.overrideWithValue(worker),
      syncNotificationTapsProvider.overrideWithValue(
        notificationTaps ?? FakeSyncNotificationTaps(),
      ),
      locationServiceProvider.overrideWithValue(
        locationService ?? FakeLocationService(),
      ),
      // The live first leg asks the server once a position is known.
      approachApiProvider.overrideWithValue(approachApi ?? FakeApproachApi()),
      // Online unless a test says otherwise: the next-batch controller the
      // screen mounts must never reach the real connectivity_plus plugin.
      connectivityProvider.overrideWithValue(
        connectivity ?? FakeConnectivity(isOnline: true),
      ),
      stopProgressStoreProvider.overrideWithValue(progress),
      evidenceApiProvider.overrideWithValue(evidenceApi ?? FakeEvidenceApi()),
      localWriteStoreProvider.overrideWithValue(store),
      syncMetaStoreProvider.overrideWithValue(InMemorySyncMetaStore()),
      apiBaseUrlProvider.overrideWithValue(apiBaseUrl ?? 'http://test-base'),
      // "Iniciar rota" settles the location mode first: never the real
      // permission_handler under flutter_test, and — unless a test is about
      // that flow — the "always" question already asked, so no dialog.
      permissionPortProvider.overrideWithValue(
        permissions ?? FakePermissions(),
      ),
      backgroundAskStoreProvider.overrideWithValue(
        backgroundAsked ?? InMemoryAskStore(asked: true),
      ),
      if (silenceWatchdog != null)
        silenceWatchdogProvider.overrideWithValue(silenceWatchdog),
      if (session != null)
        sessionProvider.overrideWith(() => FixedSession(session)),
      if (evidenceCamera != null)
        evidenceCameraProvider.overrideWithValue(evidenceCamera),
      // The repository never calls the network (spec Ruling 2): it enqueues
      // into `store`, updates `progress`, then kicks the recording worker.
      if (realExecutionRepository)
        executionRepositoryProvider.overrideWithValue(
          ExecutionRepository(
            store,
            progress,
            worker,
            database: db,
            dayLog: dayLog,
          ),
        ),
    ],
    child: MaterialApp(
      theme: buildAppTheme(),
      home: MapHomeScreen(mapTileProvider: NoTilesTileProvider()),
    ),
  );
}

/// A phone-shaped, tall surface so the sheet's lists fit without scrolling.
void usePhoneSurface(WidgetTester tester, {Size size = const Size(420, 1400)}) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Pumps [app] on the phone surface and lets it settle.
Future<void> pumpHome(WidgetTester tester, Widget app) async {
  usePhoneSurface(tester);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

/// Drives the home's sheet to [size] (0.22, 0.5 or 0.9).
Future<void> snapSheetTo(WidgetTester tester, double size) async {
  final sheet = tester.widget<DraggableScrollableSheet>(
    find.byType(DraggableScrollableSheet),
  );
  sheet.controller!.jumpTo(size);
  await tester.pumpAndSettle();
}

/// The "Sem conexão para o próximo lote" panel in the sheet — not the
/// snackbar that says the same.
Finder nextBatchOfflinePanel() => find.descendant(
  of: find.byType(DraggableScrollableSheet),
  matching: find.text(AppStrings.routeNextBatchOffline),
);

Finder scanQrButton() => find.text(AppStrings.scanQrButton);

/// Taps a widget in the sheet, scrolling it into view first.
Future<void> tapInSheet(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The card slot of [stopId] in the sheet's carousel.
Finder slotOf(String stopId) => find.byWidgetPredicate(
  (widget) => widget is StampSlot && widget.slot.stopId == stopId,
);

/// Taps [stopId]'s slot on the card and lets its stop sheet open: the
/// stop's actions live there now, not in a list under the card.
Future<void> openStopSheet(WidgetTester tester, String stopId) async {
  await tapInSheet(tester, slotOf(stopId));
  expect(stopSheet(), findsOneWidget, reason: 'stop sheet of $stopId');
}

/// The carousel's page, settled: the index of the batch card shown.
double? carouselPage(WidgetTester tester) => tester
    .widget<PageView>(find.byKey(const ValueKey('batch-card-carousel')))
    .controller
    ?.page;

/// The pin's `done/total` count, inside its circle (the label may hang
/// off-screen to the right).
Finder pinCircle(String buildingId) => find.descendant(
  of: find.byKey(ValueKey('pin-$buildingId')),
  matching: find.textContaining('/'),
);

/// The carousel's card nearest the centre of the screen: the one shown.
BatchCardView shownCard(WidgetTester tester) {
  final centre = tester.getCenter(find.byType(MapHomeScreen)).dx;
  final cards = find.byType(BatchCardView).evaluate().toList()
    ..sort(
      (a, b) => (tester.getCenter(find.byWidget(a.widget)).dx - centre)
          .abs()
          .compareTo(
            (tester.getCenter(find.byWidget(b.widget)).dx - centre).abs(),
          ),
    );
  return cards.first.widget as BatchCardView;
}

/// The open stop sheet (a modal bottom sheet over the home).
Finder stopSheet() => find.byKey(const ValueKey('stop-sheet'));

/// Closes the open stop sheet the way a worker would: back.
Future<void> closeStopSheet(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

/// Taps "Escanear QR" and answers the pushed [ScanScreen] with [rawValue]
/// (null = dismissed).
///
/// This pushes a real, uncontrolled ScanScreen() — MobileScanner builds its
/// own default (autoStart: true) controller and tries to start the real
/// camera. That is safe under flutter_test, but not because the
/// platform-channel call fails and gets caught: it never resolves at all
/// (traced in task-17 review). Safe only because nothing here awaits or
/// observes that leaked future.
Future<void> scanWith(WidgetTester tester, String? rawValue) async {
  await tester.tap(scanQrButton());
  await tester.pumpAndSettle();
  expect(find.byType(ScanScreen), findsOneWidget);
  Navigator.of(tester.element(find.byType(ScanScreen))).pop(rawValue);
}

/// The in-progress block's "Concluir" (the stop rows keep a text one).
Finder blockConcludeButton() =>
    find.byKey(const ValueKey('in-progress-conclude'));

/// The in-progress block's "Tirar fotos".
Finder blockTakePhotosButton() =>
    find.byKey(const ValueKey('in-progress-take-photos'));

/// Taps the in-progress block's "Concluir", optionally types [observation]
/// into the conclusion sheet, taps "Escanear QR de saída" and answers the
/// pushed [ScanScreen] with [rawValue] (null = cancelled; same
/// leaked-camera caveat as [scanWith]).
Future<void> concludeWith(
  WidgetTester tester,
  String? rawValue, {
  String? observation,
}) async {
  await tapInSheet(tester, blockConcludeButton());
  if (observation != null) {
    await tester.enterText(find.byType(TextField), observation);
  }
  await tester.tap(find.text(AppStrings.concludeScanExitButton));
  await tester.pumpAndSettle();
  expect(find.byType(ScanScreen), findsOneWidget);
  Navigator.of(tester.element(find.byType(ScanScreen))).pop(rawValue);
  await tester.pumpAndSettle();
}

/// A [RouteStopSummary] in building [buildingId] (default `b1`), batch 1,
/// PENDING unless told otherwise.
RouteStopSummary stopIn({
  required String id,
  String buildingId = 'b1',
  String buildingName = 'Prédio',
  String floorLabel = 'Térreo',
  int orderIndex = 1,
  int batchNumber = 1,
  String status = 'PENDING',
  String? servicePointName,
  double latitude = -7.21,
  double longitude = -35.91,
  double? distanceFromPrevM,
  double? durationFromPrevS,
  bool requiresEvidence = false,
  String? releaseReason,
  DateTime? doneAt,
}) => RouteStopSummary(
  buildingId: buildingId,
  buildingName: buildingName,
  floorLabel: floorLabel,
  id: id,
  orderIndex: orderIndex,
  batchNumber: batchNumber,
  status: status,
  servicePointName: servicePointName ?? 'Sala $id',
  latitude: latitude,
  longitude: longitude,
  distanceFromPrevM: distanceFromPrevM,
  durationFromPrevS: durationFromPrevS,
  requiresEvidence: requiresEvidence,
  releaseReason: releaseReason,
  doneAt: doneAt,
);

/// Shared by tests that only need the type to exist in the tree.
StreamController<RouteSyncStatus> statusController() {
  final controller = StreamController<RouteSyncStatus>.broadcast();
  addTearDown(controller.close);
  return controller;
}
