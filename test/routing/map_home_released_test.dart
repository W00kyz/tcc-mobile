import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/appeals/appeal_api.dart';
import 'package:route_monitor/appeals/appeal_form_screen.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/released_stop_store.dart';
import 'package:route_monitor/monitoring/notifications_screen.dart';
import 'package:route_monitor/routing/map_home_screen.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/stop_release.dart';
import 'package:route_monitor/sync/sync_providers.dart';

import '../appeals/fake_appeal_api.dart';
import '../support/fake_route_repository.dart';
import '../support/in_memory_database.dart';
import 'map_home_harness.dart';

// Ported from the deleted route_screen_test.dart: the top bar's bell and
// account menu, and the released-stop listener the home keeps (spec
// 2026-10-20-alocacao-automatica §7.5).

RouteSummary _pendingRoute() => routeWith(stops: [stopIn(id: 's1')]);

void main() {
  group('the bell', () {
    testWidgets('shows the unread count on its badge', (tester) async {
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(_pendingRoute()),
          monitoringApi: FakeMonitoringApi(unread: 3),
        ),
      );

      expect(
        find.descendant(of: find.byType(Badge), matching: find.text('3')),
        findsOneWidget,
      );
    });

    testWidgets('shows no badge when there are no unread notifications', (
      tester,
    ) async {
      await pumpHome(tester, homeWith(repositoryWith(_pendingRoute())));

      expect(find.byType(Badge), findsNothing);
    });

    testWidgets('a tap opens the notifications screen', (tester) async {
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(_pendingRoute()),
          monitoringApi: FakeMonitoringApi(unread: 1),
        ),
      );

      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsScreen), findsOneWidget);
    });
  });

  group('released stops (spec 2026-10-20-alocacao-automatica §7.5)', () {
    final route = routeWith(
      stops: [
        stopWith(
          id: 's1',
          status: 'RELEASED',
          releaseReason: 'LOCATION_SILENCE',
          servicePointName: 'Sala 101',
        ),
        stopWith(id: 's2', orderIndex: 2, servicePointName: 'Sala 102'),
      ],
    );

    /// The device's database, holding an appealable notice for s1.
    Future<AppDatabase> dbWithNotice() async {
      final db = inMemoryDatabase();
      addTearDown(db.close);
      await DriftReleasedStopStore(db).record(
        routeStopId: 's1',
        releaseReason: 'LOCATION_SILENCE',
        appealable: true,
      );
      return db;
    }

    ProviderContainer container(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(MapHomeScreen)));

    void announce(WidgetTester tester, {required bool appealable}) {
      container(tester)
          .read(stopReleaseAnnouncementsProvider.notifier)
          .announce(
            StopRelease(
              routeStopId: 's1',
              releaseReason: 'LOCATION_SILENCE',
              appealable: appealable,
            ),
          );
    }

    testWidgets(
      'an appealable release shows the snackbar, and "Recorrer" opens the '
      "stop's appeal form",
      (tester) async {
        final db = await dbWithNotice();
        await pumpHome(
          tester,
          homeWith(
            repositoryWith(route),
            releasedStopStore: DriftReleasedStopStore(db),
          ),
        );

        announce(tester, appealable: true);
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.releasedStopsSnackbar), findsOneWidget);
        await tester.tap(find.text(AppStrings.releasedStopsSnackbarAction));
        await tester.pumpAndSettle();

        final form = tester.widget<AppealFormScreen>(
          find.byType(AppealFormScreen),
        );
        expect(form.routeStopId, 's1');
        expect(form.servicePointName, 'Sala 101');
      },
    );

    testWidgets('the "Recorrer" snackbar floats above "Escanear QR"', (
      tester,
    ) async {
      final db = await dbWithNotice();
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(route),
          releasedStopStore: DriftReleasedStopStore(db),
        ),
      );

      for (final size in [0.5, 0.22]) {
        await snapSheetTo(tester, size);
        announce(tester, appealable: true);
        await tester.pumpAndSettle();
        final snack = tester.getRect(
          find
              .descendant(
                of: find.byType(SnackBar),
                matching: find.byType(Material),
              )
              .first,
        );
        final scan = tester.getRect(scanQrButton());
        expect(snack.bottom, lessThanOrEqualTo(scan.top), reason: 'at $size');
        ScaffoldMessenger.of(
          tester.element(find.byType(MapHomeScreen)),
        ).clearSnackBars();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('a release the worker cannot appeal shows no snackbar', (
      tester,
    ) async {
      await pumpHome(tester, homeWith(repositoryWith(route)));

      announce(tester, appealable: false);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.releasedStopsSnackbar), findsNothing);
    });

    testWidgets(
      'a reload of the day refreshes the appeals badge: the server may have '
      'released points meanwhile',
      (tester) async {
        final appealApi = RecordingAppealApi();
        await pumpHome(
          tester,
          homeWith(repositoryWith(route), appealApi: appealApi),
        );
        final callsAfterLoad = appealApi.eligibleCalls;

        container(tester).invalidate(myDayProvider);
        await tester.pumpAndSettle();

        expect(appealApi.eligibleCalls, callsAfterLoad + 1);
      },
    );

    testWidgets('a released stop without a reason reads just "Liberado"', (
      tester,
    ) async {
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(
            routeWith(
              stops: [
                stopWith(id: 's1', status: 'RELEASED', servicePointName: 'X'),
                stopWith(id: 's2', orderIndex: 2),
              ],
            ),
          ),
        ),
      );
      await openStopSheet(tester, 's1');

      expect(find.text('Liberado'), findsOneWidget);
      expect(find.textContaining('Liberado · '), findsNothing);
    });

    testWidgets(
      'the account avatar counts the points the worker can contest and is a '
      'direct link to Perfil, with no menu',
      (tester) async {
        await pumpHome(
          tester,
          homeWith(
            repositoryWith(route),
            appealApi: RecordingAppealApi(
              eligibleStops: [
                AppealableStop(
                  routeStopId: 's1',
                  servicePointName: 'Sala 101',
                  buildingName: 'Bloco CAA',
                  floorLabel: 'Térreo',
                  releaseReason: 'LOCATION_SILENCE',
                  deadline: DateTime.utc(2026, 10, 22, 14),
                ),
              ],
            ),
          ),
        );

        expect(find.byTooltip(AppStrings.profileTooltip), findsOneWidget);
        expect(find.widgetWithText(Badge, '1'), findsOneWidget);
        expect(find.byType(PopupMenuButton<Object>), findsNothing);
      },
    );
  });
}
