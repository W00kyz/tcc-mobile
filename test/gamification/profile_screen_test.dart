import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/appeals/appeal_api.dart';
import 'package:route_monitor/appeals/appeal_providers.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/execution_repository.dart';
import 'package:route_monitor/gamification/gamification_providers.dart';
import 'package:route_monitor/gamification/profile_screen.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/day_log_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/ui/app_theme.dart';

import '../routing/map_home_fakes.dart';
import '../support/fake_day_log_store.dart';
import '../support/fake_route_repository.dart';
import '../support/in_memory_database.dart';

/// Thursday 2026-10-22; the week runs Mon 19 .. Sun 25.
final DateTime _today = DateTime(2026, 10, 22, 15);

DayLogEntry _day(DateTime day, {int points = 0, bool serviceDay = true}) =>
    DayLogEntry(
      day: day,
      serviceDay: serviceDay,
      pointsDone: points,
      cardsCompleted: 1,
      cleanCards: 0,
    );

/// Twelve worked weekdays in a row before today, Wednesday 21 a day
/// without service, and today opened with nothing done yet.
List<DayLogEntry> _log() => [
  for (var d = 5; d <= 9; d++) _day(DateTime(2026, 10, d), points: 2),
  for (var d = 12; d <= 16; d++) _day(DateTime(2026, 10, d), points: 2),
  _day(DateTime(2026, 10, 19), points: 2),
  _day(DateTime(2026, 10, 20), points: 2),
  _day(DateTime(2026, 10, 21), serviceDay: false),
  _day(DateTime(2026, 10, 22)),
];

/// The Recursos badge reads the appeal lists; keep them off the network and
/// the database.
List<Override> _noAppealsBut(List<AppealableStop> contestable) => [
  appealEligibleProvider.overrideWith((_) async => contestable),
  localReleasedNoticesProvider.overrideWith((_) async => const []),
];

