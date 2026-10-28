import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/routing/route_repository.dart';

import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';

// Ported from the deleted route_screen_test.dart: the photo gate of a stop
// that requires evidence (spec 2026-10-26-exige-evidencias). Task 9 moves it
// to the in-progress block.

Finder _concluir() =>
    find.widgetWithText(TextButton, AppStrings.routeConcludeButton);

Finder _addPhoto() =>
    find.widgetWithText(TextButton, AppStrings.routeAddPhotoButton);

/// An [EvidenceApi] whose `listEvidence` always throws [error] — the device
/// is offline, or the server answered an HTTP error.
class _FailingEvidenceApi extends FakeEvidenceApi {
  _FailingEvidenceApi(this.error);

  /// A dropped connection: no HTTP response at all.
  factory _FailingEvidenceApi.offline() => _FailingEvidenceApi(
    DioException.connectionError(
      requestOptions: RequestOptions(path: '/executions/x/evidence'),
      reason: 'offline',
    ),
  );

  /// The server answered [status].
  factory _FailingEvidenceApi.http(int status) {
    final request = RequestOptions(path: '/executions/x/evidence');
    return _FailingEvidenceApi(
      DioException.badResponse(
        statusCode: status,
        requestOptions: request,
        response: Response<void>(requestOptions: request, statusCode: status),
      ),
    );
  }

  final DioException error;

  @override
  Future<List<EvidenceItem>> listEvidence(String executionId) async =>
      throw error;
}

