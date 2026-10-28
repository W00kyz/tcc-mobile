import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Payload of the "needs attention" sync notification: this prefix plus the
/// route whose rows are blocked (redesign §6.9 — the tap opens
/// `BlockedSyncScreen`).
const String blockedSyncPayloadPrefix = 'blocked-sync:';

/// The route a notification [payload] asks `BlockedSyncScreen` for, or null
/// when it is not a "needs attention" payload.
///
///     blockedSyncRouteOf('blocked-sync:r1'); // 'r1'
String? blockedSyncRouteOf(String? payload) {
  if (payload == null || !payload.startsWith(blockedSyncPayloadPrefix)) {
    return null;
  }
  final routeId = payload.substring(blockedSyncPayloadPrefix.length);
  return routeId.isEmpty ? null : routeId;
}

/// Taps on this app's notifications while it runs, as the route ids of
/// tapped "needs attention" notifications.
class NotificationTapRelay {
  final StreamController<String> _blockedRoutes =
      StreamController<String>.broadcast();

  Stream<String> get blockedSyncTaps => _blockedRoutes.stream;

  void onResponse(NotificationResponse response) {
    final routeId = blockedSyncRouteOf(response.payload);
    if (routeId != null) _blockedRoutes.add(routeId);
  }
}

/// INTENTIONAL: process-wide. The plugin keeps ONE tap callback — whatever
/// the last `initialize` passed — so every caller must pass this same relay,
/// or a later `initialize` (the collection notice, the silence warning)
/// would silently drop taps.
final NotificationTapRelay appNotificationTaps = NotificationTapRelay();

/// The one `initialize` every notification seam in the app goes through, so
/// a tap is always routed to [appNotificationTaps].
///
///     await initializeNotificationPlugin(plugin);
Future<void> initializeNotificationPlugin(
  FlutterLocalNotificationsPlugin plugin,
) async {
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: appNotificationTaps.onResponse,
  );
}
