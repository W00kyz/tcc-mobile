import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/routing/route_repository.dart';

import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';

// Ported from the deleted route_screen_test.dart: "Sinalizar
// impossibilidade", now a modal sheet (redesign §6.12) opened from a stop
// row of the home's sheet.

RouteSummary _pendingRoute() => routeWith(stops: [stopIn(id: 's1')]);

RouteSummary _inProgressStopRoute() => routeWith(
  stops: [stopIn(id: 's1', status: 'IN_PROGRESS')],
);

Finder _signalButton() =>
    find.widgetWithText(TextButton, AppStrings.routeSignalImpossibilityButton);

void main() {
  group('"Sinalizar impossibilidade"', () {
    testWidgets(
      'on an IN_PROGRESS stop, picking a reason and confirming enqueues an '
      'impediment row scoped to that stop',
      (tester) async {
        final store = InMemoryLocalWriteStore();
        await pumpHome(
          tester,
          homeWith(
            repositoryWith(_inProgressStopRoute()),
            localWriteStore: store,
          ),
        );

        await tapInSheet(tester, _signalButton());

        // A modal sheet now (redesign §6.12), with the same options.
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(
          find.text(AppStrings.impedimentReasonAccessBlocked),
          findsOneWidget,
        );
        expect(find.text('Não consigo fazer este ponto'), findsOneWidget);
        // Offered even on the last stop: "can't go on today" is how the
        // worker ends the day — a STOP impediment there would pull the next
        // batch.
        expect(find.text('Não consigo continuar hoje'), findsOneWidget);

        // Regression: the note field is capped at the backend `note` column
        // (`String(500)`) so an over-long note can't poison the sync queue.
        expect(tester.widget<TextField>(find.byType(TextField)).maxLength, 500);

        await tester.tap(find.text(AppStrings.impedimentReasonSiteRefusal));
        await tester.enterText(find.byType(TextField), 'Portão fechado.');
        await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
        await tester.pumpAndSettle();

        final rows = await store.unsyncedForRoute('r1');
        expect(rows, hasLength(1));
        expect(rows.single.kind, PendingOpKind.impediment);
        expect(rows.single.payload['scope'], 'STOP');
        expect(rows.single.payload['route_stop_id'], 's1');
        expect(rows.single.payload['reason'], 'SITE_REFUSAL');
        expect(rows.single.payload['note'], 'Portão fechado.');
        expect(find.text(AppStrings.routeImpedimentReported), findsOneWidget);
      },
    );

    testWidgets(
      'with two or more PENDING stops left, flipping the "resto da rota" '
      'switch enqueues a ROUTE_REMAINDER impediment with a null '
      'route_stop_id',
      (tester) async {
        final store = InMemoryLocalWriteStore();
        final route = routeWith(
          stops: [
            stopIn(id: 's1', status: 'IN_PROGRESS'),
            stopIn(id: 's2', orderIndex: 2),
            stopIn(id: 's3', orderIndex: 3),
          ],
        );
        await pumpHome(
          tester,
          homeWith(repositoryWith(route), localWriteStore: store),
        );

        // s1 (IN_PROGRESS) plus s2/s3 (PENDING) each carry the action — the
        // first is s1, the stop this report is about.
        await tapInSheet(tester, _signalButton().first);

        await tester.tap(find.text(AppStrings.impedimentReasonHealthIssue));
        await tester.tap(find.text(AppStrings.impedimentRemainderSwitch));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
        await tester.pumpAndSettle();

        final rows = await store.unsyncedForRoute('r1');
        expect(rows, hasLength(1));
        expect(rows.single.payload['scope'], 'ROUTE_REMAINDER');
        expect(rows.single.payload['route_stop_id'], isNull);
        expect(rows.single.payload['reason'], 'HEALTH_ISSUE');
        expect(rows.single.payload['note'], isNull);
      },
    );

    testWidgets('cancelling the impediment sheet enqueues nothing', (
      tester,
    ) async {
      final store = InMemoryLocalWriteStore();
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(_inProgressStopRoute()),
          localWriteStore: store,
        ),
      );

      await tapInSheet(tester, _signalButton());
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await tester.pumpAndSettle();

      expect(await store.unsyncedForRoute('r1'), isEmpty);
      expect(find.text(AppStrings.routeImpedimentReported), findsNothing);
    });

    testWidgets(
      'on a not-yet-reached (PENDING) stop enqueues a STOP-scoped impediment '
      'for that stop — a worker who cannot reach the stop to scan the QR '
      'must still be able to signal it',
      (tester) async {
        final store = InMemoryLocalWriteStore();
        await pumpHome(
          tester,
          homeWith(repositoryWith(_pendingRoute()), localWriteStore: store),
        );

        await tapInSheet(tester, _signalButton());
        await tester.tap(find.text(AppStrings.impedimentReasonAccessBlocked));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
        await tester.pumpAndSettle();

        final rows = await store.unsyncedForRoute('r1');
        expect(rows, hasLength(1));
        expect(rows.single.kind, PendingOpKind.impediment);
        expect(rows.single.payload['scope'], 'STOP');
        expect(rows.single.payload['route_stop_id'], 's1');
        expect(find.text(AppStrings.routeImpedimentReported), findsOneWidget);
      },
    );

    testWidgets(
      'an impediment on the last open stop reloads the day once it synced, '
      'and the released stop lets the next batch in',
      (tester) async {
        final secondBatch = routeWith(
          currentBatch: 2,
          stops: [
            stopWith(id: 's1', status: 'DONE', servicePointName: 'Sala 101'),
            stopWith(
              id: 's2',
              orderIndex: 2,
              batchNumber: 2,
              servicePointName: 'Sala 202',
            ),
          ],
        );
        final store = InMemoryLocalWriteStore();
        final repository = repositoryWith(
          routeWith(
            stops: [stopWith(id: 's1', servicePointName: 'Sala 101')],
          ),
        );
        repository.allocate = () {
          repository.day = myDayWith(secondBatch);
          return AllocationResult(route: secondBatch, poolEmpty: false);
        };
        await pumpHome(
          tester,
          homeWith(
            repository,
            localWriteStore: store,
            syncWorker: RecordingSyncWorker(drains: store),
          ),
        );

        await tapInSheet(tester, _signalButton());
        await tester.tap(find.text(AppStrings.impedimentReasonAccessBlocked));
        await tester.pumpAndSettle();
        // What the server reports once it has the impediment.
        repository.day = myDayWith(
          routeWith(
            stops: [
              stopWith(
                id: 's1',
                status: 'RELEASED',
                releaseReason: 'IMPEDIMENT',
                servicePointName: 'Sala 101',
              ),
            ],
          ),
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
        await tester.pumpAndSettle();

        expect(repository.allocationCalls, ['nextBatch:r1']);
        expect(find.text('Sala 202'), findsOneWidget);
      },
    );
  });
}
