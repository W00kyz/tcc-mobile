// The constructor forwards public named params to private fields, like
// position_reporter.dart: a private field can't be an initializing formal
// while its param name stays public.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math' as math;

import 'package:route_monitor/l10n/strings.dart';

/// The current time, injected so tests drive the silence clock by hand.
typedef Clock = DateTime Function();

/// The warning the worker sees: minutes without activity, and minutes left
/// before the server releases their points.
typedef SilenceWarning = ({int silentMinutes, int minutesUntilRelease});

/// One local notification at a time, behind this project's interface so the
/// watchdog and its tests never reach `flutter_local_notifications`.
abstract class LocalScheduler {
  /// Shows a notification at [at] even with the app suspended; a later call
  /// with the same [id] replaces it.
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  });

  Future<void> cancel(int id);
}

/// The app's half of the location-silence rule (spec
/// 2026-10-20-alocacao-automatica §7.3). The server releases a worker's
/// points after `releaseMinutes` without a sign of life; this warns them at
/// `warningMinutes` — an in-app banner while the app is open, a scheduled
/// local notification while it is not (the OS fires it with the app
/// suspended). Activity is what the server counts too: a position sent, a
/// check-in, a check-out.
///
///     final watchdog = SilenceWatchdog(
///       clock: DateTime.now,
///       scheduler: scheduler,
///       warningMinutes: day.silenceWarningMinutes,
///       releaseMinutes: day.silenceReleaseMinutes,
///     )..startWatching();
///     watchdog.onActivity(sentAt);
///     final warning = watchdog.currentWarning();
class SilenceWatchdog {
  SilenceWatchdog({
    required Clock clock,
    required LocalScheduler scheduler,
    required int warningMinutes,
    required int releaseMinutes,
  }) : _clock = clock,
       _scheduler = scheduler,
       _warning = Duration(minutes: warningMinutes),
       _releaseMinutes = releaseMinutes;

  /// Fixed: there is only ever one silence warning pending.
  static const int notificationId = 4712;

  /// When the app is paused already past the warning, the notification
  /// still waits this long (a schedule in the past is refused).
  static const Duration _overdueDelay = Duration(minutes: 1);

  final Clock _clock;
  final LocalScheduler _scheduler;
  final Duration _warning;
  final int _releaseMinutes;

  /// Null while no route is `IN_PROGRESS`: nothing to warn about.
  DateTime? _lastActivity;
  bool _paused = false;
  bool _scheduled = false;

  /// A route went `IN_PROGRESS`: the silence clock starts now. A no-op while
  /// already watching, so a rebuild never resets it.
  void startWatching() {
    _lastActivity ??= _clock();
  }

  /// The route left `IN_PROGRESS`: no banner, no pending notification.
  void stopWatching() {
    _lastActivity = null;
    _cancelScheduled();
  }

  /// A sign of life at [at] (defaults to now). While paused — the background
  /// service sending with the screen locked — the pending notification moves
  /// to the new deadline instead of firing at the old one.
  void onActivity([DateTime? at]) {
    if (_lastActivity == null) return;
    _lastActivity = at ?? _clock();
    if (_paused) _schedule();
  }

  void onAppPaused() {
    _paused = true;
    if (_lastActivity != null) _schedule();
  }

  void onAppResumed() {
    _paused = false;
    _cancelScheduled();
  }

  /// The banner to show now, or null when the worker is not (yet) silent.
  SilenceWarning? currentWarning() {
    final last = _lastActivity;
    if (last == null) return null;
    final silent = _clock().difference(last);
    if (silent < _warning) return null;
    return _warningAfter(silent);
  }

  SilenceWarning _warningAfter(Duration silent) {
    final minutes = silent.inMinutes;
    return (
      silentMinutes: minutes,
      minutesUntilRelease: math.max(0, _releaseMinutes - minutes),
    );
  }

  void _schedule() {
    final last = _lastActivity!;
    final now = _clock();
    final due = last.add(_warning);
    final at = due.isAfter(now) ? due : now.add(_overdueDelay);
    final warning = _warningAfter(at.difference(last));
    _scheduled = true;
    unawaited(
      _scheduler.schedule(
        id: notificationId,
        at: at,
        title: AppStrings.silenceNotificationTitle,
        body: AppStrings.silenceWarning(
          warning.silentMinutes,
          warning.minutesUntilRelease,
        ),
      ),
    );
  }

  void _cancelScheduled() {
    if (!_scheduled) return;
    _scheduled = false;
    unawaited(_scheduler.cancel(notificationId));
  }
}
