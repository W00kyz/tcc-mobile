import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/monitoring/silence_watchdog.dart';
import 'package:route_monitor/routing/route_repository.dart';

import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';

// Ported from the deleted route_screen_test.dart: "Escanear QR" (check-in
// with on-device room resolution) and the silence clock, now driven from
// the map home.

RouteSummary _pendingRoute() => routeWith(stops: [stopIn(id: 's1')]);

RouteSummary _inProgressStopRoute() => routeWith(
  stops: [stopIn(id: 's1', status: 'IN_PROGRESS')],
);

// The GPS fix FakeLocationService reports; the stops below are positioned
// relative to it so the offline room resolution (spec Ruling 4) lands on a
// known branch.
RouteSummary _oneRoomInRadiusRoute() => routeWith(
  stops: [
    stopIn(
      id: 's1',
      servicePointName: 'Sala 101',
      latitude: -7.23,
      longitude: -35.88,
    ),
    // ~2.5 km away — well outside the 50 m check radius.
    stopIn(
      id: 's2',
      orderIndex: 2,
      servicePointName: 'Sala 102',
      latitude: -7.25,
      longitude: -35.90,
    ),
  ],
);

RouteSummary _twoRoomsInRadiusRoute() => routeWith(
  stops: [
    stopIn(
      id: 's1',
      servicePointName: 'Sala 101',
      latitude: -7.23,
      longitude: -35.88,
    ),
    // ~11 m from the GPS fix — inside the radius, but farther than s1.
    stopIn(
      id: 's2',
      orderIndex: 2,
      servicePointName: 'Sala 102',
      latitude: -7.2301,
      longitude: -35.88,
    ),
  ],
);

