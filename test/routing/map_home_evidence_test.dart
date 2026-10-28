import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/photo_sequence_screen.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/routing/route_repository.dart';

import '../support/fake_evidence_camera.dart';
import '../support/fake_network_images.dart';
import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';

// Ported from the deleted route_screen_test.dart: an IN_PROGRESS stop's
// "Concluir" (check-out) and its photos, now through the in-progress block
// (redesign §6.2) and the conclusion sheet (§6.6, conclude_sheet_test.dart).

RouteSummary _inProgressStopRoute() => routeWith(
  stops: [
    stopIn(id: 's1', status: 'IN_PROGRESS', servicePointName: 'Sala 101'),
  ],
);

Finder _concluir() =>
    find.widgetWithText(TextButton, AppStrings.routeConcludeButton);

Finder _addPhoto() => blockTakePhotosButton();

VoidCallback? _onPressed(WidgetTester tester, Finder button) =>
    tester.widget<ButtonStyleButton>(button).onPressed;

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

  testWidgets('"Concluir" opens the conclusion sheet, not the scanner', (
    tester,
  ) async {
    await pumpHome(tester, homeWith(repositoryWith(_inProgressStopRoute())));

    await tapInSheet(tester, _concluir());

    expect(find.text(AppStrings.concludeScanExitButton), findsOneWidget);
    expect(find.byType(ScanScreen), findsNothing);
  });

  testWidgets(
    'disables "Tirar fotos" for an IN_PROGRESS stop with no '
    'OpenExecutions row (Ruling 17 cold-start gap)',
    (tester) async {
      await pumpHome(tester, homeWith(repositoryWith(_inProgressStopRoute())));

      expect(_onPressed(tester, _addPhoto()), isNull);
    },
  );

  testWidgets(
    'enables "Tirar fotos" for an IN_PROGRESS stop once its '
    'OpenExecutions row resolves',
    (tester) async {
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(_inProgressStopRoute()),
          stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
        ),
      );

      expect(_onPressed(tester, _addPhoto()), isNotNull);
    },
  );

  testWidgets(
    'renders all three stop states side by side with the right affordances: '
    'DONE reads done and has no action, IN_PROGRESS gets "Concluir" and '
    'the in-progress block, PENDING gets only "Sinalizar" and the sheet-level '
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
      // IN_PROGRESS (s2): one row "Concluir" and one block, with its photos
      // action.
      expect(_concluir(), findsOneWidget);
      expect(blockConcludeButton(), findsOneWidget);
      expect(_addPhoto(), findsOneWidget);
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
    'row renders the in-progress affordances (Concluir + the block)',
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
    'tapping "Tirar fotos" opens the photo sequence for the stop',
    (tester) async {
      final camera = FakeEvidenceCamera();
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(_inProgressStopRoute()),
          stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
          evidenceCamera: camera,
        ),
      );

      await tapInSheet(tester, _addPhoto());

      expect(find.byType(PhotoSequenceScreen), findsOneWidget);
      expect(find.byKey(const Key('fake-preview')), findsOneWidget);
    },
  );

  testWidgets('the block shows a pending local photo as a thumbnail', (
    tester,
  ) async {
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
    await pumpHome(
      tester,
      homeWith(
        repositoryWith(_inProgressStopRoute()),
        stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
        localWriteStore: localStore,
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.text(AppStrings.photoSequenceCounter(1)), findsOneWidget);
  });

  for (final withSession in [true, false]) {
    testWidgets(
      'the block renders a synced photo as a NetworkImage built from the '
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
