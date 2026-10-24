import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/monitoring/silence_watchdog.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 20, 8);
  late DateTime now;
  late _RecordingScheduler scheduler;

  setUp(() {
    now = t0;
    scheduler = _RecordingScheduler();
  });

  SilenceWatchdog build({int warning = 30, int release = 45}) =>
      SilenceWatchdog(
        clock: () => now,
        scheduler: scheduler,
        warningMinutes: warning,
        releaseMinutes: release,
      );

  test('no banner before a route is being watched', () {
    final watchdog = build();
    now = t0.add(const Duration(hours: 2));

    expect(watchdog.currentWarning(), isNull);
  });

  test('the banner shows once the warning minutes have passed', () {
    final watchdog = build()..startWatching();

    now = t0.add(const Duration(minutes: 29));
    expect(watchdog.currentWarning(), isNull);

    now = t0.add(const Duration(minutes: 30));
    expect(
      watchdog.currentWarning(),
      (silentMinutes: 30, minutesUntilRelease: 15),
    );

    now = t0.add(const Duration(minutes: 50));
    expect(
      watchdog.currentWarning(),
      (silentMinutes: 50, minutesUntilRelease: 0),
    );
  });

  test('the limits come from the server, not from constants', () {
    final watchdog = build(warning: 10, release: 20)..startWatching();
    now = t0.add(const Duration(minutes: 10));

    expect(
      watchdog.currentWarning(),
      (silentMinutes: 10, minutesUntilRelease: 10),
    );
  });

  test('activity resets the silence clock', () {
    final watchdog = build()
      ..startWatching()
      ..onActivity(t0.add(const Duration(minutes: 20)));
    now = t0.add(const Duration(minutes: 45));
    expect(watchdog.currentWarning(), isNull);

    now = t0.add(const Duration(minutes: 50));
    expect(
      watchdog.currentWarning(),
      (silentMinutes: 30, minutesUntilRelease: 15),
    );
  });

  test('activity without a time is stamped by the clock', () {
    final watchdog = build()..startWatching();
    now = t0.add(const Duration(minutes: 40));

    watchdog.onActivity();

    expect(watchdog.currentWarning(), isNull);
  });

  test('pausing schedules one notification at last activity + warning', () {
    final watchdog = build()..startWatching();
    now = t0.add(const Duration(minutes: 10));

    watchdog.onAppPaused();

    expect(scheduler.scheduled, hasLength(1));
    final scheduled = scheduler.scheduled.single;
    expect(scheduled.id, SilenceWatchdog.notificationId);
    expect(scheduled.at, t0.add(const Duration(minutes: 30)));
    expect(scheduled.title, AppStrings.silenceNotificationTitle);
    expect(scheduled.body, AppStrings.silenceWarning(30, 15));
  });

  test('resuming cancels the scheduled notification', () {
    build()
      ..startWatching()
      ..onAppPaused()
      ..onAppResumed();

    expect(scheduler.cancelled, [SilenceWatchdog.notificationId]);
  });

  test('activity while paused moves the notification forward', () {
    final watchdog = build()..startWatching();
    now = t0.add(const Duration(minutes: 5));
    watchdog
      ..onAppPaused()
      // A fix sent by the background service with the screen locked.
      ..onActivity(t0.add(const Duration(minutes: 12)));

    expect(
      scheduler.scheduled.map((s) => s.at),
      [
        t0.add(const Duration(minutes: 30)),
        t0.add(const Duration(minutes: 42)),
      ],
    );
  });

  test('pausing past the warning schedules it shortly after leaving', () {
    final watchdog = build()..startWatching();
    now = t0.add(const Duration(minutes: 33));

    watchdog.onAppPaused();

    final scheduled = scheduler.scheduled.single;
    expect(scheduled.at, now.add(const Duration(minutes: 1)));
    expect(scheduled.body, AppStrings.silenceWarning(34, 11));
  });

  test('nothing is scheduled when no route is being watched', () {
    build().onAppPaused();

    expect(scheduler.scheduled, isEmpty);
  });

  test('stopping cancels a scheduled notification and clears the banner', () {
    final watchdog = build()
      ..startWatching()
      ..onAppPaused()
      ..stopWatching();
    now = t0.add(const Duration(hours: 1));

    expect(scheduler.cancelled, [SilenceWatchdog.notificationId]);
    expect(watchdog.currentWarning(), isNull);
  });

  test('startWatching keeps the clock of a route already watched', () {
    final watchdog = build()..startWatching();
    now = t0.add(const Duration(minutes: 31));

    watchdog.startWatching();

    expect(watchdog.currentWarning(), isNotNull);
  });

  test('resuming with nothing scheduled touches no notification', () {
    build()
      ..startWatching()
      ..onAppResumed();

    expect(scheduler.cancelled, isEmpty);
  });
}

class _Scheduled {
  _Scheduled(this.id, this.at, this.title, this.body);
  final int id;
  final DateTime at;
  final String title;
  final String body;
}

/// Records the calls instead of reaching `flutter_local_notifications`.
class _RecordingScheduler implements LocalScheduler {
  final List<_Scheduled> scheduled = [];
  final List<int> cancelled = [];

  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async => scheduled.add(_Scheduled(id, at, title, body));

  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}
