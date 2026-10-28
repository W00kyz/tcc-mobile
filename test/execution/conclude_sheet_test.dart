import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/execution/photo_sequence_screen.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart';
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

  testWidgets('cancelling the exit QR enqueues nothing and keeps the text', (
    tester,
  ) async {
    final store = await _pump(tester);

    await concludeWith(tester, null, observation: 'pia entupida');

    expect(await _checkOuts(store), isEmpty);
    await tapInSheet(tester, blockConcludeButton());
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'pia entupida');
  });

  testWidgets('a successful check-out clears the observation', (tester) async {
    await _pump(tester);
    await concludeWith(tester, null, observation: 'pia entupida');

    await concludeWith(tester, 'v1.floor.1.sig');

    expect(find.text('pia entupida'), findsNothing);
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
}
