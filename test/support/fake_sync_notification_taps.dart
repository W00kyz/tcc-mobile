import 'dart:async';

import 'package:route_monitor/sync/sync_notifications.dart';

/// Controllable [SyncNotificationTaps]: [tap] plays a tap on the "needs
/// attention" notification; [launchRoute] is the cold-start tap, if any.
class FakeSyncNotificationTaps implements SyncNotificationTaps {
  FakeSyncNotificationTaps({this.launchRoute});

  String? launchRoute;
  final StreamController<String> _taps = StreamController<String>.broadcast();

  void tap(String routeId) => _taps.add(routeId);

  @override
  Stream<String> get blockedSyncTaps => _taps.stream;

  @override
  Future<String?> takeLaunchTap() async {
    final route = launchRoute;
    launchRoute = null;
    return route;
  }
}
