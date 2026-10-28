import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/batch_card_model.dart' show SlotState;
import 'package:route_monitor/routing/live_approach.dart';
import 'package:route_monitor/routing/map_home_screen.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/ui/stamp_slot.dart';

import '../support/fake_connectivity.dart';
import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';

// Ported from the deleted route_screen_test.dart: the start of the day and
// the route states, now in the home's sheet (redesign §6.10).

SlotState _slotState(WidgetTester tester, String stopId) =>
    tester.widget<StampSlot>(slotOf(stopId)).slot.state;

void main() {
  group('before the first batch', () {
    Finder startButton() =>
        find.widgetWithText(FilledButton, AppStrings.routeStartButton);

    /// No route yet; "Iniciar rota" hands out a one-stop batch.
    FakeRouteRepository startableRepository() {
      final repository = repositoryWith(null);
      final firstBatch = routeWith(stops: [stopWith(id: 's1')]);
      repository.allocate = () {
        repository.day = myDayWith(firstBatch);
        return AllocationResult(route: firstBatch, poolEmpty: false);
      };
      return repository;
    }

    testWidgets('a non-service day says so and offers no start', (
      tester,
    ) async {
      await pumpHome(
        tester,
        homeWith(FakeRouteRepository(myDayWith(null, serviceDay: false))),
      );

      expect(find.text(AppStrings.dayNoService), findsOneWidget);
      expect(startButton(), findsNothing);
    });

    testWidgets(
      '"Iniciar rota" allocates from the current position and shows the '
      'batch with the day progress',
      (tester) async {
        final repository = repositoryWith(null);
        final firstBatch = routeWith(
          stops: [
            stopWith(id: 's1', servicePointName: 'Sala 101'),
            stopWith(id: 's2', orderIndex: 2, servicePointName: 'Sala 102'),
          ],
        );
        repository.allocate = () {
          repository.day = myDayWith(firstBatch);
          return AllocationResult(route: firstBatch, poolEmpty: false);
        };
        await pumpHome(tester, homeWith(repository));

        await tester.tap(startButton());
        await tester.pumpAndSettle();

        expect(repository.allocationCalls, ['start']);
        expect(repository.lastPosition, (lat: -7.23, lng: -35.88));
        expect(find.text(AppStrings.dayProgress(1, 0, 2)), findsOneWidget);
        expect(startButton(), findsNothing);
        // The batch's building, its two tasks on the floor card.
        expect(slotOf('s1'), findsOneWidget);
        expect(slotOf('s2'), findsOneWidget);
      },
    );

    testWidgets(
      'the first "Iniciar rota" explains and asks for "always" location',
      (tester) async {
        final permissions = FakePermissions(grantsAlways: true);
        final asked = InMemoryAskStore();
        final repository = startableRepository();
        await pumpHome(
          tester,
          homeWith(
            repository,
            permissions: permissions,
            backgroundAsked: asked,
          ),
        );

        await tester.tap(startButton());
        await tester.pumpAndSettle();
        expect(find.text(AppStrings.locationAlwaysRationale), findsOneWidget);
        expect(repository.allocationCalls, isEmpty);

        await tester.tap(find.text(AppStrings.locationPromptContinue));
        await tester.pumpAndSettle();

        expect(permissions.alwaysRequests, 1);
        expect(asked.asked, isTrue);
        expect(repository.allocationCalls, ['start']);
      },
    );

    testWidgets('a refused "always" leaves a one-time note, then starts', (
      tester,
    ) async {
      final repository = startableRepository();
      await pumpHome(
        tester,
        homeWith(repository, backgroundAsked: InMemoryAskStore()),
      );

      await tester.tap(startButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.locationPromptContinue));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.locationForegroundOnlyNote), findsOneWidget);
      await tester.tap(find.text(AppStrings.locationPromptUnderstood));
      await tester.pumpAndSettle();

      expect(repository.allocationCalls, ['start']);
    });

    testWidgets('a permission plugin failure never swallows the start', (
      tester,
    ) async {
      final repository = startableRepository();
      await pumpHome(
        tester,
        homeWith(repository, permissions: ThrowingPermissions()),
      );

      await tester.tap(startButton());
      await tester.pumpAndSettle();

      expect(repository.allocationCalls, ['start']);
    });

    testWidgets('offline, "Iniciar rota" asks for a connection', (
      tester,
    ) async {
      final repository = repositoryWith(null);
      await pumpHome(
        tester,
        homeWith(repository, connectivity: FakeConnectivity()),
      );

      await tester.tap(startButton());
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.routeStartOffline), findsOneWidget);
      expect(repository.allocationCalls, isEmpty);
    });

    final refusals = <String, (Exception, String)>{
      'outside the campus': (
        const OutsideCampusException(),
        AppStrings.routeOutsideCampus,
      ),
      'after the workday': (
        const WorkdayOverException(),
        AppStrings.routeWorkdayOver,
      ),
      'on a non-service day': (
        const NotAServiceDayException(),
        AppStrings.routeNotServiceDay,
      ),
      'with the route already done': (
        const RouteDoneException(),
        AppStrings.routeNoMorePoints,
      ),
      'with the privacy notice still owed (plain 403)': (
        DioException(
          requestOptions: RequestOptions(path: '/routes/start'),
          response: Response<Object>(
            requestOptions: RequestOptions(path: '/routes/start'),
            statusCode: 403,
          ),
        ),
        AppStrings.routeStartFailed,
      ),
    };
    for (final MapEntry(key: situation, value: (error, message))
        in refusals.entries) {
      testWidgets('"Iniciar rota" $situation shows "$message"', (tester) async {
        final repository = repositoryWith(null)..allocate = () => throw error;
        await pumpHome(tester, homeWith(repository));

        await tester.tap(startButton());
        await tester.pumpAndSettle();

        expect(find.text(message), findsOneWidget);
        expect(startButton(), findsOneWidget);
      });
    }

    testWidgets('an empty pool on "Iniciar rota" says there is nothing left', (
      tester,
    ) async {
      final done = routeWith(status: 'DONE', stops: const []);
      final repository = repositoryWith(null);
      repository.allocate = () {
        repository.day = myDayWith(done);
        return AllocationResult(route: done, poolEmpty: true);
      };
      await pumpHome(tester, homeWith(repository));

      await tester.tap(startButton());
      await tester.pumpAndSettle();

      // The snackbar says it, and the sheet shows the finished day.
      expect(find.text(AppStrings.routeNoMorePoints), findsOneWidget);
      expect(find.text(AppStrings.dayDoneTitle), findsOneWidget);
    });

    testWidgets(
      'a GPS failure on "Iniciar rota" shows the location snackbar and asks '
      'the server for nothing',
      (tester) async {
        final repository = repositoryWith(null);
        await pumpHome(
          tester,
          homeWith(repository, locationService: FailingLocationService()),
        );

        await tester.tap(startButton());
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.routeLocationUnavailable), findsOneWidget);
        expect(repository.allocationCalls, isEmpty);
      },
    );
  });

  group('route states', () {
    testWidgets(
      'opens on the current batch under the done count of the whole day, a '
      'released stop as released and with no action',
      (tester) async {
        final route = routeWith(
          currentBatch: 2,
          stops: [
            stopWith(id: 'a', status: 'DONE', servicePointName: 'Sala Velha'),
            stopWith(
              id: 'b',
              orderIndex: 2,
              batchNumber: 2,
              status: 'RELEASED',
              releaseReason: 'IMPEDIMENT',
              servicePointName: 'Sala Impedida',
            ),
            stopWith(
              id: 'c',
              orderIndex: 3,
              batchNumber: 2,
              servicePointName: 'Sala Nova',
            ),
          ],
        );
        await pumpHome(tester, homeWith(repositoryWith(route)));

        expect(find.text('Lote 2 · 1 de 2 pontos hoje'), findsOneWidget);
        // The stops are read from the floor card, not a list on the home.
        expect(find.text('Sala Velha'), findsNothing);
        expect(_slotState(tester, 'a'), SlotState.done);
        expect(
          find.bySemanticsLabel(
            AppStrings.slotReleased(
              AppStrings.releaseReasonLabel('IMPEDIMENT'),
            ),
          ),
          findsOneWidget,
        );
        expect(_slotState(tester, 'c'), SlotState.next);
      },
    );

    testWidgets('a paused route explains why and "Retomar" resumes it', (
      tester,
    ) async {
      final paused = routeWith(
        status: 'PAUSED',
        stops: [
          stopWith(
            id: 's1',
            status: 'RELEASED',
            releaseReason: 'LEFT_CAMPUS',
            servicePointName: 'Sala 101',
          ),
        ],
      );
      final repository = repositoryWith(paused);
      await pumpHome(tester, homeWith(repository));

      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(
        find.text(
          AppStrings.routePausedReason(
            AppStrings.releaseReasonLabel('LEFT_CAMPUS'),
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Sala 101'), findsNothing);

      await tester.tap(
        find.widgetWithText(FilledButton, AppStrings.dayResumeButton),
      );
      await tester.pumpAndSettle();

      expect(repository.allocationCalls, ['start']);
    });

    Finder checkAgainButton() =>
        find.widgetWithText(FilledButton, AppStrings.routeCheckAgainButton);

    testWidgets('a finished route says the day is done and offers to check '
        'again', (tester) async {
      final done = routeWith(
        status: 'DONE',
        stops: [stopWith(id: 's1', status: 'DONE')],
      );
      await pumpHome(tester, homeWith(repositoryWith(done)));

      expect(find.text(AppStrings.dayDoneTitle), findsOneWidget);
      expect(checkAgainButton(), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, AppStrings.routeStartButton),
        findsNothing,
      );
    });

    testWidgets('"Verificar de novo" takes the points released since', (
      tester,
    ) async {
      // Spec §1: a colleague's point went back to the pool after this route
      // ran out; asking again reopens the route with it.
      final done = routeWith(
        status: 'DONE',
        stops: [stopWith(id: 's1', status: 'DONE')],
      );
      final reopened = routeWith(
        currentBatch: 2,
        stops: [
          stopWith(id: 's1', status: 'DONE'),
          stopWith(
            id: 's2',
            orderIndex: 2,
            batchNumber: 2,
            servicePointName: 'Sala 205',
          ),
        ],
      );
      final repository = repositoryWith(done);
      repository.allocate = () {
        repository.day = myDayWith(reopened);
        return AllocationResult(route: reopened, poolEmpty: false);
      };
      await pumpHome(tester, homeWith(repository));

      await tester.tap(checkAgainButton());
      await tester.pumpAndSettle();

      expect(repository.allocationCalls, ['start']);
      expect(checkAgainButton(), findsNothing);
      expect(slotOf('s2'), findsOneWidget);
    });

    testWidgets('"Verificar de novo" with the pool still empty says so', (
      tester,
    ) async {
      final done = routeWith(status: 'DONE', stops: const []);
      final repository = repositoryWith(done)
        ..allocate = () => AllocationResult(route: done, poolEmpty: true);
      await pumpHome(tester, homeWith(repository));

      await tester.tap(checkAgainButton());
      await tester.pumpAndSettle();

      expect(repository.allocationCalls, ['start']);
      expect(find.text(AppStrings.routeNoMorePoints), findsOneWidget);
      expect(checkAgainButton(), findsOneWidget);
    });
  });

  testWidgets('the header reads how far the worker is from the building', (
    tester,
  ) async {
    await pumpHome(
      tester,
      homeWith(repositoryWith(routeWith(stops: [stopIn(id: 's1')]))),
    );
    const worker = LatLng(-7.211, -35.91);
    ProviderScope.containerOf(
      tester.element(find.byType(MapHomeScreen)),
    ).read(workerPositionProvider.notifier).update(worker);
    await tester.pumpAndSettle();

    final meters = const Distance()(worker, const LatLng(-7.21, -35.91));
    expect(find.text(AppStrings.meters(meters.round())), findsOneWidget);
  });
}