void main() {
  group('the scan button', () {
    testWidgets('shows on an in-progress route with a pending stop', (
      tester,
    ) async {
      await pumpHome(tester, homeWith(repositoryWith(_pendingRoute())));

      expect(scanQrButton(), findsOneWidget);
    });

    testWidgets('hides when every stop is already done', (tester) async {
      await pumpHome(
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
      'hides when the only remaining stop is already IN_PROGRESS (checked '
      'in, awaiting checkout — Task 18), not PENDING',
      (tester) async {
        // Regression: _canCheckIn used to accept any stop.status != 'DONE',
        // so it stayed visible here — the backend has no PENDING candidate
        // to resolve on that floor any more, so scanning again would only
        // get a confusing 422 FLOOR_NOT_ON_ROUTE dead end (task-17 review).
        await pumpHome(
          tester,
          homeWith(repositoryWith(_inProgressStopRoute())),
        );

        expect(scanQrButton(), findsNothing);
      },
    );
  });

  testWidgets(
    'runs the check-in flow end-to-end: scans, checks in and shows success',
    (tester) async {
      final store = InMemoryLocalWriteStore();
      await pumpHome(
        tester,
        homeWith(repositoryWith(_pendingRoute()), localWriteStore: store),
      );

      await scanWith(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.kind, PendingOpKind.checkIn);
      expect(rows.single.payload['qr_payload'], 'v1.floor.1.sig');
      expect(rows.single.payload['latitude'], -7.23);
      expect(rows.single.payload['longitude'], -35.88);
      expect(find.text(AppStrings.routeCheckInDone), findsOneWidget);
    },
  );

  testWidgets('does nothing when the scan screen is popped without a value', (
    tester,
  ) async {
    final store = InMemoryLocalWriteStore();
    await pumpHome(
      tester,
      homeWith(repositoryWith(_pendingRoute()), localWriteStore: store),
    );

    await scanWith(tester, null);
    await tester.pumpAndSettle();

    expect(await store.unsyncedForRoute('r1'), isEmpty);
    expect(scanQrButton(), findsOneWidget);
  });

  testWidgets(
    'tolerates a GPS failure during check-in and still checks in with null '
    'coordinates',
    (tester) async {
      final store = InMemoryLocalWriteStore();
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(_pendingRoute()),
          locationService: FailingLocationService(),
          localWriteStore: store,
        ),
      );

      await scanWith(tester, 'v1.floor.1.sig');
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
      expect(rows.single.payload['qr_payload'], 'v1.floor.1.sig');
      expect(rows.single.payload['latitude'], isNull);
      expect(rows.single.payload['longitude'], isNull);
    },
  );

  testWidgets(
    'check-in with GPS placing one pending stop in radius resolves to it and '
    'enqueues that routeStopId',
    (tester) async {
      final store = InMemoryLocalWriteStore();
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(_oneRoomInRadiusRoute()),
          localWriteStore: store,
        ),
      );

      await scanWith(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.roomPickerPrompt), findsNothing);
      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.kind, PendingOpKind.checkIn);
      expect(rows.single.payload['route_stop_id'], 's1');
      expect(find.text(AppStrings.routeCheckInDone), findsOneWidget);
    },
  );

  testWidgets(
    'check-in with two pending stops in radius shows the picker sheet '
    '(nearest pre-selected); choosing the second enqueues its routeStopId',
    (tester) async {
      final store = InMemoryLocalWriteStore();
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(_twoRoomsInRadiusRoute()),
          localWriteStore: store,
        ),
      );

      await scanWith(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.roomPickerPrompt), findsOneWidget);
      // Scope to the sheet — the stop list behind it also renders a
      // "Sala 102" row.
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Sala 102'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();

      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.payload['route_stop_id'], 's2');
      expect(find.text(AppStrings.routeCheckInDone), findsOneWidget);
    },
  );

  testWidgets('dismissing the room picker enqueues nothing and shows no '
      'snackbar', (tester) async {
    final store = InMemoryLocalWriteStore();
    await pumpHome(
      tester,
      homeWith(
        repositoryWith(_twoRoomsInRadiusRoute()),
        localWriteStore: store,
      ),
    );

    await scanWith(tester, 'v1.floor.1.sig');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();

    expect(await store.unsyncedForRoute('r1'), isEmpty);
    expect(find.text(AppStrings.routeCheckInDone), findsNothing);
  });

  testWidgets(
    'no GPS with a single pending stop resolves to it and enqueues the '
    'check-in with a null distance',
    (tester) async {
      final store = InMemoryLocalWriteStore();
      // A single PENDING stop — with no GPS the resolution falls to the
      // "lone pending stop resolves anyway" path (Ruling 4 /
      // validation.py:117).
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(_pendingRoute()),
          locationService: FailingLocationService(),
          localWriteStore: store,
        ),
      );

      await scanWith(tester, 'v1.floor.1.sig');
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.roomPickerPrompt), findsNothing);
      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.payload['route_stop_id'], 's1');
      expect(rows.single.payload['latitude'], isNull);
    },
  );

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
      await pumpHome(
        tester,
        homeWith(repositoryWith(_pendingRoute()), silenceWatchdog: watchdog),
      );
      now = t0.add(const Duration(minutes: 29));

      await scanWith(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      now = t0.add(const Duration(minutes: 31));
      expect(watchdog.currentWarning(), isNotNull);
    });

    testWidgets('a check-out written locally does not reset the clock', (
      tester,
    ) async {
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(_inProgressStopRoute()),
          silenceWatchdog: watchdog,
        ),
      );
      now = t0.add(const Duration(minutes: 29));

      await concludeWith(tester, 'v1.floor.1.sig');
      await tester.pumpAndSettle();

      now = t0.add(const Duration(minutes: 31));
      expect(watchdog.currentWarning(), isNotNull);
    });

    testWidgets('a silent worker sees the warning chip', (tester) async {
      now = t0.add(const Duration(minutes: 32));
      await pumpHome(
        tester,
        homeWith(repositoryWith(_pendingRoute()), silenceWatchdog: watchdog),
      );

      expect(find.text(AppStrings.silenceChip(32)), findsOneWidget);
    });
  });
}