void main() {
  group('a stop that requires evidence', () {
    RouteSummary requiringRoute() => routeWith(
      stops: [stopIn(id: 's1', status: 'IN_PROGRESS', requiresEvidence: true)],
    );

    /// A photo still waiting in the outbox for `exec-1`.
    Future<void> enqueuePhoto(InMemoryLocalWriteStore store, String id) =>
        store.enqueue(
          id: id,
          kind: PendingOpKind.evidencePhoto,
          routeId: 'r1',
          payload: {
            'execution_id': 'exec-1',
            'bytes_b64': base64Encode(onePixelPng),
            'sha256': 'abc',
            'captured_at': DateTime.utc(2026, 8, 25, 9).toIso8601String(),
            'idempotency_key': id,
          },
        );

    Future<InMemoryLocalWriteStore> pumpWith(
      WidgetTester tester, {
      int pendingPhotos = 0,
      int syncedPhotos = 0,
      EvidenceApi? evidenceApi,
    }) async {
      // A fresh tree, so a second call in one test starts from scratch.
      await tester.pumpWidget(const SizedBox());
      final store = InMemoryLocalWriteStore();
      for (var i = 0; i < pendingPhotos; i++) {
        await enqueuePhoto(store, 'p$i');
      }
      // Delivered photos stay in the outbox, state `synced`.
      for (var i = 0; i < syncedPhotos; i++) {
        await enqueuePhoto(store, 's$i');
        await store.markSynced('s$i');
      }
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(requiringRoute()),
          stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
          evidenceApi: evidenceApi,
          localWriteStore: store,
        ),
      );
      return store;
    }

    testWidgets('with 1 photo shows the hint and a disabled "Concluir"', (
      tester,
    ) async {
      await pumpWith(tester, pendingPhotos: 1);

      expect(find.text(AppStrings.evidenceMissingHint(1)), findsOneWidget);
      expect(find.text('Tire pelo menos 2 fotos (faltam 1)'), findsOneWidget);
      expect(tester.widget<TextButton>(_concluir()).onPressed, isNull);
    });

    // The gate reads the device's own outbox: no network answer, good or
    // bad, may stall or undercount it (spec §6.4, SQLite is the truth).
    testWidgets('offline, 1 delivered + 1 pending photo enable "Concluir"', (
      tester,
    ) async {
      await pumpWith(
        tester,
        pendingPhotos: 1,
        syncedPhotos: 1,
        evidenceApi: _FailingEvidenceApi.offline(),
      );

      expect(tester.widget<TextButton>(_concluir()).onPressed, isNotNull);
      expect(find.textContaining('Tire pelo menos'), findsNothing);
    });

    testWidgets('an HTTP 500 on the list does not stall the count', (
      tester,
    ) async {
      await pumpWith(
        tester,
        pendingPhotos: 2,
        evidenceApi: _FailingEvidenceApi.http(500),
      );
      expect(tester.widget<TextButton>(_concluir()).onPressed, isNotNull);

      await pumpWith(
        tester,
        pendingPhotos: 1,
        evidenceApi: _FailingEvidenceApi.http(500),
      );
      expect(tester.widget<TextButton>(_concluir()).onPressed, isNull);
      expect(find.text(AppStrings.evidenceMissingHint(1)), findsOneWidget);
    });

    testWidgets('the 10-photo cap counts the local photos, list or no list', (
      tester,
    ) async {
      await pumpWith(
        tester,
        pendingPhotos: 5,
        syncedPhotos: 5,
        evidenceApi: _FailingEvidenceApi.http(404),
      );
      expect(tester.widget<TextButton>(_addPhoto()).onPressed, isNull);

      await pumpWith(
        tester,
        pendingPhotos: 5,
        syncedPhotos: 4,
        evidenceApi: _FailingEvidenceApi.http(404),
      );
      expect(tester.widget<TextButton>(_addPhoto()).onPressed, isNotNull);
    });

    testWidgets('counts a pending photo together with a synced one', (
      tester,
    ) async {
      await pumpWith(
        tester,
        pendingPhotos: 1,
        evidenceApi: FakeEvidenceApi(
          syncedItems: [
            EvidenceItem(
              id: 'e1',
              kind: 'PHOTO',
              capturedAt: DateTime.utc(2026, 8, 25, 8, 30),
              createdAt: DateTime.utc(2026, 8, 25, 8, 30),
            ),
          ],
        ),
      );

      expect(find.textContaining('Tire pelo menos'), findsNothing);
      expect(tester.widget<TextButton>(_concluir()).onPressed, isNotNull);
    });

    testWidgets('disables "Adicionar foto" at the 10-photo cap', (
      tester,
    ) async {
      await pumpWith(tester, pendingPhotos: 10);

      expect(tester.widget<TextButton>(_addPhoto()).onPressed, isNull);
    });

    testWidgets('"Concluir" asks for complaints first and "Cancelar" '
        'enqueues nothing', (tester) async {
      final store = await pumpWith(tester, pendingPhotos: 2);

      await tapInSheet(tester, _concluir());
      expect(find.text(AppStrings.complaintsDialogTitle), findsOneWidget);
      expect(find.byType(ScanScreen), findsNothing);

      await tester.tap(find.text(AppStrings.commonCancel));
      await tester.pumpAndSettle();

      expect(find.byType(ScanScreen), findsNothing);
      final kinds = (await store.unsyncedForRoute('r1')).map((r) => r.kind);
      expect(kinds, isNot(contains(PendingOpKind.checkOut)));
    });

    testWidgets('"Continuar" scans and enqueues the check-out with the '
        'typed text', (tester) async {
      final store = await pumpWith(tester, pendingPhotos: 2);

      await tapInSheet(tester, _concluir());
      await tester.enterText(find.byType(TextField), 'Falta papel');
      await tester.tap(find.text(AppStrings.complaintsContinue));
      await tester.pumpAndSettle();
      expect(find.byType(ScanScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(ScanScreen))).pop('v1.floor.1.s');
      await tester.pumpAndSettle();

      final checkOut = (await store.unsyncedForRoute(
        'r1',
      )).singleWhere((r) => r.kind == PendingOpKind.checkOut);
      expect(checkOut.payload['complaints_suggestions'], 'Falta papel');
    });
  });
}
