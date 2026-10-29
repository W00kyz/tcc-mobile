import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/monitoring/silence_watchdog.dart';
import 'package:route_monitor/routing/batch_card_model.dart' show SlotState;
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/ui/stamp_slot.dart';

import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';

// Ported from the deleted route_screen_test.dart: "Escanear QR" (one floor
// scan checks in every open task of that floor) and the silence clock, now
// driven from the map home.

RouteSummary _pendingRoute() => routeWith(stops: [stopIn(id: 's1')]);

RouteSummary _inProgressStopRoute() => routeWith(
  stops: [stopIn(id: 's1', status: 'IN_PROGRESS')],
);

/// Two tasks on the Térreo and one on the 1º andar of the same building.
RouteSummary _twoFloorsRoute() => routeWith(
  stops: [
    stopIn(id: 's1'),
    stopIn(id: 's2', orderIndex: 2),
    stopIn(id: 's3', orderIndex: 3, floorLabel: '1º andar'),
  ],
);

final String _terreoQr = qrOf('Térreo');

void main() {
  group('the scan button', () {
    testWidgets('shows on an in-progress route with a pending stop', (
      tester,
    ) async {
      await pumpHomeWithSheet(
        tester,
        homeWith(repositoryWith(_pendingRoute())),
      );

      expect(scanQrButton(), findsOneWidget);
    });

    testWidgets('hides when every stop is already done', (tester) async {
      await pumpHomeWithSheet(
        tester,
        homeWith(
          repositoryWith(
            routeWith(
              stops: [stopIn(id: 's1', status: 'DONE')],
            ),
          ),
        ),
      );

      expect(scanQrButton(), findsNothing);
    });

    testWidgets(
      'turns into the exit scan when the only remaining stop is already '
      'IN_PROGRESS (checked in, awaiting checkout — Task 18)',
      (tester) async {
        // Regression: _canCheckIn used to accept any stop.status != 'DONE',
        // so it stayed visible here — the backend has no PENDING candidate
        // to resolve on that floor any more, so scanning again would only
        // get a confusing 422 FLOOR_NOT_ON_ROUTE dead end (task-17 review).
        await pumpHomeWithSheet(
          tester,
          homeWith(repositoryWith(_inProgressStopRoute())),
        );

        expect(scanQrButton(), findsNothing);
        expect(find.text(AppStrings.scanExitQrButton), findsOneWidget);
      },
    );
  });

  testWidgets(
    'runs the check-in flow end-to-end: scans, checks in and shows success',
    (tester) async {
      final store = InMemoryLocalWriteStore();
      await pumpHomeWithSheet(
        tester,
        homeWith(repositoryWith(_pendingRoute()), localWriteStore: store),
      );

      await scanWith(tester, _terreoQr);

      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.kind, PendingOpKind.checkIn);
      expect(rows.single.payload['qr_payload'], _terreoQr);
      expect(rows.single.payload['latitude'], -7.21);
      expect(rows.single.payload['longitude'], -35.91);
      expect(find.text(AppStrings.floorCheckInDone(1)), findsOneWidget);
    },
  );

  testWidgets('does nothing when the scan screen is popped without a value', (
    tester,
  ) async {
    final store = InMemoryLocalWriteStore();
    await pumpHomeWithSheet(
      tester,
      homeWith(repositoryWith(_pendingRoute()), localWriteStore: store),
    );

    await scanWith(tester, null);

    expect(await store.unsyncedForRoute('r1'), isEmpty);
    expect(scanQrButton(), findsOneWidget);
  });

  testWidgets(
    'tolerates a GPS failure during check-in and still checks in with null '
    'coordinates',
    (tester) async {
      final store = InMemoryLocalWriteStore();
      await pumpHomeWithSheet(
        tester,
        homeWith(
          repositoryWith(_pendingRoute()),
          locationService: FailingLocationService(),
          localWriteStore: store,
        ),
      );

      await tester.tap(scanFooterButton());
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(ScanScreen))).pop(_terreoQr);
      // A single pump catches the GPS-failure snackbar before the queued
      // success snackbar replaces it — asserting the final state here would
      // race the ScaffoldMessenger's own dismiss timer.
      await tester.pump();

      expect(
        find.text('Sem localização agora. O registro foi feito mesmo assim.'),
        findsWidgets,
      );

      await tester.pumpAndSettle();
      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.payload['qr_payload'], _terreoQr);
      expect(rows.single.payload['latitude'], isNull);
      expect(rows.single.payload['longitude'], isNull);
    },
  );

  testWidgets('one floor scan checks in every open task of that floor and '
      'none of another', (tester) async {
    final store = InMemoryLocalWriteStore();
    await pumpHomeWithSheet(
      tester,
      homeWith(repositoryWith(_twoFloorsRoute()), localWriteStore: store),
    );

    await scanWith(tester, _terreoQr);

    final rows = await store.unsyncedForRoute('r1');
    expect(rows.map((row) => row.kind).toSet(), {PendingOpKind.checkIn});
    expect(rows.map((row) => row.payload['route_stop_id']), ['s1', 's2']);
    expect(find.text(AppStrings.floorCheckInDone(2)), findsOneWidget);
  });

  testWidgets('a QR of a floor with no open task enqueues nothing', (
    tester,
  ) async {
    final store = InMemoryLocalWriteStore();
    await pumpHomeWithSheet(
      tester,
      homeWith(repositoryWith(_pendingRoute()), localWriteStore: store),
    );

    await scanWith(tester, qrOf('elsewhere'));

    expect(await store.unsyncedForRoute('r1'), isEmpty);
    expect(find.text(AppStrings.floorHasNoOpenTasks), findsOneWidget);
  });

  group('the silence clock (spec §7.3)', () {
    final t0 = DateTime.utc(2026, 10, 20, 8);
    late DateTime now;
    late SilenceWatchdog watchdog;

    setUp(() {
      now = t0;
      watchdog = SilenceWatchdog(
        clock: () => now,
        scheduler: NoopScheduler(),
        warningMinutes: 30,
        releaseMinutes: 45,
      )..startWatching();
    });

    // The server counts a scan only once it arrives (by its `scanned_at`):
    // a check-in written offline, e.g. underground, must not quiet the
    // app's warning. The sync delivery reports it (sync_worker_test.dart).
    testWidgets('a check-in written locally does not reset the clock', (
      tester,
    ) async {
      await pumpHomeWithSheet(
        tester,
        homeWith(repositoryWith(_pendingRoute()), silenceWatchdog: watchdog),
      );
      now = t0.add(const Duration(minutes: 29));

      await scanWith(tester, _terreoQr);

      now = t0.add(const Duration(minutes: 31));
      expect(watchdog.currentWarning(), isNotNull);
    });

    testWidgets('a check-out written locally does not reset the clock', (
      tester,
    ) async {
      // s1 checked in and stamped: the floor's exit scan is open.
      final progress = FakeStopProgressStore({'s1': 'exec-1'});
      await progress.markStamped('s1');
      final store = InMemoryLocalWriteStore();
      await pumpHomeWithSheet(
        tester,
        homeWith(
          repositoryWith(_inProgressStopRoute()),
          silenceWatchdog: watchdog,
          stopProgressStore: progress,
          localWriteStore: store,
        ),
      );
      now = t0.add(const Duration(minutes: 29));

      await scanWith(tester, _terreoQr);
      final kinds = (await store.unsyncedForRoute('r1')).map((r) => r.kind);
      expect(kinds, [PendingOpKind.checkOut]);

      now = t0.add(const Duration(minutes: 31));
      expect(watchdog.currentWarning(), isNotNull);
    });

    testWidgets('a silent worker sees the warning chip', (tester) async {
      now = t0.add(const Duration(minutes: 32));
      await pumpHomeWithSheet(
        tester,
        homeWith(repositoryWith(_pendingRoute()), silenceWatchdog: watchdog),
      );

      expect(find.text(AppStrings.silenceChip(32)), findsOneWidget);
    });
  });

  testWidgets('the floor reads checked in after an offline check-in', (
    tester,
  ) async {
    // RecordingSyncWorker never delivers: the server still says PENDING,
    // only the device's own progress row says the stop is open.
    await pumpHomeWithSheet(tester, homeWith(repositoryWith(_pendingRoute())));
    expect(find.text(AppStrings.scanExitQrButton), findsNothing);

    await scanWith(tester, _terreoQr);

    expect(find.text(AppStrings.scanExitQrButton), findsOneWidget);
    expect(
      tester.widget<StampSlot>(slotOf('s1')).slot.state,
      SlotState.inProgress,
    );
  });

  testWidgets('runs the exit scan end-to-end: checks out the stamped task, '
      'reloads the day and shows success', (tester) async {
    final progress = FakeStopProgressStore({'s1': 'exec-1'});
    await progress.markStamped('s1', observation: 'pia entupida');
    final store = InMemoryLocalWriteStore();
    final repository = repositoryWith(_inProgressStopRoute());
    await pumpHomeWithSheet(
      tester,
      homeWith(repository, localWriteStore: store, stopProgressStore: progress),
    );
    expect(repository.fetchCount, 1);

    await scanWith(tester, _terreoQr);

    final rows = await store.unsyncedForRoute('r1');
    expect(rows, hasLength(1));
    expect(rows.single.kind, PendingOpKind.checkOut);
    expect(rows.single.payload['qr_payload'], _terreoQr);
    expect(rows.single.payload['route_stop_id'], 's1');
    expect(rows.single.payload['complaints_suggestions'], 'pia entupida');
    expect(find.text(AppStrings.floorCheckOutDone), findsOneWidget);
    expect(repository.fetchCount, 2);
  });

  testWidgets('a local IN_PROGRESS row overrides a server PENDING stop', (
    tester,
  ) async {
    await pumpHomeWithSheet(
      tester,
      homeWith(
        repositoryWith(_pendingRoute()),
        stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
      ),
    );

    expect(
      tester.widget<StampSlot>(slotOf('s1')).slot.state,
      SlotState.inProgress,
    );
    expect(find.text(AppStrings.scanExitQrButton), findsOneWidget);
  });
}
