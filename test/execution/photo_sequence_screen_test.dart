import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/evidence_capture.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/photo_sequence_screen.dart';
import 'package:route_monitor/execution/photo_sequence_widgets.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/ui/app_theme.dart';

import '../routing/map_home_fakes.dart';
import '../support/fake_evidence_camera.dart';

const _shutter = Key('photo-shutter');
const _done = Key('photo-done');

/// A store whose `enqueue` waits on [gate] when set, to observe the screen
/// between "shutter tapped" and "row written".
class _GatedStore extends InMemoryLocalWriteStore {
  Completer<void>? gate;
  Error? failure;

  /// When true, `deletePendingPhoto` refuses like the real store does for a
  /// row that a sync worker claimed after the screen listed it.
  bool refuseDelete = false;

  @override
  Future<bool> deletePendingPhoto(String operationId) async =>
      !refuseDelete && await super.deletePendingPhoto(operationId);

  @override
  Future<bool> enqueue({
    required String id,
    required PendingOpKind kind,
    required Map<String, dynamic> payload,
    required String routeId,
    PendingOpState initialState = PendingOpState.pending,
  }) async {
    await gate?.future;
    if (failure != null) throw failure!;
    return super.enqueue(
      id: id,
      kind: kind,
      payload: payload,
      routeId: routeId,
      initialState: initialState,
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required InMemoryLocalWriteStore store,
  int? minimum,
  FakeEvidenceCamera? camera,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localWriteStoreProvider.overrideWithValue(store),
        evidenceCameraProvider.overrideWithValue(
          camera ?? FakeEvidenceCamera(),
        ),
        capturedFileCompressorProvider.overrideWithValue(
          (path) async => CapturedPhoto(bytes: onePixelPng, sha256: path),
        ),
        evidenceApiProvider.overrideWithValue(FakeEvidenceApi()),
        stopProgressStoreProvider.overrideWithValue(FakeStopProgressStore()),
        syncWorkerProvider.overrideWithValue(RecordingSyncWorker()),
        apiBaseUrlProvider.overrideWithValue('http://test-base'),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: PhotoSequenceScreen(
          routeId: 'r1',
          executionId: 'exec-1',
          title: AppStrings.photoSequenceTitle('CAA', '1º andar'),
          minimum: minimum,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _shoot(WidgetTester tester) async {
  await tester.tap(find.byKey(_shutter));
  await tester.pumpAndSettle();
}

bool _doneEnabled(WidgetTester tester) =>
    tester
        .widget<InkWell>(
          find.descendant(
            of: find.byKey(_done),
            matching: find.byType(InkWell),
          ),
        )
        .onTap !=
    null;

void main() {
  testWidgets('each shot is enqueued before its thumbnail appears', (
    tester,
  ) async {
    final store = _GatedStore()..gate = Completer<void>();
    await _pump(tester, store: store, minimum: 2);

    await tester.tap(find.byKey(_shutter));
    await tester.pump();
    expect(find.byKey(const Key('photo-thumb-0')), findsNothing);
    expect(await store.localPhotoCountFor('exec-1'), 0);

    store.gate!.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('photo-thumb-0')), findsOneWidget);
    final rows = await store.unsyncedForRoute('r1');
    expect(rows.single.kind, PendingOpKind.evidencePhoto);
    expect(rows.single.payload['sha256'], '/fake/shot-1.jpg');
  });

  testWidgets('counter shows "1 de 2 obrigatórias", Pronto needs 2 shots', (
    tester,
  ) async {
    await _pump(tester, store: InMemoryLocalWriteStore(), minimum: 2);
    expect(find.text('0 de 2 obrigatórias'), findsOneWidget);

    await _shoot(tester);

    expect(find.text('1 de 2 obrigatórias'), findsOneWidget);
    expect(find.text('Falta 1'), findsOneWidget);
    expect(_doneEnabled(tester), isFalse);

    await _shoot(tester);

    expect(find.text('2 de 2 obrigatórias'), findsOneWidget);
    expect(find.text('Falta 1'), findsNothing);
    expect(_doneEnabled(tester), isTrue);
  });

  testWidgets('non-evidence stop shows "{n} fotos", Pronto always enabled', (
    tester,
  ) async {
    await _pump(tester, store: InMemoryLocalWriteStore());
    expect(find.text('0 fotos'), findsOneWidget);
    expect(_doneEnabled(tester), isTrue);

    await _shoot(tester);
    await _shoot(tester);
    await _shoot(tester);

    expect(find.text('3 fotos'), findsOneWidget);
    expect(_doneEnabled(tester), isTrue);
  });

  testWidgets('Apagar removes an unsynced photo and the counter decrements', (
    tester,
  ) async {
    final store = InMemoryLocalWriteStore();
    await _pump(tester, store: store, minimum: 2);
    await _shoot(tester);
    await _shoot(tester);

    await tester.tap(find.byKey(const Key('photo-thumb-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photo-delete')));
    await tester.pumpAndSettle();

    expect(await store.unsyncedForRoute('r1'), hasLength(1));
    expect(find.byKey(const Key('photo-thumb-1')), findsNothing);
    expect(find.text('1 de 2 obrigatórias'), findsOneWidget);
    expect(_doneEnabled(tester), isFalse);
  });

  testWidgets('Apagar is not offered for a synced photo: cloud icon instead', (
    tester,
  ) async {
    final store = InMemoryLocalWriteStore();
    await _pump(tester, store: store);
    await _shoot(tester);
    final id = (await store.unsyncedForRoute('r1')).single.id;
    await store.markSynced(id);

    await tester.tap(find.byKey(const Key('photo-thumb-0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('photo-delete')), findsNothing);
    expect(find.text(AppStrings.photoSequenceDelete), findsNothing);
    expect(find.byIcon(Icons.cloud_done), findsWidgets);
    expect(find.text(AppStrings.photoSequenceSynced), findsOneWidget);
  });

  testWidgets('an uploading photo is not shown as sent and has no Apagar', (
    tester,
  ) async {
    final store = InMemoryLocalWriteStore();
    await _pump(tester, store: store);
    await _shoot(tester);
    final id = (await store.unsyncedForRoute('r1')).single.id;
    await store.claim(id, now: 0, leaseUntil: 1);

    await tester.tap(find.byKey(const Key('photo-thumb-0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('photo-delete')), findsNothing);
    expect(find.byIcon(Icons.cloud_done), findsNothing);
    expect(find.text(AppStrings.photoSequenceSynced), findsNothing);
    expect(find.text(AppStrings.photoSequenceNotSent), findsOneWidget);
  });

  testWidgets('a blocked photo gets the brick badge and can be deleted', (
    tester,
  ) async {
    final store = InMemoryLocalWriteStore();
    await _pump(tester, store: store, minimum: 2);
    await _shoot(tester);
    final id = (await store.unsyncedForRoute('r1')).single.id;
    await store.markBlocked(id, 'HTTP 422');

    await tester.tap(find.byKey(const Key('photo-thumb-0')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.photoSequenceBlocked), findsOneWidget);
    expect(find.text(AppStrings.photoSequenceSynced), findsNothing);
    final badge = tester.widget<Container>(
      find
          .ancestor(
            of: find.descendant(
              of: find.byKey(const Key('photo-thumb-0')),
              matching: find.byIcon(Icons.cloud_off),
            ),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (badge.decoration! as BoxDecoration).color,
      FieldPalette.light.brick,
    );

    await tester.tap(find.byKey(const Key('photo-delete')));
    await tester.pumpAndSettle();

    expect(await store.blockedForRoute('r1'), isEmpty);
    expect(await store.localPhotoCountFor('exec-1'), 0);
    expect(find.byKey(const Key('photo-thumb-0')), findsNothing);
    expect(find.text('0 de 2 obrigatórias'), findsOneWidget);
  });

  testWidgets("empty slots count the stop's photos from earlier sessions", (
    tester,
  ) async {
    final store = InMemoryLocalWriteStore();
    await store.enqueue(
      id: 'earlier',
      kind: PendingOpKind.evidencePhoto,
      payload: {'execution_id': 'exec-1'},
      routeId: 'r1',
    );
    await _pump(tester, store: store, minimum: 2);

    expect(find.text('1 de 2 obrigatórias'), findsOneWidget);
    expect(find.byType(PendingSlot), findsOneWidget);

    await _shoot(tester);

    expect(find.byType(PendingSlot), findsNothing);
  });

  testWidgets('no gallery entry point', (tester) async {
    await _pump(tester, store: InMemoryLocalWriteStore(), minimum: 2);

    expect(find.byIcon(Icons.photo_library), findsNothing);
    expect(find.byIcon(Icons.photo_library_outlined), findsNothing);
  });

  testWidgets('a camera that cannot open shows the message, stays closable', (
    tester,
  ) async {
    await _pump(
      tester,
      store: InMemoryLocalWriteStore(),
      camera: FakeEvidenceCamera(openError: StateError('denied')),
    );

    expect(find.text(AppStrings.photoSequenceCameraError), findsOneWidget);
    expect(find.byKey(const Key('photo-close')), findsOneWidget);
  });

  testWidgets('a failed save shows the error and adds no thumbnail', (
    tester,
  ) async {
    final store = _GatedStore();
    await _pump(tester, store: store);
    store.failure = StateError('disk full');

    await _shoot(tester);

    expect(find.text(AppStrings.photoSequenceSaveError), findsOneWidget);
    expect(find.byKey(const Key('photo-thumb-0')), findsNothing);
  });

  testWidgets('openPhotoSequence returns the photos kept in the session', (
    tester,
  ) async {
    final store = InMemoryLocalWriteStore();
    var result = -1;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localWriteStoreProvider.overrideWithValue(store),
          evidenceCameraProvider.overrideWithValue(FakeEvidenceCamera()),
          capturedFileCompressorProvider.overrideWithValue(
            (path) async => CapturedPhoto(bytes: onePixelPng, sha256: path),
          ),
          evidenceApiProvider.overrideWithValue(FakeEvidenceApi()),
          stopProgressStoreProvider.overrideWithValue(FakeStopProgressStore()),
          syncWorkerProvider.overrideWithValue(RecordingSyncWorker()),
          apiBaseUrlProvider.overrideWithValue('http://test-base'),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await openPhotoSequence(
                context,
                routeId: 'r1',
                executionId: 'exec-1',
                buildingName: 'CAA',
                floorLabel: '1º andar',
                minimum: null,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('CAA · 1º andar'), findsOneWidget);
    await _shoot(tester);
    await _shoot(tester);

    await tester.tap(find.byKey(_done));
    await tester.pumpAndSettle();

    expect(result, 2);
  });

  testWidgets('Pronto, X and back wait for a shot in flight (RNF06)', (
    tester,
  ) async {
    final store = _GatedStore()..gate = Completer<void>();
    var result = -1;
    await _pumpOpened(tester, store, (r) => result = r);

    await tester.tap(find.byKey(_shutter));
    await tester.pump();
    await tester.tap(find.byKey(_done), warnIfMissed: false);
    await tester.tap(find.byKey(const Key('photo-close')), warnIfMissed: false);
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.byType(PhotoSequenceScreen), findsOneWidget);
    expect(result, -1);

    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(await store.unsyncedForRoute('r1'), hasLength(1));
    expect(find.byType(PhotoSequenceScreen), findsOneWidget);

    await tester.tap(find.byKey(_done));
    await tester.pumpAndSettle();
    expect(result, 1);
  });

  testWidgets('Apagar on a row the store refuses shows a message', (
    tester,
  ) async {
    final store = _GatedStore();
    await _pump(tester, store: store);
    await _shoot(tester);
    // Listed as deletable, then claimed for sending before the tap lands.
    store.refuseDelete = true;

    await tester.tap(find.byKey(const Key('photo-thumb-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photo-delete')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.photoSequenceDeleteError), findsOneWidget);
    expect(find.byKey(const Key('photo-thumb-0')), findsOneWidget);
  });

  testWidgets('the camera is closed when the screen goes away', (
    tester,
  ) async {
    final camera = FakeEvidenceCamera();
    await _pump(tester, store: InMemoryLocalWriteStore(), camera: camera);
    expect(camera.closed, isFalse);

    await tester.pumpWidget(const SizedBox());

    expect(camera.closed, isTrue);
  });

  group('app lifecycle (final review I-4)', () {
    void lifecycle(WidgetTester tester, AppLifecycleState state) =>
        tester.binding.handleAppLifecycleStateChanged(state);

    testWidgets('inactive closes the camera, resumed re-opens it', (
      tester,
    ) async {
      final camera = FakeEvidenceCamera();
      await _pump(tester, store: InMemoryLocalWriteStore(), camera: camera);
      expect(camera.opens, 1);

      lifecycle(tester, AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(camera.closed, isTrue);
      expect(find.byKey(const Key('fake-preview')), findsNothing);

      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(camera.opens, 2);
      expect(camera.closed, isFalse);
      expect(find.byKey(const Key('fake-preview')), findsOneWidget);
    });

    testWidgets('going inactive twice and back opens the camera once', (
      tester,
    ) async {
      final camera = FakeEvidenceCamera();
      await _pump(tester, store: InMemoryLocalWriteStore(), camera: camera);

      // Android passes inactive again on its way back from paused.
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        lifecycle(tester, state);
        await tester.pump();
      }
      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(camera.opens, 2);
      expect(find.byKey(const Key('fake-preview')), findsOneWidget);
    });

    testWidgets('a shot in flight keeps the camera until it is written', (
      tester,
    ) async {
      final camera = FakeEvidenceCamera();
      final store = _GatedStore()..gate = Completer<void>();
      await _pump(tester, store: store, camera: camera);

      await tester.tap(find.byKey(_shutter));
      await tester.pump();
      lifecycle(tester, AppLifecycleState.inactive);
      await tester.pump();
      expect(camera.closed, isFalse);

      store.gate!.complete();
      await tester.pumpAndSettle();
      expect(await store.localPhotoCountFor('exec-1'), 1);
      expect(camera.closed, isTrue);

      lifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(camera.opens, 2);
      expect(find.byKey(const Key('fake-preview')), findsOneWidget);
    });
  });

  testWidgets('a takePicture failure shows the error and the shutter works', (
    tester,
  ) async {
    final camera = FakeEvidenceCamera()..shotError = StateError('busy');
    await _pump(tester, store: InMemoryLocalWriteStore(), camera: camera);

    await _shoot(tester);
    expect(find.text(AppStrings.photoSequenceSaveError), findsOneWidget);
    expect(find.byKey(const Key('photo-thumb-0')), findsNothing);

    await _shoot(tester);
    expect(find.byKey(const Key('photo-thumb-0')), findsOneWidget);
  });

  testWidgets('counter is singular for 1 and plural for 3', (tester) async {
    await _pump(tester, store: InMemoryLocalWriteStore());
    await _shoot(tester);
    expect(find.text('1 foto'), findsOneWidget);

    await _shoot(tester);
    await _shoot(tester);
    expect(find.text('3 fotos'), findsOneWidget);
  });
}

Future<void> _pumpOpened(
  WidgetTester tester,
  InMemoryLocalWriteStore store,
  void Function(int) onResult,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localWriteStoreProvider.overrideWithValue(store),
        evidenceCameraProvider.overrideWithValue(FakeEvidenceCamera()),
        capturedFileCompressorProvider.overrideWithValue(
          (path) async => CapturedPhoto(bytes: onePixelPng, sha256: path),
        ),
        evidenceApiProvider.overrideWithValue(FakeEvidenceApi()),
        stopProgressStoreProvider.overrideWithValue(FakeStopProgressStore()),
        syncWorkerProvider.overrideWithValue(RecordingSyncWorker()),
        apiBaseUrlProvider.overrideWithValue('http://test-base'),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => onResult(
              await openPhotoSequence(
                context,
                routeId: 'r1',
                executionId: 'exec-1',
                buildingName: 'CAA',
                floorLabel: '1º andar',
                minimum: null,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
