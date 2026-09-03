import 'dart:async';

import 'package:route_monitor/sync/connectivity.dart';

/// Controllable [Connectivity] double for tests: set [isOnlineValue] to steer
/// [isOnline], and call [goOnline]/[goOffline] to drive the transition stream
/// the same way the real plugin would after a `distinct()` + regained filter.
class FakeConnectivity implements Connectivity {
  FakeConnectivity({bool isOnline = false}) : isOnlineValue = isOnline;

  bool isOnlineValue;

  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  @override
  Future<bool> get isOnline async => isOnlineValue;

  @override
  Stream<bool> get onOnlineChanged => _controller.stream;

  /// Simulate connectivity being regained.
  void goOnline() {
    isOnlineValue = true;
    _controller.add(true);
  }

  /// Simulate connectivity being lost. Emits nothing — [onOnlineChanged] only
  /// reports the regained edge.
  void goOffline() {
    isOnlineValue = false;
  }

  Future<void> dispose() => _controller.close();
}
