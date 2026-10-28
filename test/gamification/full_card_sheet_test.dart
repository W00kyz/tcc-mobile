import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_monitor/gamification/full_card_sheet.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/day_log_store.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/routing/batch_allocation.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/ui/app_theme.dart';

import '../routing/map_home_harness.dart';
import '../support/fake_day_log_store.dart';
import '../support/fake_route_repository.dart';

/// Records "Pegar próximo lote" instead of asking a server.
class _RecordingAllocation extends BatchAllocation {
  int retries = 0;

  @override
  NextBatchState build() => NextBatchState.idle;

  @override
  Future<void> retry() async => retries++;
}

CardSlot _done(String id, DateTime at) => CardSlot(
  stopId: id,
  state: SlotState.done,
  floorLabel: 'Térreo',
  stampedAt: at,
  pendingSync: false,
  releaseReason: null,
  stampRotationDeg: 0,
);

/// Batch 2, eight stamps; the last one at 11:25.
BatchCard _card() => BatchCard(
  batchNumber: 2,
  groups: [
    BuildingGroup(
      buildingId: 'b1',
      buildingName: 'Central de Aulas',
      position: const LatLng(0, 0),
      slots: [
        for (var i = 0; i < 7; i++)
          _done('s$i', DateTime(2026, 10, 21, 8 + i % 3, 10)),
        _done('s7', DateTime(2026, 10, 21, 11, 25)),
      ],
    ),
  ],
);

