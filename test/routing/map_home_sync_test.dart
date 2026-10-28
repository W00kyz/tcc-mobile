import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/routing/blocked_sync_screen.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/sync_status.dart';

import '../support/fake_connectivity.dart';
import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';

// Ported from the deleted route_screen_test.dart: the sync state (now the
// top-bar indicator and its detail sheet), the per-stop outbox chips and the
// next-batch pull.

RouteSummary _pendingRoute() => routeWith(stops: [stopIn(id: 's1')]);

RouteSyncStatus _statusOf({
  RouteSyncState state = RouteSyncState.idle,
  int pending = 0,
  int blocked = 0,
}) => RouteSyncStatus(
  routeId: 'r1',
  state: state,
  pending: pending,
  blocked: blocked,
);

/// The outbox chip of a stop row — not the "Pendente" state word.
Finder _chip(String label) => find.widgetWithText(Chip, label);

void main() {
  group('the sync slot', () {
    testWidgets(
      'two pending outbox rows show the waiting count and a tap sends them',
      (tester) async {
        final worker = RecordingSyncWorker(
          statusStream: Stream<RouteSyncStatus>.value(_statusOf(pending: 2)),
        );
        await pumpHome(
          tester,
          homeWith(repositoryWith(_pendingRoute()), syncWorker: worker),
        );

        expect(find.byTooltip(AppStrings.routePendingSync(2)), findsOneWidget);
        await tester.tap(find.byTooltip(AppStrings.routePendingSync(2)));
        await tester.pumpAndSettle();
        await tester.tap(find.text(AppStrings.syncSendNow));
        await tester.pumpAndSettle();
        expect(worker.syncAllCount, 1);
      },
    );

    testWidgets('the waiting count uses the singular for a single row', (
      tester,
    ) async {
      final worker = RecordingSyncWorker(
        statusStream: Stream<RouteSyncStatus>.value(_statusOf(pending: 1)),
      );
      await pumpHome(
        tester,
        homeWith(repositoryWith(_pendingRoute()), syncWorker: worker),
      );

      expect(find.byTooltip(AppStrings.routePendingSync(1)), findsOneWidget);
    });

    testWidgets('an idle status with nothing pending reads all synced', (
      tester,
    ) async {
      final worker = RecordingSyncWorker(
        statusStream: Stream<RouteSyncStatus>.value(_statusOf()),
      );
      await pumpHome(
        tester,
        homeWith(repositoryWith(_pendingRoute()), syncWorker: worker),
      );

      expect(find.byTooltip(AppStrings.routeAllSynced), findsOneWidget);
      expect(find.byTooltip(AppStrings.routePendingSync(0)), findsNothing);
    });

    testWidgets('a tap on the indicator opens the detail sheet', (
      tester,
    ) async {
      final worker = RecordingSyncWorker(
        statusStream: Stream<RouteSyncStatus>.value(_statusOf(pending: 2)),
      );
      await pumpHome(
        tester,
        homeWith(repositoryWith(_pendingRoute()), syncWorker: worker),
      );

      await tester.tap(find.byTooltip(AppStrings.routePendingSync(2)));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.syncSendNow), findsOneWidget);
      expect(find.text(AppStrings.syncDetailPending(2)), findsOneWidget);
    });

    testWidgets('a blocked status opens BlockedSyncScreen', (tester) async {
      final store = InMemoryLocalWriteStore();
      await store.enqueue(
        id: 'op-1',
        kind: PendingOpKind.checkIn,
        routeId: 'r1',
        payload: {'route_stop_id': 's1'},
      );
      await store.markBlocked('op-1', 'HTTP 422');
      final worker = RecordingSyncWorker(
        statusStream: Stream<RouteSyncStatus>.value(
          _statusOf(state: RouteSyncState.blocked, blocked: 1),
        ),
      );
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(_pendingRoute()),
          syncWorker: worker,
          localWriteStore: store,
        ),
      );

      await tester.tap(find.byTooltip(AppStrings.routeSyncBlockedBanner));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.syncSeeBlocked));
      await tester.pumpAndSettle();
      expect(find.byType(BlockedSyncScreen), findsOneWidget);
    });
  });

  group('the per-stop outbox chip', () {
    testWidgets(
      'a stop with a pending check-in row shows "Pendente"; a stop with no '
      'rows shows none',
      (tester) async {
        final store = InMemoryLocalWriteStore();
        await store.enqueue(
          id: 'op-1',
          kind: PendingOpKind.checkIn,
          routeId: 'r1',
          payload: {'route_stop_id': 's1'},
        );
        await pumpHome(
          tester,
          homeWith(
            repositoryWith(
              routeWith(
                stops: [
                  stopIn(id: 's1'),
                  stopIn(id: 's2'),
                ],
              ),
            ),
            localWriteStore: store,
          ),
        );

        expect(_chip(AppStrings.routeChipPending), findsOneWidget);
        expect(_chip(AppStrings.routeChipBlocked), findsNothing);
      },
    );

    testWidgets(
      'a stop with a pending evidence row (matched by its StopProgress '
      'executionId) shows "Pendente"',
      (tester) async {
        final store = InMemoryLocalWriteStore();
        await store.enqueue(
          id: 'op-photo',
          kind: PendingOpKind.evidencePhoto,
          routeId: 'r1',
          payload: {'execution_id': 'exec-1'},
        );
        await pumpHome(
          tester,
          homeWith(
            repositoryWith(
              routeWith(
                stops: [stopIn(id: 's1', status: 'IN_PROGRESS')],
              ),
            ),
            stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
            localWriteStore: store,
          ),
        );

        expect(_chip(AppStrings.routeChipPending), findsOneWidget);
      },
    );

    testWidgets('a stop whose only outbox row is blocked shows "Bloqueado"', (
      tester,
    ) async {
      final store = InMemoryLocalWriteStore();
      await store.enqueue(
        id: 'op-1',
        kind: PendingOpKind.checkIn,
        routeId: 'r1',
        payload: {'route_stop_id': 's1'},
      );
      await store.markBlocked('op-1', 'HTTP 422');
      await pumpHome(
        tester,
        homeWith(repositoryWith(_pendingRoute()), localWriteStore: store),
      );

      expect(_chip(AppStrings.routeChipBlocked), findsOneWidget);
      expect(_chip(AppStrings.routeChipPending), findsNothing);
    });

    testWidgets('blocked wins pending', (tester) async {
      final store = InMemoryLocalWriteStore();
      await store.enqueue(
        id: 'op-checkin',
        kind: PendingOpKind.checkIn,
        routeId: 'r1',
        payload: {'route_stop_id': 's1'},
      );
      await store.markBlocked('op-checkin', 'HTTP 422');
      await store.enqueue(
        id: 'op-photo',
        kind: PendingOpKind.evidencePhoto,
        routeId: 'r1',
        payload: {'execution_id': 'exec-1'},
      );
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(
            routeWith(
              stops: [stopIn(id: 's1', status: 'IN_PROGRESS')],
            ),
          ),
          stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
          localWriteStore: store,
        ),
      );

      expect(_chip(AppStrings.routeChipBlocked), findsOneWidget);
      expect(_chip(AppStrings.routeChipPending), findsNothing);
    });
  });

  group('next batch', () {
    RouteSummary lastStopInProgress() => routeWith(
      stops: [
        stopWith(id: 's1', status: 'IN_PROGRESS', servicePointName: 'Sala 101'),
      ],
    );

    RouteSummary secondBatch() => routeWith(
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

    void handOutSecondBatch(FakeRouteRepository repository) {
      repository.allocate = () {
        repository.day = myDayWith(secondBatch());
        return AllocationResult(route: secondBatch(), poolEmpty: false);
      };
    }

    testWidgets(
      'checking out the last open stop delivers it and pulls the next batch',
      (tester) async {
        final store = InMemoryLocalWriteStore();
        final repository = repositoryWith(lastStopInProgress());
        handOutSecondBatch(repository);
        await pumpHome(
          tester,
          homeWith(
            repository,
            localWriteStore: store,
            stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
            syncWorker: RecordingSyncWorker(drains: store),
          ),
        );
        expect(repository.allocationCalls, isEmpty);

        await concludeWith(tester, 'v1.floor.1.sig');
        await tester.pumpAndSettle();

        expect(repository.allocationCalls, ['nextBatch:r1']);
        expect(await store.unsyncedForRoute('r1'), isEmpty);
        expect(find.text(AppStrings.dayProgress(2, 1, 2)), findsOneWidget);
        expect(find.text('Sala 202'), findsOneWidget);
      },
    );

    testWidgets(
      'offline, a finished batch shows the reconnect panel and pulls the next '
      'batch once the connection is back',
      (tester) async {
        final connectivity = FakeConnectivity();
        addTearDown(connectivity.dispose);
        final progress = FakeStopProgressStore({'s1': 'exec-1'});
        await progress.markDone('s1');
        final repository = repositoryWith(lastStopInProgress());
        handOutSecondBatch(repository);
        await pumpHome(
          tester,
          homeWith(
            repository,
            connectivity: connectivity,
            stopProgressStore: progress,
          ),
        );

        expect(nextBatchOfflinePanel(), findsOneWidget);
        expect(repository.allocationCalls, isEmpty);

        connectivity.goOnline();
        await tester.pumpAndSettle();

        expect(repository.allocationCalls, ['nextBatch:r1']);
        expect(nextBatchOfflinePanel(), findsNothing);
        expect(find.text('Sala 202'), findsOneWidget);
      },
    );

    testWidgets('offline, the finished batch also says so in a snackbar', (
      tester,
    ) async {
      final progress = FakeStopProgressStore({'s1': 'exec-1'});
      await progress.markDone('s1');
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(lastStopInProgress()),
          connectivity: FakeConnectivity(),
          stopProgressStore: progress,
        ),
      );

      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(AppStrings.routeNextBatchOffline),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      '"Tentar de novo" drains the outbox and then re-runs the pull that was '
      'waiting on it',
      (tester) async {
        final store = InMemoryLocalWriteStore();
        await store.enqueue(
          id: 'checkout-s1',
          kind: PendingOpKind.checkOut,
          payload: const {'route_stop_id': 's1'},
          routeId: 'r1',
        );
        final progress = FakeStopProgressStore({'s1': 'exec-1'});
        await progress.markDone('s1');
        final status = statusController();
        final worker = RecordingSyncWorker(statusStream: status.stream);
        final repository = repositoryWith(lastStopInProgress());
        handOutSecondBatch(repository);
        await pumpHome(
          tester,
          homeWith(
            repository,
            localWriteStore: store,
            stopProgressStore: progress,
            syncWorker: worker,
          ),
        );
        status.add(_statusOf(pending: 1));
        await tester.pumpAndSettle();
        expect(nextBatchOfflinePanel(), findsOneWidget);
        expect(repository.allocationCalls, isEmpty);

        // The server is reachable again; the worker taps "Tentar de novo".
        worker.drains = store;
        await tester.tap(
          find.descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.text(AppStrings.retryButton),
          ),
        );
        await tester.pumpAndSettle();

        expect(worker.syncAllCount, 1);
        expect(repository.allocationCalls, ['nextBatch:r1']);
        expect(find.text('Sala 202'), findsOneWidget);
      },
    );
  });
}