Future<void> _pump(
  WidgetTester tester, {
  List<AppealableStop> contestable = const [],
}) async {
  tester.view
    ..physicalSize = const Size(420, 1400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dayLogStoreProvider.overrideWithValue(
          RecordingDayLogStore(entries: _log()),
        ),
        gamificationClockProvider.overrideWithValue(() => _today),
        ..._noAppealsBut(contestable),
        myDayProvider.overrideWith((_) async => myDayWith(null)),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: const ProfileScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// A sync that never answers, like a pass stuck on a dead network.
class HangingSyncWorker extends RecordingSyncWorker {
  final Completer<void> _never = Completer<void>();

  @override
  Future<void> syncRoute(String routeId) {
    syncedRoutes.add(routeId);
    return _never.future;
  }
}

void main() {
  testWidgets('shows the title, the streak and the week Seg..Dom with the '
      'no-service note', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);

    expect(find.text('Seu perfil'), findsOneWidget);
    expect(find.text('12 dias seguidos'), findsOneWidget);
    for (final day in ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom']) {
      expect(find.text(day), findsOneWidget);
    }
    expect(
      find.text('Dia sem serviço não quebra a sequência.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(AppStrings.profileNoServiceDay), findsOne);
    semantics.dispose();
  });

  testWidgets('five achievement stamps; locked ones show current/target', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Conquistas'), findsOneWidget);
    for (final label in [
      'Primeiro cartão completo',
      '5 dias seguidos',
      '20 dias seguidos',
      '100 pontos concluídos',
      'Cartão completo sem pendências',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      find.byKey(const ValueKey('achievement-unlocked-firstCard')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('achievement-unlocked-streak5')),
      findsOne,
    );
    expect(find.byKey(const ValueKey('achievement-locked-streak20')), findsOne);
    expect(find.text('12/20'), findsOneWidget);
    expect(find.text('24/100'), findsOneWidget);
    expect(find.text('0/1'), findsOneWidget);
    // Locked never reads as done: no check on a locked stamp.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('achievement-locked-cleanCard')),
        matching: find.byIcon(Icons.check),
      ),
      findsNothing,
    );
  });

  testWidgets('reopened after a check-out, the profile shows the new '
      'point', (tester) async {
    final db = inMemoryDatabase();
    addTearDown(db.close);
    final store = DriftDayLogStore(db);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dayLogStoreProvider.overrideWithValue(store),
          gamificationClockProvider.overrideWithValue(() => _today),
          ..._noAppealsBut(const []),
          myDayProvider.overrideWith((_) async => myDayWith(null)),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    Future<void> openProfile() async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    await openProfile();
    expect(find.text('0 dias seguidos'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // A check-out while the profile is closed.
    await store.recordStopDone(_today);
    await openProfile();

    expect(find.text('1 dia seguido'), findsOneWidget);
    expect(find.text('1/100'), findsOneWidget);
  });

  testWidgets('shortcuts to Meus dados, Recursos and Sair, each 48dp+', (
    tester,
  ) async {
    await _pump(tester);

    for (final label in ['Meus dados', 'Recursos', 'Sair']) {
      final tile = find.ancestor(
        of: find.text(label),
        matching: find.byType(ListTile),
      );
      expect(tile, findsOneWidget);
      expect(tester.getSize(tile).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('the Recursos row carries the contestable-points badge that '
      'used to sit in the avatar menu', (tester) async {
    await _pump(
      tester,
      contestable: [
        AppealableStop(
          routeStopId: 's1',
          servicePointName: 'Sala 101',
          buildingName: 'Bloco CAA',
          floorLabel: 'Térreo',
          releaseReason: 'LOCATION_SILENCE',
          deadline: DateTime.utc(2026, 10, 22, 14),
        ),
      ],
    );

    final row = find.ancestor(
      of: find.text('Recursos'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: row, matching: find.widgetWithText(Badge, '1')),
      findsOneWidget,
    );
  });

  testWidgets('no ranking and no other worker', (tester) async {
    await _pump(tester);

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => (t.data ?? t.textSpan?.toPlainText() ?? '').toLowerCase());
    expect(texts.where((t) => t.contains('ranking')), isEmpty);
    expect(texts.where((t) => t.contains('média')), isEmpty);
  });

  group('Encerrar por hoje', () {
    late AppDatabase db;
    late InMemoryLocalWriteStore store;
    late RecordingSyncWorker worker;

    setUp(() {
      db = inMemoryDatabase();
      addTearDown(db.close);
      store = InMemoryLocalWriteStore();
      worker = RecordingSyncWorker();
    });

    /// The profile opened over a "map" button, with a day whose route has
    /// [routeStatus] (no route at all when null).
    Future<void> openProfile(WidgetTester tester, {String? routeStatus}) async {
      tester.view
        ..physicalSize = const Size(420, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final route = routeStatus == null
          ? null
          : routeWith(
              stops: [stopWith(id: 's1')],
              status: routeStatus,
            );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dayLogStoreProvider.overrideWithValue(
              RecordingDayLogStore(entries: _log()),
            ),
            gamificationClockProvider.overrideWithValue(() => _today),
            ..._noAppealsBut(const []),
            myDayProvider.overrideWith((_) async => myDayWith(route)),
            syncWorkerProvider.overrideWithValue(worker),
            executionRepositoryProvider.overrideWithValue(
              ExecutionRepository(
                store,
                DriftStopProgressStore(db),
                worker,
                database: db,
                dayLog: RecordingDayLogStore(),
              ),
            ),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ProfileScreen(),
                  ),
                ),
                child: const Text('map'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('map'));
      await tester.pumpAndSettle();
    }

    testWidgets('is offered only while the route is in progress', (
      tester,
    ) async {
      await openProfile(tester, routeStatus: 'PAUSED');
      expect(find.text(AppStrings.profileEndDay), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await openProfile(tester);
      expect(find.text(AppStrings.profileEndDay), findsNothing);
    });

    testWidgets('reads as a 56dp row with its subtitle', (tester) async {
      await openProfile(tester, routeStatus: 'IN_PROGRESS');
      final tile = find.ancestor(
        of: find.text(AppStrings.profileEndDay),
        matching: find.byType(ListTile),
      );
      expect(tester.getSize(tile).height, greaterThanOrEqualTo(56));
      expect(find.text(AppStrings.profileEndDaySubtitle), findsOneWidget);
    });

    testWidgets('the reason is reported as ROUTE_REMAINDER, then back to the '
        'map', (tester) async {
      await openProfile(tester, routeStatus: 'IN_PROGRESS');
      await tester.tap(find.text(AppStrings.profileEndDay));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.impedimentReasonHealthIssue));
      await tester.pump();
      await tester.tap(find.text(AppStrings.commonConfirm));
      await tester.pumpAndSettle();

      final row = (await store.unsyncedForRoute('r1')).single;
      expect(row.payload['scope'], 'ROUTE_REMAINDER');
      expect(row.payload['reason'], 'HEALTH_ISSUE');
      expect(row.payload['route_stop_id'], isNull);
      expect(worker.syncedRoutes, contains('r1'));
      expect(find.byType(ProfileScreen), findsNothing);
      expect(find.text('map'), findsOneWidget);
    });

    testWidgets('an offline sync does not hold the worker on the profile', (
      tester,
    ) async {
      worker = HangingSyncWorker();
      await openProfile(tester, routeStatus: 'IN_PROGRESS');
      await tester.tap(find.text(AppStrings.profileEndDay));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.impedimentReasonOther));
      await tester.pump();
      await tester.tap(find.text(AppStrings.commonConfirm));
      await tester.pumpAndSettle();

      expect(
        (await store.unsyncedForRoute('r1')).single.payload['scope'],
        'ROUTE_REMAINDER',
      );
      expect(find.byType(ProfileScreen), findsNothing);
      expect(find.text('map'), findsOneWidget);
    });

    testWidgets('cancelling the reason reports nothing and stays', (
      tester,
    ) async {
      await openProfile(tester, routeStatus: 'IN_PROGRESS');
      await tester.tap(find.text(AppStrings.profileEndDay));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.commonCancel));
      await tester.pumpAndSettle();

      expect(await store.unsyncedForRoute('r1'), isEmpty);
      expect(find.byType(ProfileScreen), findsOneWidget);
    });
  });
}
