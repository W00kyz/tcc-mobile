import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/monitoring/silence_watchdog.dart';
import 'package:timezone/timezone.dart' as tz;

/// [LocalScheduler] over `flutter_local_notifications` — the silence warning
/// (spec 2026-10-20-alocacao-automatica §7.3). Inexact on purpose
/// (`inexactAllowWhileIdle`): a warning a few minutes late is fine, and it
/// spares the `SCHEDULE_EXACT_ALARM` permission. Times go out in UTC, so no
/// time-zone database has to be loaded. Like `LocalOngoingNotification`, the
/// channel is created on first use and a missing platform channel (a unit
/// test) is swallowed.
class LocalNotificationScheduler implements LocalScheduler {
  LocalNotificationScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const String _channelId = 'location_silence';
  static const String _channelName = AppStrings.silenceNotificationChannelName;
  static const String _channelDescription =
      AppStrings.silenceNotificationChannelDescription;

  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
          ),
        );
    _initialized = true;
  }

  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    try {
      await _ensureInit();
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(at, tz.UTC),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } on MissingPluginException {
      // No platform channel: the warning is best-effort, never a hard
      // dependency of the route.
    } on PlatformException {
      // The plugin failed natively (channel, alarm manager): same rationale.
      // A best-effort warning must never crash the watchdog's unawaited call.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      // A date the plugin judged past despite the watchdog's margin.
    }
  }

  @override
  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } on MissingPluginException {
      // Same rationale as schedule().
    } on PlatformException {
      // Same rationale as schedule().
    }
  }
}
