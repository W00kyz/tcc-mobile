import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/route_repository.dart';

import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';

// The start button out of hours (spec §2): disabled before the opening, a
// ticking countdown in the last 5 minutes, enabled again at zero, and a
// disabled "Rota finalizada" on a finished route. The clock is injected.

final _opensAt = DateTime.utc(2026, 11, 2, 10);

/// A service day whose workday opens at [_opensAt]; the server clock reads
/// like the device clock (offset zero).
MyDay _dayOpeningAt10({RouteSummary? route}) => MyDay(
  serviceDay: true,
  route: route,
  positionIntervalSeconds: 60,
  silenceWarningMinutes: 30,
  silenceReleaseMinutes: 45,
  serverTime: DateTime.utc(2026, 11, 2, 9),
  startOpensAt: _opensAt,
);

Finder _button(String label) => find.widgetWithText(FilledButton, label);

bool _isEnabled(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(_button(label)).onPressed != null;

void main() {
  late DateTime now;

  Widget home(FakeRouteRepository repository) =>
      homeWith(repository, startClock: () => now);

  setUp(() => now = DateTime.utc(2026, 11, 2, 9));

  testWidgets('start_button_is_disabled_before_the_workday', (tester) async {
    await pumpHome(tester, home(FakeRouteRepository(_dayOpeningAt10())));

    expect(_button(AppStrings.routeStartButton), findsOneWidget);
    expect(_isEnabled(tester, AppStrings.routeStartButton), isFalse);
    expect(find.text(AppStrings.routeStartNotOpenYet), findsOneWidget);
    expect(find.textContaining('Abre em'), findsNothing);
  });

  testWidgets('start_button_shows_a_ticking_countdown_in_the_last_5_minutes', (
    tester,
  ) async {
    now = DateTime.utc(2026, 11, 2, 9, 55, 28);
    await pumpHome(tester, home(FakeRouteRepository(_dayOpeningAt10())));

    expect(find.text('Abre em 04:32'), findsOneWidget);
    expect(find.text(AppStrings.routeStartNotOpenYet), findsNothing);
    expect(_isEnabled(tester, 'Abre em 04:32'), isFalse);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Abre em 04:31'), findsOneWidget);
    expect(find.text('Abre em 04:32'), findsNothing);
  });

  testWidgets('the_caption_gives_way_to_the_countdown_when_the_window_opens', (
    tester,
  ) async {
    now = DateTime.utc(2026, 11, 2, 9, 50);
    await pumpHome(tester, home(FakeRouteRepository(_dayOpeningAt10())));
    expect(find.text(AppStrings.routeStartNotOpenYet), findsOneWidget);

    now = DateTime.utc(2026, 11, 2, 9, 55);
    await tester.pump(const Duration(minutes: 5));

    expect(find.text(AppStrings.routeStartNotOpenYet), findsNothing);
    expect(find.text('Abre em 05:00'), findsOneWidget);
  });

  testWidgets('start_button_enables_and_reloads_the_day_at_zero', (
    tester,
  ) async {
    now = DateTime.utc(2026, 11, 2, 9, 59, 58);
    final repository = FakeRouteRepository(_dayOpeningAt10());
    await pumpHome(tester, home(repository));
    expect(repository.fetchCount, 1);

    now = _opensAt;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(repository.fetchCount, 2);
    expect(_isEnabled(tester, AppStrings.routeStartButton), isTrue);
    expect(find.textContaining('Abre em'), findsNothing);

    // The countdown is over: no further tick reloads the day again.
    await tester.pump(const Duration(seconds: 10));
    expect(repository.fetchCount, 2);
  });

  testWidgets('paused_route_shows_continuar_rota_enabled', (tester) async {
    final paused = routeWith(
      status: 'PAUSED',
      stops: [stopWith(id: 's1', status: 'RELEASED')],
    );
    // Before the opening, even: the opening only holds a first start.
    await pumpHome(
      tester,
      home(FakeRouteRepository(_dayOpeningAt10(route: paused))),
    );

    expect(_button(AppStrings.dayResumeButton), findsOneWidget);
    expect(_isEnabled(tester, AppStrings.dayResumeButton), isTrue);
  });

  testWidgets('done_route_shows_a_disabled_rota_finalizada_button', (
    tester,
  ) async {
    final done = routeWith(
      status: 'DONE',
      stops: [stopWith(id: 's1', status: 'DONE')],
    );
    await pumpHome(tester, home(FakeRouteRepository(myDayWith(done))));

    expect(_button(AppStrings.routeFinishedButton), findsOneWidget);
    expect(_isEnabled(tester, AppStrings.routeFinishedButton), isFalse);
  });

  testWidgets('no_start_bar_on_a_non_service_day', (tester) async {
    await pumpHome(
      tester,
      home(FakeRouteRepository(myDayWith(null, serviceDay: false))),
    );

    expect(find.text(AppStrings.dayNoService), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('countdown_timer_is_cancelled_on_dispose', (tester) async {
    now = DateTime.utc(2026, 11, 2, 9, 59, 58);
    final repository = FakeRouteRepository(_dayOpeningAt10());
    await pumpHome(tester, home(repository));

    await tester.pumpWidget(const SizedBox.shrink());
    now = _opensAt;
    await tester.pump(const Duration(seconds: 10));

    // A live timer would have hit zero and reloaded the day (and flutter_test
    // fails a test that ends with a timer pending).
    expect(repository.fetchCount, 1);
  });
}
