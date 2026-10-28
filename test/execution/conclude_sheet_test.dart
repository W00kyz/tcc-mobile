import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/execution/conclude_sheet.dart';
import 'package:route_monitor/execution/evidence_photo_count.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/photo_sequence_screen.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/routing/map_home_screen.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';

import '../routing/map_home_harness.dart';
import '../support/fake_evidence_camera.dart';
import '../support/fake_route_repository.dart';

// The conclusion sheet (redesign §6.6): one optional observation for every
// stop, sent as `complaints_suggestions` on the check-out, and nothing
// written before the exit QR is read.

RouteSummary _route({bool requiresEvidence = false}) => routeWith(
  stops: [
    stopIn(
      id: 's1',
      status: 'IN_PROGRESS',
      buildingName: 'Central de Aulas',
      floorLabel: '1º andar',
      requiresEvidence: requiresEvidence,
    ),
  ],
);

/// Two photos already in the outbox for `exec-1`, so an evidence stop may
/// conclude.
Future<InMemoryLocalWriteStore> _storeWithTwoPhotos() async {
  final store = InMemoryLocalWriteStore();
  for (final id in ['p1', 'p2']) {
    await store.enqueue(
      id: id,
      kind: PendingOpKind.evidencePhoto,
      routeId: 'r1',
      payload: {
        'execution_id': 'exec-1',
        'bytes_b64': base64Encode(onePixelPng),
        'sha256': 'abc',
        'captured_at': DateTime.utc(2026, 10, 28, 9).toIso8601String(),
        'idempotency_key': id,
      },
    );
  }
  return store;
}

Future<InMemoryLocalWriteStore> _pump(
  WidgetTester tester, {
  bool requiresEvidence = false,
  FakeEvidenceCamera? camera,
}) async {
  final store = await _storeWithTwoPhotos();
  await pumpHome(
    tester,
    homeWith(
      repositoryWith(_route(requiresEvidence: requiresEvidence)),
      stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
      localWriteStore: store,
      evidenceCamera: camera,
    ),
  );
  return store;
}

Future<List<PendingOperationRow>> _checkOuts(
  InMemoryLocalWriteStore store,
) async => (await store.unsyncedForRoute(
  'r1',
)).where((row) => row.kind == PendingOpKind.checkOut).toList();

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MapHomeScreen)));

VoidCallback? _scanExitPressed(WidgetTester tester) => tester
    .widget<ButtonStyleButton>(find.byKey(const ValueKey('conclude-scan-exit')))
    .onPressed;

