import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/evidence_capture.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/routing/route_repository.dart';

import '../support/fake_network_images.dart';
import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';

// Ported from the deleted route_screen_test.dart: an IN_PROGRESS stop's
// "Concluir" (check-out), evidence buttons and list. Tasks 8 and 9 replace
// this block with the photo sequence and the conclusion sheet.

RouteSummary _inProgressStopRoute() => routeWith(
  stops: [
    stopIn(id: 's1', status: 'IN_PROGRESS', servicePointName: 'Sala 101'),
  ],
);

Finder _concluir() =>
    find.widgetWithText(TextButton, AppStrings.routeConcludeButton);

Finder _addPhoto() =>
    find.widgetWithText(TextButton, AppStrings.routeAddPhotoButton);

Finder _addNote() =>
    find.widgetWithText(TextButton, AppStrings.routeAddNoteButton);

void main() {
  testWidgets('shows "Concluir" only for an IN_PROGRESS stop, not a PENDING '
      'one', (tester) async {
    await pumpHome(
      tester,
      homeWith(repositoryWith(routeWith(stops: [stopIn(id: 's1')]))),
    );

    expect(_concluir(), findsNothing);
  });

  testWidgets('an IN_PROGRESS stop offers "Concluir"', (tester) async {
    await pumpHome(
      tester,
      homeWith(
        repositoryWith(_inProgressStopRoute()),
        stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
      ),
    );

    expect(tester.widget<TextButton>(_concluir()).onPressed, isNotNull);
  });

  testWidgets(
    'runs the check-out flow end-to-end: scans, checks out, reloads the day '
    'and shows success',
    (tester) async {
      final store = InMemoryLocalWriteStore();
      final repository = repositoryWith(_inProgressStopRoute());
      await pumpHome(tester, homeWith(repository, localWriteStore: store));
      expect(repository.fetchCount, 1);

      await concludeWith(tester, 'v1.floor.1.sig');
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

  testWidgets('a stop without the flag concludes with no dialog', (
    tester,
  ) async {
    await pumpHome(tester, homeWith(repositoryWith(_inProgressStopRoute())));

    await tapInSheet(tester, _concluir());

    expect(find.text(AppStrings.complaintsDialogTitle), findsNothing);
    expect(find.byType(ScanScreen), findsOneWidget);
  });

  testWidgets(
    'hides the evidence buttons for an IN_PROGRESS stop with no '
    'OpenExecutions row (Ruling 17 cold-start gap)',
    (tester) async {
      await pumpHome(tester, homeWith(repositoryWith(_inProgressStopRoute())));

      expect(find.text(AppStrings.routeAddPhotoButton), findsNothing);
      expect(find.text(AppStrings.routeAddNoteButton), findsNothing);
    },
  );

  testWidgets(
    'shows the evidence buttons for an IN_PROGRESS stop once its '
    'OpenExecutions row resolves',
    (tester) async {
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(_inProgressStopRoute()),
          stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
        ),
      );

      expect(_addPhoto(), findsOneWidget);
      expect(_addNote(), findsOneWidget);
    },
  );

  testWidgets(
    'renders all three stop states side by side with the right affordances: '
    'DONE reads done and has no action, IN_PROGRESS gets "Concluir" plus '
    'evidence actions, PENDING gets only "Sinalizar" and the sheet-level '
    '"Escanear QR"',
    (tester) async {
      final route = routeWith(
        stops: [
          stopIn(id: 's1', status: 'DONE', servicePointName: 'Sala 101'),
          stopIn(
            id: 's2',
            orderIndex: 2,
            status: 'IN_PROGRESS',
            servicePointName: 'Sala 102',
          ),
          stopIn(id: 's3', orderIndex: 3, servicePointName: 'Sala 103'),
        ],
      );
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(route),
          stopProgressStore: FakeStopProgressStore({'s2': 'exec-1'}),
        ),
      );

      expect(find.text('Sala 101'), findsOneWidget);
      expect(find.text('Sala 102'), findsOneWidget);
      expect(find.text('Sala 103'), findsOneWidget);
      // DONE (s1) reads done, by word as well as by stamp.
      expect(find.text(AppStrings.slotDoneNoHour), findsOneWidget);
      // IN_PROGRESS (s2): "Concluir" plus both evidence actions, exactly one
      // of each across the whole list.
      expect(_concluir(), findsOneWidget);
      expect(_addPhoto(), findsOneWidget);
      expect(_addNote(), findsOneWidget);
      // s2 and s3 can be signalled, s1 cannot.
      expect(
        find.widgetWithText(
          TextButton,
          AppStrings.routeSignalImpossibilityButton,
        ),
        findsNWidgets(2),
      );
      // PENDING has a sheet-level entry point, not a per-stop button.
      expect(scanQrButton(), findsOneWidget);
    },
  );

  testWidgets(
    'a local IN_PROGRESS StopProgress overrides a server PENDING stop — the '
    'row renders the in-progress affordances (Concluir + evidence)',
    (tester) async {
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(routeWith(stops: [stopIn(id: 's1')])),
          stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
        ),
      );

      expect(_concluir(), findsOneWidget);
      expect(_addPhoto(), findsOneWidget);
      expect(find.text(AppStrings.slotInProgress), findsWidgets);
    },
  );

  testWidgets(
    'tapping "Adicionar foto" captures, enqueues the photo and shows success',
    (tester) async {
      final store = InMemoryLocalWriteStore();
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(_inProgressStopRoute()),
          stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
          localWriteStore: store,
          evidenceCapture: FakeEvidenceCapture(
            // A real (1x1) PNG — the pending row renders as an Image.memory
            // thumbnail in the evidence list, which decodes eagerly.
            photo: CapturedPhoto(bytes: onePixelPng, sha256: 'abc123'),
          ),
        ),
      );

      await tapInSheet(tester, _addPhoto());

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
      final evidenceApi = FakeEvidenceApi();
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(_inProgressStopRoute()),
          stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
          evidenceApi: evidenceApi,
          evidenceCapture: FakeEvidenceCapture(),
        ),
      );

      await tapInSheet(tester, _addPhoto());

      expect(evidenceApi.uploadedPhotoExecutionIds, isEmpty);
      expect(find.text(AppStrings.routePhotoAdded), findsNothing);
      expect(find.text(AppStrings.routePhotoAddError), findsNothing);
    },
  );

  testWidgets(
    'shows a failure snackbar when the camera itself throws (e.g. '
    'compression failed)',
    (tester) async {
      final evidenceApi = FakeEvidenceApi();
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(_inProgressStopRoute()),
          stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
          evidenceApi: evidenceApi,
          evidenceCapture: FakeEvidenceCapture(
            error: StateError('Photo compression failed for "x.jpg".'),
          ),
        ),
      );

      await tapInSheet(tester, _addPhoto());

      expect(evidenceApi.uploadedPhotoExecutionIds, isEmpty);
      expect(find.text(AppStrings.routePhotoAddError), findsOneWidget);
    },
  );

  testWidgets(
    'tapping "Adicionar observação" opens a dialog and "Salvar" enqueues the '
    'note',
    (tester) async {
      final store = InMemoryLocalWriteStore();
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(_inProgressStopRoute()),
          stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
          localWriteStore: store,
        ),
      );

      await tapInSheet(tester, _addNote());

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

  testWidgets('cancelling the note dialog uploads nothing', (tester) async {
    final evidenceApi = FakeEvidenceApi();
    await pumpHome(
      tester,
      homeWith(
        repositoryWith(_inProgressStopRoute()),
        stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
        evidenceApi: evidenceApi,
      ),
    );

    await tapInSheet(tester, _addNote());
    await tester.enterText(find.byType(TextField), 'not saved');
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();

    expect(evidenceApi.uploadedNoteTexts, isEmpty);
    expect(find.text(AppStrings.routeNoteAdded), findsNothing);
  });

  testWidgets(
    'renders a synced note from the backend and a pending local photo '
    'together, each with its own sync icon',
    (tester) async {
      final localStore = InMemoryLocalWriteStore();
      await localStore.enqueue(
        id: 'op-photo-1',
        kind: PendingOpKind.evidencePhoto,
        routeId: 'r1',
        payload: {
          'execution_id': 'exec-1',
          // A real (1x1) PNG, not arbitrary bytes: Image.memory decodes this
          // eagerly, and flutter_test surfaces a decode failure as an
          // uncaught test error rather than a rendering glitch.
          'bytes_b64': base64Encode(onePixelPng),
          'sha256': 'abc123',
          'captured_at': '2026-08-25T08:05:00.000Z',
        },
      );
      final evidenceApi = FakeEvidenceApi(
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
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(_inProgressStopRoute()),
          stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
          evidenceApi: evidenceApi,
          localWriteStore: localStore,
        ),
      );

      expect(find.text('Sala trancada.'), findsOneWidget);
      expect(find.text(AppStrings.routeEvidencePhotoLabel), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done), findsOneWidget);
      expect(find.byIcon(Icons.cloud_upload), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    },
  );

  for (final withSession in [true, false]) {
    testWidgets(
      'renders a synced PHOTO evidence item as a NetworkImage built from the '
      'configured base URL + contentUrl, '
      '${withSession ? 'with a bearer-token header' : 'with no headers and '
                'no session'}',
      (tester) async {
        await withMockedNetworkImages(onePixelPng, () async {
          final evidenceApi = FakeEvidenceApi(
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
          await pumpHome(
            tester,
            homeWith(
              repositoryWith(_inProgressStopRoute()),
              stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
              evidenceApi: evidenceApi,
              apiBaseUrl: 'http://test-base',
              session: withSession
                  ? const Session(
                      accessToken: 'test-token',
                      refreshToken: 'test-refresh-token',
                      role: 'FIELD_WORKER',
                    )
                  : null,
            ),
          );

          final image = tester.widget<Image>(find.byType(Image));
          final provider = image.image as NetworkImage;
          expect(provider.url, 'http://test-base/evidence/e1/content');
          expect(
            provider.headers,
            withSession ? {'Authorization': 'Bearer test-token'} : isNull,
          );
        });
      },
    );
  }
}
