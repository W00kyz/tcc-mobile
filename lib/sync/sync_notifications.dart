import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/monitoring/notification_plugin.dart';

/// The OS notifications of the background drain (redesign §6.9), behind a
/// project seam so the drain and its tests never reach the vendor plugin.
///
///     await notifications.progress(3, 5); // "Enviando registros · 3 de 5"
///     await notifications.finished(5);    // "Registros enviados · 5 …"
abstract class SyncNotificationPublisher {
  Future<void> progress(int done, int total);
  Future<void> finished(int sent);
  Future<void> needsAttention(int blocked);
  Future<void> clear();
}

/// A publisher that posts nothing — what the drain talks to while the app is
/// in the foreground, where the snackbars already report the sync.
class SilentSyncNotifications implements SyncNotificationPublisher {
  const SilentSyncNotifications();

  @override
  Future<void> progress(int done, int total) async {}

  @override
  Future<void> finished(int sent) async {}

  @override
  Future<void> needsAttention(int blocked) async {}

  @override
  Future<void> clear() async {}
}

/// [SyncNotificationPublisher] over `flutter_local_notifications`. Progress
/// and result share one low-importance, silent channel ("Envio de
/// registros"); "needs attention" has its own default-importance channel —
/// on Android 8+ importance belongs to the channel, not the notification —
/// and its tap opens `BlockedSyncScreen` for the `blockedRouteId` route.
/// Like `LocalOngoingNotification`, a missing platform channel is swallowed.
class LocalSyncNotifications implements SyncNotificationPublisher {
  LocalSyncNotifications({
    required this._blockedRouteId,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final Future<String?> Function() _blockedRouteId;
  final FlutterLocalNotificationsPlugin _plugin;

  static const int _uploadId = 4721;
  static const int _attentionId = 4722;
  static const String _uploadChannelId = 'sync_uploads';
  static const String _attentionChannelId = 'sync_attention';

  /// "Registros enviados" goes away on its own after a few seconds.
  static const Duration _finishedLingers = Duration(seconds: 5);

  bool _initialized = false;

  @override
  Future<void> progress(int done, int total) => _guarded(
    () => _plugin.show(
      id: _uploadId,
      title: AppStrings.syncNotificationProgress(done, total),
      notificationDetails: _uploadDetails(
        showProgress: true,
        maxProgress: total,
        progress: done,
      ),
    ),
  );

  @override
  Future<void> finished(int sent) => _guarded(
    () => _plugin.show(
      id: _uploadId,
      title: AppStrings.syncNotificationFinished(sent),
      notificationDetails: _uploadDetails(timeoutAfter: _finishedLingers),
    ),
  );

  @override
  Future<void> needsAttention(int blocked) => _guarded(() async {
    await _plugin.cancel(id: _uploadId);
    final routeId = await _blockedRouteId();
    await _plugin.show(
      id: _attentionId,
      title: AppStrings.syncNotificationAttention(blocked),
      notificationDetails: _attentionDetails,
      payload: routeId == null ? null : '$blockedSyncPayloadPrefix$routeId',
    );
  });

  @override
  Future<void> clear() => _guarded(() => _plugin.cancel(id: _uploadId));

  NotificationDetails _uploadDetails({
    bool showProgress = false,
    int maxProgress = 0,
    int progress = 0,
    Duration? timeoutAfter,
  }) => NotificationDetails(
    android: AndroidNotificationDetails(
      _uploadChannelId,
      AppStrings.syncNotificationChannelName,
      channelDescription: AppStrings.syncNotificationChannelDescription,
      importance: Importance.low,
      priority: Priority.low,
      playSound: false,
      onlyAlertOnce: true,
      showProgress: showProgress,
      maxProgress: maxProgress,
      progress: progress,
      timeoutAfter: timeoutAfter?.inMilliseconds,
    ),
  );

  static const NotificationDetails _attentionDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _attentionChannelId,
      AppStrings.syncAttentionChannelName,
      channelDescription: AppStrings.syncAttentionChannelDescription,
    ),
  );

  /// Best-effort: a notification must never fail the drain itself.
  Future<void> _guarded(Future<void> Function() post) async {
    try {
      await _ensureInit();
      await post();
    } on MissingPluginException {
      // No platform channel (a unit test): degrade quietly.
    } on PlatformException {
      // The plugin failed natively: same rationale.
    }
  }

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await initializeNotificationPlugin(_plugin);
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(_uploadChannel);
    await android?.createNotificationChannel(_attentionChannel);
    _initialized = true;
  }

  static const AndroidNotificationChannel _uploadChannel =
      AndroidNotificationChannel(
        _uploadChannelId,
        AppStrings.syncNotificationChannelName,
        description: AppStrings.syncNotificationChannelDescription,
        importance: Importance.low,
        playSound: false,
      );

  static const AndroidNotificationChannel _attentionChannel =
      AndroidNotificationChannel(
        _attentionChannelId,
        AppStrings.syncAttentionChannelName,
        description: AppStrings.syncAttentionChannelDescription,
      );
}

/// Where the app hears taps on the "needs attention" notification, as the
/// route whose blocked rows to show.
///
///     taps.blockedSyncTaps.listen((routeId) => openBlocked(routeId));
abstract class SyncNotificationTaps {
  /// Taps while the app runs (foreground or background).
  Stream<String> get blockedSyncTaps;

  /// The route of the tap that launched the app from a cold start, once;
  /// null on every later call or when the launch was not such a tap.
  Future<String?> takeLaunchTap();
}

/// [SyncNotificationTaps] over the plugin. [takeLaunchTap] also initializes
/// the plugin on the app's isolate, so taps reach [appNotificationTaps] even
/// before any other notification was posted this session.
class PluginSyncNotificationTaps implements SyncNotificationTaps {
  PluginSyncNotificationTaps({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _launchTaken = false;

  @override
  Stream<String> get blockedSyncTaps => appNotificationTaps.blockedSyncTaps;

  @override
  Future<String?> takeLaunchTap() async {
    if (_launchTaken) return null;
    _launchTaken = true;
    try {
      await initializeNotificationPlugin(_plugin);
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp != true) return null;
      return blockedSyncRouteOf(launch?.notificationResponse?.payload);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

/// The app's notification taps; tests override it with a fake.
final syncNotificationTapsProvider = Provider<SyncNotificationTaps>(
  (ref) => PluginSyncNotificationTaps(),
);