void main() {
  for (final requiresEvidence in [true, false]) {
    testWidgets(
      'conclude sheet has exactly one text field labelled "Observação '
      '(opcional)" with helper "Reclamações e sugestões também vão aqui" and '
      'maxLength 2000 (requires_evidence: $requiresEvidence)',
      (tester) async {
        await _pump(tester, requiresEvidence: requiresEvidence);

        await tapInSheet(tester, blockConcludeButton());

        expect(
          find.text(
            AppStrings.concludeSheetTitle('Central de Aulas', '1º andar'),
          ),
          findsOneWidget,
        );
        expect(find.byType(TextField), findsOneWidget);
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.maxLength, 2000);
        expect(field.decoration?.labelText, 'Observação (opcional)');
        expect(
          field.decoration?.helperText,
          'Reclamações e sugestões também vão aqui',
        );
        expect(find.text('Escanear QR de saída'), findsOneWidget);
        expect(find.byType(ScanScreen), findsNothing);
      },
    );
  }

  testWidgets(
    'observation travels as complaints_suggestions on the check-out',
    (tester) async {
      final store = await _pump(tester);

      await concludeWith(tester, 'v1.floor.1.sig', observation: 'pia entupida');

      final checkOut = (await _checkOuts(store)).single;
      expect(checkOut.payload['complaints_suggestions'], 'pia entupida');
      final kinds = (await store.unsyncedForRoute('r1')).map((r) => r.kind);
      expect(kinds, isNot(contains(PendingOpKind.evidenceNote)));
    },
  );

  testWidgets('blank observation sends no complaints_suggestions key', (
    tester,
  ) async {
    final store = await _pump(tester);

    await concludeWith(tester, 'v1.floor.1.sig', observation: '   ');

    final checkOut = (await _checkOuts(store)).single;
    expect(checkOut.payload.containsKey('complaints_suggestions'), isFalse);
  });

  testWidgets('cancelling the exit QR enqueues nothing and brings the sheet '
      'back with the text (ruling R12)', (tester) async {
    final store = await _pump(tester);

    // concludeWith pops the scanner with null and settles: no tap after.
    await concludeWith(tester, null, observation: 'pia entupida');

    expect(find.byType(ScanScreen), findsNothing);
    expect(find.text(AppStrings.concludeScanExitButton), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'pia entupida');
    expect(await _checkOuts(store), isEmpty);

    // The loop goes on: scan again from the same sheet, now with a QR.
    await tester.tap(find.text(AppStrings.concludeScanExitButton));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(ScanScreen))).pop('v1.floor.1.s');
    await tester.pumpAndSettle();
    final sent = (await _checkOuts(store)).single;
    expect(sent.payload['complaints_suggestions'], 'pia entupida');
  });

  testWidgets('a successful check-out clears the observation', (tester) async {
    await _pump(tester);
    final container = _container(tester);

    await concludeWith(tester, 'v1.floor.1.sig', observation: 'pia entupida');

    expect(container.read(observationDraftProvider('s1')), isEmpty);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the sent text never exceeds 2000 code points', (tester) async {
    final store = await _pump(tester);
    // One grapheme, seven code points (four emoji and three joiners): the
    // field's own limit counts graphemes, the backend counts code points.
    const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}';
    expect(family.runes.length, 7);

    await tapInSheet(tester, blockConcludeButton());
    await tester.enterText(find.byType(TextField), family * 400);
    await tester.pump();
    expect(find.text('2000/2000'), findsOneWidget);
    await tester.tap(find.text(AppStrings.concludeScanExitButton));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(ScanScreen))).pop('v1.floor.1.s');
    await tester.pumpAndSettle();

    final sent = (await _checkOuts(store)).single;
    expect(
      (sent.payload['complaints_suggestions'] as String).runes.length,
      2000,
    );
  });

  testWidgets('a requires_evidence stop that drops to 1 photo closes '
      '"Escanear QR de saída" with "Falta 1 foto"', (tester) async {
    final store = await _pump(tester, requiresEvidence: true);
    await tapInSheet(tester, blockConcludeButton());
    expect(_scanExitPressed(tester), isNotNull);

    // A photo goes while the sheet is open (as "Tirar mais" → "Apagar"
    // would); the count is re-read the way the photo sequence does it.
    await store.deletePendingPhoto('p2');
    _container(tester)
      ..invalidate(localPhotoCountProvider('exec-1'))
      ..invalidate(stopEvidenceProvider(('r1', 'exec-1')));
    await tester.pumpAndSettle();

    expect(_scanExitPressed(tester), isNull);
    expect(find.text('Falta 1 foto'), findsWidgets);
  });

  testWidgets('cancelling the sheet enqueues nothing', (tester) async {
    final store = await _pump(tester);

    await tapInSheet(tester, blockConcludeButton());
    await tester.tap(find.text(AppStrings.commonCancel));
    await tester.pumpAndSettle();

    expect(find.byType(ScanScreen), findsNothing);
    expect(await _checkOuts(store), isEmpty);
  });

  testWidgets('the summary shows the photo count and "Tirar mais" opens the '
      'photo sequence', (tester) async {
    await _pump(tester, camera: FakeEvidenceCamera());

    await tapInSheet(tester, blockConcludeButton());
    expect(find.text(AppStrings.photoSequenceCounter(2)), findsWidgets);
    await tester.tap(find.text('Tirar mais'));
    await tester.pumpAndSettle();

    expect(find.byType(PhotoSequenceScreen), findsOneWidget);
  });

  testWidgets('signalling the stop impeded forgets its observation', (
    tester,
  ) async {
    await _pump(tester);
    final container = _container(tester);
    container.read(observationDraftProvider('s1').notifier).write('pia');

    await openStopSheet(tester, 's1');
    await tapInSheet(
      tester,
      find.widgetWithText(
        TextButton,
        AppStrings.routeSignalImpossibilityButton,
      ),
    );
    await tester.tap(find.text(AppStrings.impedimentReasonSiteRefusal));
    // "Confirmar" opens only once the chosen reason is drawn.
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.routeImpedimentReported), findsOneWidget);
    expect(container.read(observationDraftProvider('s1')), isEmpty);
  });

  testWidgets('a stop that comes back released forgets its observation', (
    tester,
  ) async {
    final repository = repositoryWith(_route());
    await pumpHome(tester, homeWith(repository));
    final container = _container(tester);
    container.read(observationDraftProvider('s1').notifier).write('pia');

    repository.day = myDayWith(
      routeWith(
        stops: [
          stopIn(id: 's1', status: 'RELEASED', releaseReason: 'IMPEDIMENT'),
        ],
      ),
    );
    container.invalidate(myDayProvider);
    await tester.pumpAndSettle();

    expect(container.read(observationDraftProvider('s1')), isEmpty);
  });
}
