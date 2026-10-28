import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/routing/route_repository.dart';

import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';

// Ported from the deleted route_screen_test.dart: the photo gate of a stop
// that requires evidence (spec 2026-10-26-exige-evidencias), now on the
// in-progress block (redesign §6.2).

Finder _concluir() => blockConcludeButton();

Finder _addPhoto() => blockTakePhotosButton();

VoidCallback? _onPressed(WidgetTester tester, Finder button) =>
    tester.widget<ButtonStyleButton>(button).onPressed;

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

    testWidgets('with 1 photo shows "Falta 1 foto" and a disabled "Concluir"', (
      tester,
    ) async {
      await pumpWith(tester, pendingPhotos: 1);

      expect(find.text(AppStrings.missingPhotos(1)), findsOneWidget);
      expect(find.text('Falta 1 foto'), findsOneWidget);
      expect(_onPressed(tester, _concluir()), isNull);
    });

    testWidgets('with no photo says "Faltam 2 fotos" (ruling R11)', (
      tester,
    ) async {
      await pumpWith(tester);

      expect(find.text('Faltam 2 fotos'), findsOneWidget);
      expect(_onPressed(tester, _concluir()), isNull);
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

      expect(_onPressed(tester, _concluir()), isNotNull);
      expect(find.textContaining('Falta'), findsNothing);
    });

    testWidgets('an HTTP 500 on the list does not stall the count', (
      tester,
    ) async {
      await pumpWith(
        tester,
        pendingPhotos: 2,
        evidenceApi: _FailingEvidenceApi.http(500),
      );
      expect(_onPressed(tester, _concluir()), isNotNull);

      await pumpWith(
        tester,
        pendingPhotos: 1,
        evidenceApi: _FailingEvidenceApi.http(500),
      );
      expect(_onPressed(tester, _concluir()), isNull);
      expect(find.text(AppStrings.missingPhotos(1)), findsOneWidget);
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
      expect(_onPressed(tester, _addPhoto()), isNull);

      await pumpWith(
        tester,
        pendingPhotos: 5,
        syncedPhotos: 4,
        evidenceApi: _FailingEvidenceApi.http(404),
      );
      expect(_onPressed(tester, _addPhoto()), isNotNull);
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

      expect(find.textContaining('Falta'), findsNothing);
      expect(_onPressed(tester, _concluir()), isNotNull);
    });

    testWidgets('disables "Tirar fotos" at the 10-photo cap', (
      tester,
    ) async {
      await pumpWith(tester, pendingPhotos: 10);

      expect(_onPressed(tester, _addPhoto()), isNull);
    });
  });
}
