import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/monitoring/notification_plugin.dart';

/// The persistent "location collection is active" OS notification shown while
/// a route is `IN_PROGRESS` (LGPD transparency, RNF11). A thin seam over
/// `flutter_local_notifications` so `PositionReporter` and its tests depend on
/// this project's interface, never the vendor plugin (docs/CLAUDE.md —
/// Dependencies).
///
///     final notification = LocalOngoingNotification();
///     await notification.show(); // route started
///     await notification.hide(); // route done / checked out
abstract class OngoingNotification {
  Future<void> show();
  Future<void> hide();
}

/// Real implementation. Posts one ongoing, low-importance, silent notification
/// that the field worker cannot swipe away while the route runs (`ongoing`,
/// `autoCancel: false`). The Android channel is created lazily on the first
/// `show()` so `flutter test` — which never constructs this class — never
/// touches the platform channel; a `MissingPluginException` (e.g. a unit test
/// that does build it) is swallowed so it degrades quietly rather than crashing
/// the collection loop.
class LocalOngoingNotification implements OngoingNotification {
  LocalOngoingNotification({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const int _notificationId = 4711;
  static const String _channelId = 'collection_ongoing';
  // User-facing copy (shown in Android notification settings) lives in
  // AppStrings (RNF02).
  static const String _channelName =
      AppStrings.collectionNotificationChannelName;
  static const String _channelDescription =
      AppStrings.collectionNotificationChannelDescription;

  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    // The shared init: a tap callback of its own would replace the app's.
    await initializeNotificationPlugin(_plugin);
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.low,
            playSound: false,
          ),
        );
    _initialized = true;
  }

  @override
  Future<void> show() async {
    try {
      await _ensureInit();
      await _plugin.show(
        id: _notificationId,
        title: AppStrings.collectionNotificationTitle,
        body: AppStrings.collectionNotificationBody,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            playSound: false,
            onlyAlertOnce: true,
          ),
        ),
      );
    } on MissingPluginException {
      // No platform channel (a unit test that still constructs this class):
      // the notification is best-effort transparency, never a hard dependency
      // of the collection loop.
    }
  }

  @override
  Future<void> hide() async {
    try {
      await _plugin.cancel(id: _notificationId);
    } on MissingPluginException {
      // Same rationale as show(): degrade quietly when off-device.
    }
  }
}