Future<_RecordingAllocation> _open(WidgetTester tester) async {
  final allocation = _RecordingAllocation();
  tester.view
    ..physicalSize = const Size(420, 1400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [batchAllocationProvider.overrideWith(() => allocation)],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFullCard(
                context,
                _card(),
                streak: 5,
                startedAt: DateTime(2026, 10, 21, 7, 42),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return allocation;
}

void main() {
  testWidgets('shows the title, the batch time from the first check-in to '
      'the last stamp, and the streak', (tester) async {
    await _open(tester);

    expect(find.text('CARTÃO COMPLETO!'), findsOneWidget);
    expect(find.text('Lote 2 · 8 pontos em 3 h 43 min'), findsOneWidget);
    expect(find.text('5 dias seguidos'), findsOneWidget);
    expect(find.text('CARTÃO DO LOTE 2'), findsOneWidget);
    expect(find.text('8/8'), findsOneWidget);
  });

  testWidgets('"Pegar próximo lote" closes the sheet and asks for the next '
      'batch', (tester) async {
    final allocation = await _open(tester);

    await tester.tap(find.text(AppStrings.fullCardNextBatch));
    await tester.pumpAndSettle();

    expect(find.text('CARTÃO COMPLETO!'), findsNothing);
    expect(allocation.retries, 1);
  });

  testWidgets('"Ver mapa" closes it without asking', (tester) async {
    final allocation = await _open(tester);

    await tester.tap(find.text(AppStrings.fullCardSeeMap));
    await tester.pumpAndSettle();

    expect(find.text('CARTÃO COMPLETO!'), findsNothing);
    expect(allocation.retries, 0);
  });

  testWidgets('both actions are at least 48dp tall', (tester) async {
    await _open(tester);

    for (final label in [
      AppStrings.fullCardNextBatch,
      AppStrings.fullCardSeeMap,
    ]) {
      final button = find.ancestor(
        of: find.text(label),
        matching: find.bySubtype<ButtonStyleButton>(),
      );
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    }
  });

  test('batchElapsed falls back to the first stamp without a check-in', () {
    expect(batchElapsed(_card(), null), const Duration(hours: 3, minutes: 15));
  });

  group('on the map home', () {
    /// Batch 2: s1 already done on the server, s2 in progress here.
    List<RouteStopSummary> stops() => [
      stopIn(id: 's1', batchNumber: 2, status: 'DONE'),
      stopIn(id: 's2', batchNumber: 2, status: 'IN_PROGRESS', orderIndex: 2),
    ];

    /// Concludes s2, the batch's last stop. The sync worker never delivers
    /// anything, so the check-out just written is still unsent when the
    /// card is counted (ruling R14). [prepare] seeds the outbox first.
    Future<RecordingDayLogStore> concludeLast(
      WidgetTester tester, {
      Future<void> Function(InMemoryLocalWriteStore store)? prepare,
    }) async {
      final store = InMemoryLocalWriteStore();
      await prepare?.call(store);
      final today = DateTime.now();
      final dayLog = RecordingDayLogStore(
        entries: [
          DayLogEntry(
            day: DateTime(today.year, today.month, today.day),
            serviceDay: true,
            pointsDone: 2,
            cardsCompleted: 0,
            cleanCards: 0,
          ),
        ],
      );
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(routeWith(stops: stops(), currentBatch: 2)),
          stopProgressStore: FakeStopProgressStore({'s2': 'exec-2'}),
          localWriteStore: store,
          syncWorker: RecordingSyncWorker(),
          dayLogStore: dayLog,
        ),
      );
      await concludeWith(tester, 'v1.floor.1.sig');
      return dayLog;
    }

    testWidgets('the last stamp opens the full card and records one clean '
        'card right away, its own unsent check-out aside', (tester) async {
      final dayLog = await concludeLast(tester);

      expect(find.text(AppStrings.fullCardTitle), findsOneWidget);
      expect(find.text('1 dia seguido'), findsOneWidget);
      expect(
        dayLog.calls.where((c) => c.startsWith('cardCompleted')),
        [endsWith(':true')],
      );
      expect(dayLog.calls, contains(startsWith('stopDone:')));
    });

    testWidgets("an earlier stop's unsent row makes the card not clean", (
      tester,
    ) async {
      final dayLog = await concludeLast(
        tester,
        prepare: (store) async {
          await store.enqueue(
            id: 's1-out',
            kind: PendingOpKind.checkOut,
            routeId: 'r1',
            payload: const {'route_stop_id': 's1'},
          );
        },
      );

      expect(find.text(AppStrings.fullCardTitle), findsOneWidget);
      expect(
        dayLog.calls.where((c) => c.startsWith('cardCompleted')),
        [endsWith(':false')],
      );
    });

    testWidgets('a blocked row makes the card not clean', (tester) async {
      final dayLog = await concludeLast(
        tester,
        prepare: (store) async {
          await store.enqueue(
            id: 'old-photo',
            kind: PendingOpKind.evidencePhoto,
            routeId: 'r1',
            payload: const {'execution_id': 'exec-1'},
          );
          await store.markBlocked('old-photo', 'HTTP 422');
        },
      );

      expect(
        dayLog.calls.where((c) => c.startsWith('cardCompleted')),
        [endsWith(':false')],
      );
    });

    testWidgets('a stamp that leaves the card open shows no full card', (
      tester,
    ) async {
      final dayLog = RecordingDayLogStore();
      final store = InMemoryLocalWriteStore();
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(
            routeWith(
              stops: [
                ...stops(),
                stopIn(id: 's3', batchNumber: 2, orderIndex: 3),
              ],
              currentBatch: 2,
            ),
          ),
          stopProgressStore: FakeStopProgressStore({'s2': 'exec-2'}),
          localWriteStore: store,
          syncWorker: RecordingSyncWorker(drains: store),
          dayLogStore: dayLog,
        ),
      );
      await concludeWith(tester, 'v1.floor.1.sig');

      expect(find.text(AppStrings.fullCardTitle), findsNothing);
      expect(dayLog.calls.where((c) => c.startsWith('cardCompleted')), isEmpty);
    });

    testWidgets('recordDayOpened is called when myDayProvider resolves', (
      tester,
    ) async {
      final dayLog = RecordingDayLogStore();
      await pumpHome(
        tester,
        homeWith(
          FakeRouteRepository(myDayWith(null, serviceDay: false)),
          dayLogStore: dayLog,
        ),
      );

      expect(dayLog.calls, [startsWith('opened:')]);
      expect(dayLog.calls.single, endsWith(':false'));
    });

    testWidgets('a cached day from another date is not logged as today', (
      tester,
    ) async {
      final dayLog = RecordingDayLogStore();
      // routeWith's route is dated 2026-10-20: the offline cache of a past
      // day, not today.
      await pumpHome(
        tester,
        homeWith(
          repositoryWith(routeWith(stops: stops(), currentBatch: 2)),
          dayLogStore: dayLog,
        ),
      );

      expect(dayLog.calls.where((c) => c.startsWith('opened:')), isEmpty);
    });

    testWidgets('a day whose route is dated today is logged', (tester) async {
      final dayLog = RecordingDayLogStore();
      final past = routeWith(stops: stops(), currentBatch: 2);
      final now = DateTime.now();
      final todays = RouteSummary(
        id: past.id,
        fieldWorkerName: past.fieldWorkerName,
        routeDate: DateTime(now.year, now.month, now.day),
        status: past.status,
        startedAt: past.startedAt,
        currentBatch: past.currentBatch,
        stops: past.stops,
      );
      await pumpHome(
        tester,
        homeWith(repositoryWith(todays), dayLogStore: dayLog),
      );

      expect(dayLog.calls, contains(endsWith(':true')));
    });
  });
}
