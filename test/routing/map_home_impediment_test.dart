import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/routing/batch_card_model.dart' show SlotState;
import 'package:route_monitor/routing/floor_actions.dart';
import 'package:route_monitor/routing/map_home_screen.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/ui/stamp_slot.dart';

import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';

// A task reported impossible from the home: its STOP impediment is written
// first, the floor card greys its slot at once (offline too), and once the
// server has it the released stop lets the next batch in. The dialog that
// asks for the reason is the task dialog's (Task 7); here the flow is driven
// through the same `signalTaskImpossible` it calls.

RouteSummary _pendingRoute() => routeWith(stops: [stopIn(id: 's1')]);

WidgetRef _homeRef(WidgetTester tester) =>
    tester.element(find.byType(MapHomeScreen)) as WidgetRef;

Future<void> _signal(WidgetTester tester, RouteSummary route) async {
  await signalTaskImpossible(
    tester.element(find.byType(MapHomeScreen)),
    _homeRef(tester),
    route,
    route.stops.first,
    reason: 'ACCESS_BLOCKED',
    note: 'Portão fechado.',
  );
  await tester.pumpAndSettle();
}

void main() {
  group('a task reported impossible', () {
    testWidgets('enqueues a STOP impediment for that stop and greys its slot', (
      tester,
    ) async {
      final store = InMemoryLocalWriteStore();
      final route = _pendingRoute();
      await pumpHomeWithSheet(
        tester,
        homeWith(repositoryWith(route), localWriteStore: store),
      );

      await _signal(tester, route);

      final rows = await store.unsyncedForRoute('r1');
      expect(rows, hasLength(1));
      expect(rows.single.kind, PendingOpKind.impediment);
      expect(rows.single.payload['scope'], 'STOP');
      expect(rows.single.payload['route_stop_id'], 's1');
      expect(rows.single.payload['reason'], 'ACCESS_BLOCKED');
      expect(rows.single.payload['note'], 'Portão fechado.');
      expect(find.text(AppStrings.taskImpededDone), findsOneWidget);
      expect(
        tester.widget<StampSlot>(slotOf('s1')).slot.state,
        SlotState.impeded,
      );
      expect(shownFloorCard(tester).animateImpededStopId, 's1');
    });

    testWidgets(
      'on the last open stop reloads the day once it synced, and the released '
      'stop lets the next batch in',
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
        final first = routeWith(
          stops: [stopWith(id: 's1', servicePointName: 'Sala 101')],
        );
        final repository = repositoryWith(first);
        repository.allocate = () {
          repository.day = myDayWith(secondBatch);
          return AllocationResult(route: secondBatch, poolEmpty: false);
        };
        await pumpHomeWithSheet(
          tester,
          homeWith(
            repository,
            localWriteStore: store,
            syncWorker: RecordingSyncWorker(drains: store),
          ),
        );
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

        await _signal(tester, first);

        expect(repository.allocationCalls, ['nextBatch:r1']);
        // The new batch starts with no building selected.
        await tapPin(tester, 'b1');
        expect(slotOf('s2'), findsOneWidget);
      },
    );
  });
}
