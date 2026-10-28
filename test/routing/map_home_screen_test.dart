import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/monitoring/silence_watchdog.dart';
import 'package:route_monitor/routing/campus_map.dart';
import 'package:route_monitor/routing/floor_actions.dart';
import 'package:route_monitor/routing/map_home_screen.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/ui/building_pin.dart';
import 'package:route_monitor/ui/floor_card.dart';
import 'package:route_monitor/ui/stamp_slot.dart';

import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';

/// Two buildings: "Central de Aulas" (Térreo, 1º andar) and "Bloco B"
/// (2º andar), far enough apart to draw two pins.
RouteSummary _twoBuildings() => routeWith(
  stops: [
    stopIn(id: 's1', buildingName: 'Central de Aulas'),
    stopIn(
      id: 's2',
      orderIndex: 2,
      buildingName: 'Central de Aulas',
      floorLabel: '1º andar',
    ),
    stopIn(
      id: 's3',
      orderIndex: 3,
      buildingId: 'b2',
      buildingName: 'Bloco B',
      floorLabel: '2º andar',
      latitude: -7.214,
      longitude: -35.906,
    ),
  ],
);

BuildingPin _pinOf(WidgetTester tester, String buildingId) =>
    tester.widget<BuildingPin>(
      find.descendant(
        of: find.byKey(ValueKey('pin-$buildingId')),
        matching: find.byType(BuildingPin),
      ),
    );

CampusMap _map(WidgetTester tester) =>
    tester.widget<CampusMap>(find.byType(CampusMap));

/// The top bar's progress dots, filled (`on`) or empty (`off`).
Finder _dots(String state) => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('progress-dot-$state'),
);

