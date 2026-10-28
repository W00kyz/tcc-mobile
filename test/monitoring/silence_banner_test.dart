import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/monitoring/monitoring_providers.dart';
import 'package:route_monitor/monitoring/silence_banner.dart';
import 'package:route_monitor/monitoring/silence_watchdog.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 20, 8);
  late DateTime now;
  late SilenceWatchdog watchdog;

  setUp(() {
    now = t0;
    watchdog = SilenceWatchdog(
      clock: () => now,
      scheduler: _NoopScheduler(),
      warningMinutes: 30,
      releaseMinutes: 45,
    )..startWatching();
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    ProviderScope(
      overrides: [silenceWatchdogProvider.overrideWithValue(watchdog)],
      child: const MaterialApp(home: Scaffold(body: SilenceBanner())),
    ),
  );

  testWidgets('appears by itself once the warning minutes pass', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(AppStrings.silenceChip(30)), findsNothing);

    now = t0.add(const Duration(minutes: 30));
    await tester.pump(SilenceBanner.refreshInterval);

    expect(find.text(AppStrings.silenceChip(30)), findsOneWidget);
  });

  testWidgets('a tap opens the whole warning', (tester) async {
    now = t0.add(const Duration(minutes: 31));
    await pump(tester);

    await tester.tap(find.text(AppStrings.silenceChip(31)));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.silenceWarning(31, 14)), findsOneWidget);
  });

  testWidgets('goes away after the next activity', (tester) async {
    now = t0.add(const Duration(minutes: 31));
    await pump(tester);
    expect(find.text(AppStrings.silenceChip(31)), findsOneWidget);

    watchdog.onActivity();
    await tester.pump(SilenceBanner.refreshInterval);

    expect(find.byType(Text), findsNothing);
  });

  testWidgets('renders nothing without a watchdog (no day loaded yet)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [silenceWatchdogProvider.overrideWithValue(null)],
        child: const MaterialApp(home: Scaffold(body: SilenceBanner())),
      ),
    );

    expect(find.byType(Text), findsNothing);
  });
}

class _NoopScheduler implements LocalScheduler {
  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancel(int id) async {}
}
