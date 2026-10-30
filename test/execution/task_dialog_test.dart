import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_monitor/execution/evidence_capture.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/execution_repository.dart';
import 'package:route_monitor/execution/location_execution_id.dart';
import 'package:route_monitor/execution/location_gate.dart';
import 'package:route_monitor/execution/location_gate_source.dart';
import 'package:route_monitor/execution/task_dialog.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/stop_completion.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/ui/app_theme.dart';

import '../routing/map_home_fakes.dart';
import '../support/fake_day_log_store.dart';
import '../support/in_memory_database.dart';
import 'location_gate_fakes.dart';

RouteStopSummary _stop({
  bool requiresEvidence = true,
  String floorLabel = 'Térreo',
  StopCompletion completion = StopCompletion.qr,
}) => RouteStopSummary(
  completion: completion,
  id: 's1',
  orderIndex: 1,
  batchNumber: 1,
  status: 'PENDING',
  servicePointName: 'Banheiro masculino',
  buildingId: 'b1',
  buildingName: 'Central de Aulas',
  floorLabel: floorLabel,
  floorId: 'f1',
  latitude: -7.2,
  longitude: -35.9,
  serviceTypeName: 'Limpeza de banheiro',
  requiresEvidence: requiresEvidence,
);

RouteSummary _route(RouteStopSummary stop, {int checkRadiusMeters = 50}) =>
    RouteSummary(
      checkRadiusMeters: checkRadiusMeters,
      id: 'r1',
      fieldWorkerName: 'João',
      routeDate: DateTime(2026, 10, 28),
      status: 'IN_PROGRESS',
      startedAt: null,
      currentBatch: 1,
      stops: [stop],
    );

CardSlot _slot(SlotState state, {String stopId = 's1'}) => CardSlot(
  stopId: stopId,
  state: state,
  floorLabel: 'Térreo',
  stampedAt: null,
  pendingSync: false,
  releaseReason: null,
  stampRotationDeg: 0,
);

