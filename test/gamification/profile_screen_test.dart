import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/gamification/gamification_providers.dart';
import 'package:route_monitor/gamification/profile_screen.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/day_log_store.dart';
import 'package:route_monitor/ui/app_theme.dart';

import '../support/fake_day_log_store.dart';
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

Future<void> _pump(WidgetTester tester) async {
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
      ],
      child: MaterialApp(theme: buildAppTheme(), home: const ProfileScreen()),
    ),
  );
  await tester.pumpAndSettle();
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

  testWidgets('no ranking and no other worker', (tester) async {
    await _pump(tester);

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => (t.data ?? t.textSpan?.toPlainText() ?? '').toLowerCase());
    expect(texts.where((t) => t.contains('ranking')), isEmpty);
    expect(texts.where((t) => t.contains('média')), isEmpty);
  });
}