void main() {
  group('day states (spec §6.10)', () {
    testWidgets('no service says so, with no card and no start', (
      tester,
    ) async {
      await pumpHome(
        tester,
        homeWith(FakeRouteRepository(myDayWith(null, serviceDay: false))),
      );

      expect(find.text(AppStrings.dayNoService), findsOneWidget);
      expect(find.byType(FloorCard), findsNothing);
      expect(find.text(AppStrings.routeStartButton), findsNothing);
      expect(find.byType(CampusMap), findsOneWidget);
    });

    testWidgets('no route yet shows the start bar', (tester) async {
      await pumpHome(tester, homeWith(repositoryWith(null)));

      expect(
        find.widgetWithText(FilledButton, AppStrings.routeStartButton),
        findsOneWidget,
      );
    });

    testWidgets('a paused route shows only "Retomar", with no sheet', (
      tester,
    ) async {
      final paused = routeWith(
        status: 'PAUSED',
        stops: [
          stopIn(id: 's1', status: 'RELEASED', releaseReason: 'LEFT_CAMPUS'),
        ],
      );
      await pumpHome(tester, homeWith(repositoryWith(paused)));

      expect(
        find.widgetWithText(FilledButton, AppStrings.dayResumeButton),
        findsOneWidget,
      );
      expect(find.byType(DraggableScrollableSheet), findsNothing);
    });

    testWidgets('a done route shows "Dia concluído" and "Verificar de novo"', (
      tester,
    ) async {
      final done = routeWith(
        status: 'DONE',
        stops: [stopIn(id: 's1', status: 'DONE')],
      );
      await pumpHome(tester, homeWith(repositoryWith(done)));

      expect(find.text(AppStrings.dayDoneTitle), findsOneWidget);
      expect(find.text(AppStrings.dayDoneSummary(1)), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, AppStrings.routeCheckAgainButton),
        findsOneWidget,
      );
    });

    testWidgets('a load error offers "Tentar de novo" over the map', (
      tester,
    ) async {
      final repository = FakeRouteRepository()
        ..fetchError = DioException(
          requestOptions: RequestOptions(path: '/routes/me'),
        );
      await pumpHome(tester, homeWith(repository));

      expect(find.text(AppStrings.routeLoadError), findsOneWidget);
      expect(find.byType(CampusMap), findsOneWidget);

      repository.fetchError = null;
      await tester.tap(find.text(AppStrings.retryButton));
      await tester.pumpAndSettle();

      expect(repository.fetchCount, greaterThan(1));
      expect(find.text(AppStrings.routeLoadError), findsNothing);
      expect(find.text(AppStrings.routeStartButton), findsOneWidget);
    });
  });

  testWidgets('in-progress route shows the floor card and Escanear QR', (
    tester,
  ) async {
    await pumpHome(tester, homeWith(repositoryWith(_twoBuildings())));

    expect(find.byType(FloorCard), findsOneWidget);
    expect(scanQrButton(), findsOneWidget);
    expect(find.text(AppStrings.buildingSheetNext), findsOneWidget);
  });

  testWidgets('Escanear QR visible at all three snaps', (tester) async {
    await pumpHome(tester, homeWith(repositoryWith(_twoBuildings())));

    for (final size in [0.22, 0.5, 0.9]) {
      await snapSheetTo(tester, size);
      expect(scanQrButton().hitTestable(), findsOneWidget, reason: '$size');
    }
  });

  testWidgets('a checked-in floor offers the exit scan, not "Escanear QR"', (
    tester,
  ) async {
    final route = routeWith(
      stops: [
        stopIn(id: 's1', status: 'IN_PROGRESS'),
        stopIn(id: 's2', orderIndex: 2, status: 'DONE'),
      ],
    );
    await pumpHome(tester, homeWith(repositoryWith(route)));

    expect(scanQrButton(), findsNothing);
    expect(find.text(AppStrings.scanExitQrButton), findsOneWidget);
  });

  testWidgets('tapping a pin selects the building', (tester) async {
    await pumpHome(tester, homeWith(repositoryWith(_twoBuildings())));

    await tester.tap(pinCircle('b2'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MapHomeScreen)),
    );
    expect(container.read(selectedBuildingProvider), 'b2');
    // The sheet swaps to the tapped building's floor card.
    expect(shownFloorCard(tester).building.buildingId, 'b2');
    // The map centres on b2, which can push b1 out of view: read the
    // selection the map dims the other pins by (campus_map_test covers the
    // dimming itself).
    expect(_map(tester).selectedBuildingId, 'b2');
    expect(_pinOf(tester, 'b2').selected, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(container.read(selectedBuildingProvider), isNull);
    expect(_map(tester).selectedBuildingId, isNull);
    expect(shownFloorCard(tester).building.buildingId, 'b1');
  });

  testWidgets(
    'top bar shows "Lote 2 · 3 de 8 pontos hoje" with 8 progress dots, '
    '3 filled',
    (tester) async {
      final route = routeWith(
        currentBatch: 2,
        stops: [
          for (var i = 1; i <= 3; i++)
            stopIn(id: 'd$i', orderIndex: i, status: 'DONE'),
          for (var i = 4; i <= 8; i++)
            stopIn(id: 'p$i', orderIndex: i, batchNumber: 2),
          stopIn(
            id: 'r9',
            orderIndex: 9,
            batchNumber: 2,
            status: 'RELEASED',
          ),
        ],
      );
      await pumpHome(tester, homeWith(repositoryWith(route)));

      expect(find.text('Lote 2 · 3 de 8 pontos hoje'), findsOneWidget);
      expect(_dots('on'), findsNWidgets(3));
      expect(_dots('off'), findsNWidgets(5));
    },
  );

  testWidgets('collection chip shows while the route is IN_PROGRESS', (
    tester,
  ) async {
    await pumpHome(tester, homeWith(repositoryWith(_twoBuildings())));

    expect(find.text(AppStrings.collectionChip), findsOneWidget);
  });

  testWidgets('the silence chip shows "Sem localização há 12 min"', (
    tester,
  ) async {
    // Started at t0, read at t0 + 12 min.
    final t0 = DateTime.utc(2026, 10, 20, 8);
    var now = t0;
    final started = SilenceWatchdog(
      clock: () => now,
      scheduler: NoopScheduler(),
      warningMinutes: 10,
      releaseMinutes: 45,
    )..startWatching();
    now = t0.add(const Duration(minutes: 12));

    await pumpHome(
      tester,
      homeWith(repositoryWith(_twoBuildings()), silenceWatchdog: started),
    );

    expect(find.text('Sem localização há 12 min'), findsOneWidget);
    await tester.tap(find.text('Sem localização há 12 min'));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.silenceWarning(12, 33)), findsOneWidget);
  });

  testWidgets('"Minha posição" draws the worker on the map', (tester) async {
    await pumpHome(tester, homeWith(repositoryWith(_twoBuildings())));
    expect(find.byKey(const ValueKey('worker-position')), findsNothing);

    await tester.tap(find.byTooltip(AppStrings.myPositionTooltip));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('worker-position')), findsOneWidget);
  });

  testWidgets('"Minha posição" without GPS says so', (tester) async {
    await pumpHome(
      tester,
      homeWith(
        repositoryWith(_twoBuildings()),
        locationService: FailingLocationService(),
      ),
    );

    await tester.tap(find.byTooltip(AppStrings.myPositionTooltip));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.routeLocationUnavailable), findsOneWidget);
    expect(find.byKey(const ValueKey('worker-position')), findsNothing);
  });

  testWidgets('a selected building still offers Escanear QR', (tester) async {
    await pumpHome(tester, homeWith(repositoryWith(_twoBuildings())));

    await tester.tap(pinCircle('b2'));
    await tester.pumpAndSettle();

    expect(scanQrButton().hitTestable(), findsOneWidget);
  });

  group('fix round 1', () {
    testWidgets('the account avatar is a 48dp touch target', (tester) async {
      await pumpHome(tester, homeWith(repositoryWith(_twoBuildings())));

      final size = tester.getSize(find.byTooltip(AppStrings.profileTooltip));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('the stamp and its label read the same hour for a server-done '
        'stop (wall-clock-tagged UTC, no toLocal)', (tester) async {
      final route = routeWith(
        stops: [
          stopIn(
            id: 's1',
            status: 'DONE',
            doneAt: DateTime.utc(2026, 10, 20, 10, 5),
          ),
          stopIn(id: 's2', orderIndex: 2),
        ],
      );
      await pumpHome(tester, homeWith(repositoryWith(route)));

      // The stamp's hour, on the card, and the slot's spoken label.
      expect(find.text('10:05'), findsOneWidget);
      expect(
        find.bySemanticsLabel(AppStrings.slotDone('10:05')),
        findsOneWidget,
      );
    });

    testWidgets('a new batch clears the building selection, even in the '
        'same building', (tester) async {
      final repository = repositoryWith(
        routeWith(
          stops: [stopIn(id: 's1', servicePointName: 'Sala 1')],
        ),
      );
      await pumpHome(tester, homeWith(repository));
      await tester.tap(pinCircle('b1'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MapHomeScreen)),
      );
      expect(container.read(selectedBuildingProvider), 'b1');

      repository.day = myDayWith(
        routeWith(
          currentBatch: 2,
          stops: [
            stopIn(id: 's1', status: 'DONE'),
            stopIn(id: 's2', orderIndex: 2, batchNumber: 2),
          ],
        ),
      );
      container.invalidate(myDayProvider);
      await tester.pumpAndSettle();

      expect(container.read(selectedBuildingProvider), isNull);
      expect(find.text(AppStrings.buildingSheetNext), findsOneWidget);
      expect(find.text(AppStrings.buildingSheetSelected), findsNothing);
    });

    testWidgets('on a small phone the closed sheet still shows the next '
        'building and Escanear QR', (tester) async {
      tester.view
        ..physicalSize = const Size(360, 640)
        ..devicePixelRatio = 1
        ..padding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(homeWith(repositoryWith(_twoBuildings())));
      await tester.pumpAndSettle();

      await snapSheetTo(tester, 0.22);

      expect(
        find.text(AppStrings.buildingSheetNext).hitTestable(),
        findsOneWidget,
      );
      expect(scanQrButton().hitTestable(), findsOneWidget);
    });
  });

  testWidgets('a stamp animates only its own slot on the floor card', (
    tester,
  ) async {
    final route = routeWith(
      stops: [
        stopIn(id: 's1', status: 'IN_PROGRESS'),
        stopIn(id: 's2', orderIndex: 2, status: 'IN_PROGRESS'),
      ],
    );
    await pumpHome(
      tester,
      homeWith(
        repositoryWith(route),
        stopProgressStore: FakeStopProgressStore({
          's1': 'exec-1',
          's2': 'exec-2',
        }),
      ),
    );
    final ref = tester.element(find.byType(MapHomeScreen)) as WidgetRef;

    await concludeTask(ref, route, route.stops.first);
    await tester.pumpAndSettle();

    expect(shownFloorCard(tester).animateStopId, 's1');
    final animating = tester
        .widgetList<StampSlot>(find.byType(StampSlot))
        .where((slot) => slot.animateStamp);
    expect(animating.map((slot) => slot.slot.stopId), ['s1']);
  });
}