void main() {
  late AppDatabase db;
  late DriftStopProgressStore progress;
  late InMemoryLocalWriteStore store;
  late ExecutionRepository repository;
  late FakeLocationGateSource gates;

  setUp(() {
    gates = FakeLocationGateSource();
    db = inMemoryDatabase();
    addTearDown(db.close);
    progress = DriftStopProgressStore(db);
    store = InMemoryLocalWriteStore();
    repository = ExecutionRepository(
      store,
      progress,
      RecordingSyncWorker(),
      database: db,
      dayLog: RecordingDayLogStore(),
    );
  });

  /// A host whose button opens the task dialog for [stop] on a [state]
  /// slot, and taps it. With [tappedStopId], it goes through `showSlotTask`
  /// for a slot of that stop instead; [progressStore] replaces the
  /// in-memory progress rows the dialog reads.
  Future<void> openDialog(
    WidgetTester tester, {
    RouteStopSummary? stop,
    SlotState state = SlotState.inProgress,
    String? tappedStopId,
    StopProgressStore? progressStore,
    int checkRadiusMeters = 50,
  }) async {
    final shown = stop ?? _stop();
    tester.view
      ..physicalSize = const Size(420, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localWriteStoreProvider.overrideWithValue(store),
          stopProgressStoreProvider.overrideWithValue(
            progressStore ?? progress,
          ),
          syncWorkerProvider.overrideWithValue(RecordingSyncWorker()),
          executionRepositoryProvider.overrideWithValue(repository),
          evidenceApiProvider.overrideWithValue(FakeEvidenceApi()),
          locationGateSourceProvider.overrideWithValue(gates),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => tappedStopId == null
                    ? showTaskDialog(
                        context,
                        ref,
                        route: _route(
                          shown,
                          checkRadiusMeters: checkRadiusMeters,
                        ),
                        stop: shown,
                        slot: _slot(state),
                      )
                    : showSlotTask(
                        context,
                        ref,
                        _route(shown, checkRadiusMeters: checkRadiusMeters),
                        _slot(state, stopId: tappedStopId),
                      ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  /// Opens a bare [TaskDialog] for [stop] and collects what it pops, so a
  /// test can read the [TaskDecision] itself.
  Future<List<TaskDecision>> openAndCapture(
    WidgetTester tester,
    RouteStopSummary stop,
  ) async {
    final popped = <TaskDecision>[];
    tester.view
      ..physicalSize = const Size(420, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localWriteStoreProvider.overrideWithValue(store),
          stopProgressStoreProvider.overrideWithValue(progress),
          syncWorkerProvider.overrideWithValue(RecordingSyncWorker()),
          executionRepositoryProvider.overrideWithValue(repository),
          evidenceApiProvider.overrideWithValue(FakeEvidenceApi()),
          locationGateSourceProvider.overrideWithValue(gates),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final decision = await showDialog<TaskDecision>(
                  context: context,
                  builder: (_) => TaskDialog(route: _route(stop), stop: stop),
                );
                if (decision != null) popped.add(decision);
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return popped;
  }

  Future<void> addPhotos(int n) async {
    for (var i = 0; i < n; i++) {
      await repository.addPhoto(
        routeId: 'r1',
        executionId: 'exec-1',
        photo: CapturedPhoto(bytes: onePixelPng, sha256: 'sha-$i'),
      );
    }
  }

  Future<List<PendingOperationRow>> rowsOf(PendingOpKind kind) async => [
    for (final row in await store.unsyncedForRoute('r1'))
      if (row.kind == kind) row,
  ];

  IconButton cameraButton(WidgetTester tester) => tester.widget(
    find.ancestor(
      of: find.byTooltip(AppStrings.taskAddPhotos),
      matching: find.byType(IconButton),
    ),
  );

  FilledButton concludeButton(WidgetTester tester) => tester.widget(
    find.widgetWithText(FilledButton, AppStrings.taskConclude),
  );

  Future<void> signalImpossibleWith(WidgetTester tester, String label) async {
    await tester.tap(find.text(AppStrings.routeSignalImpossibilityButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pump();
  }

  testWidgets('shows the service point, its place and its details', (
    tester,
  ) async {
    await openDialog(tester);

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Banheiro masculino'), findsOneWidget);
    expect(find.text('Central de Aulas · Térreo'), findsOneWidget);
    expect(find.text('Limpeza de banheiro'), findsOneWidget);
    expect(find.text(AppStrings.taskRequiresPhotos), findsOneWidget);
    expect(find.text(AppStrings.taskObservationLabel), findsOneWidget);
  });

  testWidgets('a bare-number floor reads "Andar <n>" under the name', (
    tester,
  ) async {
    await openDialog(tester, stop: _stop(floorLabel: '1'));

    expect(find.text('Central de Aulas · Andar 1'), findsOneWidget);
  });

  testWidgets('a task with no evidence flag does not ask for photos', (
    tester,
  ) async {
    await openDialog(tester, stop: _stop(requiresEvidence: false));

    expect(find.text(AppStrings.taskRequiresPhotos), findsNothing);
  });

  testWidgets('without the floor check-in the camera and Concluir are off '
      'and the hint says why', (tester) async {
    await openDialog(tester);

    expect(cameraButton(tester).onPressed, isNull);
    expect(concludeButton(tester).onPressed, isNull);
    expect(find.text(AppStrings.taskNeedsFloorCheckIn), findsOneWidget);
  });

  testWidgets('an evidence task with no photo keeps Concluir off', (
    tester,
  ) async {
    await progress.upsertInProgress('s1', 'exec-1');
    await openDialog(tester);

    expect(cameraButton(tester).onPressed, isNotNull);
    expect(concludeButton(tester).onPressed, isNull);
    expect(find.text(AppStrings.missingPhotos(2)), findsOneWidget);
    expect(find.text(AppStrings.taskNeedsFloorCheckIn), findsNothing);
  });

  testWidgets('with two photos Concluir stamps the task with the typed '
      'observation', (tester) async {
    await progress.upsertInProgress('s1', 'exec-1');
    await addPhotos(2);
    await openDialog(tester);
    expect(find.byTooltip(AppStrings.taskRemovePhoto), findsNWidgets(2));

    await tester.enterText(find.byType(TextField), '  pia entupida  ');
    await tester.tap(find.text(AppStrings.taskConclude));
    await tester.pumpAndSettle();

    final entry = await progress.progressFor('s1');
    expect(entry?.status, StopLocalStatus.stamped);
    expect(entry?.observation, 'pia entupida');
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('the observation draft survives closing and reopening', (
    tester,
  ) async {
    await openDialog(tester);
    await tester.enterText(find.byType(TextField), 'sem papel');
    await tester.tap(find.byTooltip(AppStrings.photoSequenceClose));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('sem papel'), findsOneWidget);
  });

  testWidgets('✕ on a thumbnail deletes that held photo at once', (
    tester,
  ) async {
    await progress.upsertInProgress('s1', 'exec-1');
    await addPhotos(1);
    await openDialog(tester);

    await tester.tap(find.byTooltip(AppStrings.taskRemovePhoto));
    await tester.pumpAndSettle();

    expect(await rowsOf(PendingOpKind.evidencePhoto), isEmpty);
    expect(find.byTooltip(AppStrings.taskRemovePhoto), findsNothing);
  });

  testWidgets('Sinalizar impossibilidade sends the picked reason with the '
      'observation as its note', (tester) async {
    await progress.upsertInProgress('s1', 'exec-1');
    await openDialog(tester);
    await tester.enterText(find.byType(TextField), 'porta trancada');

    await signalImpossibleWith(
      tester,
      AppStrings.impedimentReasonAccessBlocked,
    );
    await tester.tap(find.text(AppStrings.commonConfirm));
    await tester.pumpAndSettle();

    final rows = await rowsOf(PendingOpKind.impediment);
    expect(rows, hasLength(1));
    expect(rows.single.payload['reason'], 'ACCESS_BLOCKED');
    expect(rows.single.payload['note'], 'porta trancada');
    expect(rows.single.payload['route_stop_id'], 's1');
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('cancelling the reason writes nothing and keeps the task open', (
    tester,
  ) async {
    await progress.upsertInProgress('s1', 'exec-1');
    await openDialog(tester);

    await signalImpossibleWith(tester, AppStrings.impedimentReasonOther);
    await tester.tap(find.text(AppStrings.commonCancel));
    await tester.pumpAndSettle();

    expect(await store.unsyncedForRoute('r1'), isEmpty);
    expect(
      (await progress.progressFor('s1'))?.status,
      StopLocalStatus.inProgress,
    );
    expect(find.text(AppStrings.taskConclude), findsOneWidget);
  });

  testWidgets('an over-long observation is cut to the impediment note limit', (
    tester,
  ) async {
    await openDialog(tester);
    await tester.enterText(find.byType(TextField), 'a' * 700);

    await signalImpossibleWith(tester, AppStrings.impedimentReasonOther);
    await tester.tap(find.text(AppStrings.commonConfirm));
    await tester.pumpAndSettle();

    final note = (await rowsOf(
      PendingOpKind.impediment,
    )).single.payload['note'];
    expect((note as String).runes.length, 500);
  });

  testWidgets('a stamped slot opens no dialog', (tester) async {
    await openDialog(tester, state: SlotState.stamped);

    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('the reason dialog warns only when the observation is over '
      'the note limit', (tester) async {
    await openDialog(tester);
    await tester.enterText(find.byType(TextField), 'a' * 500);
    await tester.tap(find.text(AppStrings.routeSignalImpossibilityButton));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.impossibilityNoteTrimmed), findsNothing);
    await tester.tap(find.text(AppStrings.commonCancel));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'a' * 501);
    await tester.tap(find.text(AppStrings.routeSignalImpossibilityButton));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.impossibilityNoteTrimmed), findsOneWidget);
  });

  testWidgets('a slot whose stop left the route opens nothing', (
    tester,
  ) async {
    await openDialog(tester, tappedStopId: 'gone');

    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a slot of the route opens its dialog through showSlotTask', (
    tester,
  ) async {
    await openDialog(tester, tappedStopId: 's1');

    expect(find.text('Banheiro masculino'), findsOneWidget);
  });

  testWidgets('a stamp that fails to save says so and keeps the draft', (
    tester,
  ) async {
    store = FailingTaskWriteStore();
    repository = ExecutionRepository(
      store,
      progress,
      RecordingSyncWorker(),
      database: db,
      dayLog: RecordingDayLogStore(),
    );
    await progress.upsertInProgress('s1', 'exec-1');
    await openDialog(tester, stop: _stop(requiresEvidence: false));
    await tester.enterText(find.byType(TextField), 'pia ok');

    await tester.tap(find.text(AppStrings.taskConclude));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.taskSaveFailed), findsOneWidget);
    expect(
      (await progress.progressFor('s1'))?.status,
      StopLocalStatus.inProgress,
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('pia ok'), findsOneWidget);
  });

  testWidgets('an impossibility that fails to save says so', (tester) async {
    store = FailingTaskWriteStore();
    repository = ExecutionRepository(
      store,
      progress,
      RecordingSyncWorker(),
      database: db,
      dayLog: RecordingDayLogStore(),
    );
    await openDialog(tester);

    await signalImpossibleWith(tester, AppStrings.impedimentReasonOther);
    await tester.tap(find.text(AppStrings.commonConfirm));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.taskSaveFailed), findsOneWidget);
    expect(await store.unsyncedForRoute('r1'), isEmpty);
  });

  group('a location stop', () {
    final place = _stop(
      requiresEvidence: false,
      completion: StopCompletion.location,
    );
    final evidencePlace = _stop(completion: StopCompletion.location);
    const ready = LocationGate(
      GateState.ready,
      distanceM: 12,
      fix: Coordinates(latitude: -7.2, longitude: -35.9),
    );

    testWidgets('Concluir is off and says to turn the location on', (
      tester,
    ) async {
      gates.emit(const LocationGate(GateState.locationOff));
      await openDialog(tester, stop: place);

      expect(concludeButton(tester).onPressed, isNull);
      expect(find.text(AppStrings.taskGateLocationOff), findsOneWidget);
      expect(find.text(AppStrings.taskNeedsFloorCheckIn), findsNothing);
    });

    testWidgets('Concluir is off while the position is being found', (
      tester,
    ) async {
      await openDialog(tester, stop: place);

      expect(concludeButton(tester).onPressed, isNull);
      expect(find.text(AppStrings.taskGateSearching), findsOneWidget);
    });

    testWidgets('Concluir is off too far away and says how far', (
      tester,
    ) async {
      gates.emit(const LocationGate(GateState.tooFar, distanceM: 312.4));
      await openDialog(tester, stop: place);

      expect(concludeButton(tester).onPressed, isNull);
      expect(
        find.text('Você está a 312 m do local; chegue a até 50 m.'),
        findsOneWidget,
      );
    });

    testWidgets('Concluir is on when ready, with no check-in needed', (
      tester,
    ) async {
      gates.emit(ready);
      await openDialog(tester, stop: place);

      expect(concludeButton(tester).onPressed, isNotNull);
      expect(find.text(AppStrings.taskGateSearching), findsNothing);
    });

    testWidgets('Concluir turns on when the gate becomes ready, dialog open', (
      tester,
    ) async {
      await openDialog(tester, stop: place);
      expect(concludeButton(tester).onPressed, isNull);

      gates.emit(ready);
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(concludeButton(tester).onPressed, isNotNull);
      expect(find.text(AppStrings.taskGateSearching), findsNothing);
    });

    testWidgets('Concluir turns off again when the location goes off', (
      tester,
    ) async {
      gates.emit(ready);
      await openDialog(tester, stop: place);

      gates.emit(const LocationGate(GateState.locationOff));
      await tester.pumpAndSettle();

      expect(concludeButton(tester).onPressed, isNull);
      expect(find.text(AppStrings.taskGateLocationOff), findsOneWidget);
    });

    testWidgets("the hint and the gate use the route's check radius", (
      tester,
    ) async {
      gates.emit(const LocationGate(GateState.tooFar, distanceM: 90));
      await openDialog(tester, stop: place, checkRadiusMeters: 65);

      expect(find.text(AppStrings.taskGateTooFar(90, 65)), findsOneWidget);
      expect(gates.watchedRadii, [65.0]);
    });

    testWidgets("the gate watches the stop's own coordinates", (
      tester,
    ) async {
      await openDialog(tester, stop: place);

      expect(gates.watchedTargets, [const LatLng(-7.2, -35.9)]);
    });

    testWidgets('the camera and Sinalizar impossibilidade stay on with '
        'location off', (tester) async {
      gates.emit(const LocationGate(GateState.locationOff));
      await openDialog(tester, stop: place);

      expect(cameraButton(tester).onPressed, isNotNull);
      final impossible = tester.widget<TextButton>(
        find.widgetWithText(
          TextButton,
          AppStrings.routeSignalImpossibilityButton,
        ),
      );
      expect(impossible.onPressed, isNotNull);
    });

    testWidgets('a photo already held under the id shows as a thumbnail', (
      tester,
    ) async {
      await repository.addPhoto(
        routeId: 'r1',
        executionId: locationExecutionId('s1'),
        photo: CapturedPhoto(bytes: onePixelPng, sha256: 'sha-0'),
      );
      await openDialog(tester, stop: place);

      expect(find.byTooltip(AppStrings.taskRemovePhoto), findsOneWidget);
    });

    testWidgets('with required evidence, ready is not enough without '
        'two photos', (tester) async {
      gates.emit(ready);
      await openDialog(tester, stop: evidencePlace);

      expect(concludeButton(tester).onPressed, isNull);
      expect(find.text(AppStrings.missingPhotos(2)), findsOneWidget);
    });

    testWidgets('with required evidence, two photos and ready open Concluir', (
      tester,
    ) async {
      gates.emit(ready);
      for (var i = 0; i < 2; i++) {
        await repository.addPhoto(
          routeId: 'r1',
          executionId: locationExecutionId('s1'),
          photo: CapturedPhoto(bytes: onePixelPng, sha256: 'sha-$i'),
        );
      }
      await openDialog(tester, stop: evidencePlace);

      expect(concludeButton(tester).onPressed, isNotNull);
    });

    testWidgets('with required evidence and two photos, too far still '
        'blocks', (tester) async {
      gates.emit(const LocationGate(GateState.tooFar, distanceM: 200));
      for (var i = 0; i < 2; i++) {
        await repository.addPhoto(
          routeId: 'r1',
          executionId: locationExecutionId('s1'),
          photo: CapturedPhoto(bytes: onePixelPng, sha256: 'sha-$i'),
        );
      }
      await openDialog(tester, stop: evidencePlace);

      expect(concludeButton(tester).onPressed, isNull);
    });

    testWidgets('concluding queues the location completion with the gate '
        'fix, writes no QR-style stamp and closes the dialog', (tester) async {
      gates.emit(ready);
      await openDialog(tester, stop: place);

      await tester.tap(find.text(AppStrings.taskConclude));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect((await progress.progressFor('s1'))!.status, StopLocalStatus.done);
      final row = (await store.unsyncedForRoute('r1')).single;
      expect(row.kind, PendingOpKind.locationCompletion);
      expect(row.payload['latitude'], -7.2);
      expect(row.payload['longitude'], -35.9);
    });

    testWidgets('Concluir pops the exact fix that opened the gate', (
      tester,
    ) async {
      const fix = Coordinates(latitude: -7.2001, longitude: -35.9002);
      gates.emit(const LocationGate(GateState.ready, distanceM: 5, fix: fix));
      final popped = await openAndCapture(tester, place);

      await tester.tap(find.text(AppStrings.taskConclude));
      await tester.pumpAndSettle();

      final decision = popped.single as TaskConcluded;
      expect(decision.fix?.latitude, -7.2001);
      expect(decision.fix?.longitude, -35.9002);
    });

    testWidgets('a gate that closes right before the tap pops nothing', (
      tester,
    ) async {
      gates.emit(ready);
      final popped = await openAndCapture(tester, place);
      expect(concludeButton(tester).onPressed, isNotNull);

      // No frame between the emission and the tap: the button is still the
      // one built for the ready gate.
      gates.emit(const LocationGate(GateState.tooFar, distanceM: 300));
      await tester.idle();
      await tester.tap(find.text(AppStrings.taskConclude));
      await tester.pumpAndSettle();

      expect(popped, isEmpty);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text(AppStrings.taskGateTooFar(300, 50)), findsOneWidget);
    });

    testWidgets('Sinalizar impossibilidade drops the photos held for the '
        'stop', (tester) async {
      gates.emit(const LocationGate(GateState.locationOff));
      await repository.addPhoto(
        routeId: 'r1',
        executionId: locationExecutionId('s1'),
        photo: CapturedPhoto(bytes: onePixelPng, sha256: 'sha-0'),
      );
      await openDialog(tester, stop: place);

      await signalImpossibleWith(tester, AppStrings.impedimentReasonOther);
      await tester.tap(find.text(AppStrings.commonConfirm));
      await tester.pumpAndSettle();

      expect(await rowsOf(PendingOpKind.evidencePhoto), isEmpty);
      expect(await rowsOf(PendingOpKind.impediment), hasLength(1));
    });
  });

  testWidgets('a QR stop ignores the location gate entirely', (tester) async {
    await progress.upsertInProgress('s1', 'exec-1');
    gates.emit(const LocationGate(GateState.locationOff));
    await openDialog(tester, stop: _stop(requiresEvidence: false));

    expect(concludeButton(tester).onPressed, isNotNull);
    expect(find.text(AppStrings.taskGateLocationOff), findsNothing);
    expect(gates.watchedTargets, isEmpty);
  });

  testWidgets('while the progress row loads no check-in hint flashes and '
      'Concluir stays off', (tester) async {
    await openDialog(tester, progressStore: NeverLoadingProgressStore());

    expect(find.text(AppStrings.taskNeedsFloorCheckIn), findsNothing);
    expect(concludeButton(tester).onPressed, isNull);
    expect(cameraButton(tester).onPressed, isNull);
  });
}

/// A write store that fails the writes behind a stamp (releasing the held
/// photos) and an impediment (enqueuing it), as a full disk would.
class FailingTaskWriteStore extends InMemoryLocalWriteStore {
  @override
  Future<int> releaseHeldPhotos(String executionId) async =>
      throw Exception('release of $executionId failed');

  @override
  Future<bool> enqueue({
    required String id,
    required PendingOpKind kind,
    required Map<String, dynamic> payload,
    required String routeId,
    PendingOpState initialState = PendingOpState.pending,
  }) async => throw Exception('enqueue of $kind failed');
}

/// A progress store whose read never completes: the dialog stays in its
/// loading state.
class NeverLoadingProgressStore extends FakeStopProgressStore {
  @override
  Future<StopProgressEntry?> progressFor(String routeStopId) =>
      Completer<StopProgressEntry?>().future;
}
