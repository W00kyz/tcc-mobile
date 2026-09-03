import 'package:connectivity_plus/connectivity_plus.dart' as cplus;

/// Thin seam over the `connectivity_plus` plugin so the sync worker can react
/// to the device coming back online without touching the platform channel in
/// tests (CLAUDE.md — Dependencies: "wrap third-party libs behind a thin
/// interface").
abstract class Connectivity {
  /// Whether the device currently has a usable network interface.
  Future<bool> get isOnline;

  /// Emits `true` each time connectivity is *regained* — an offline→online
  /// transition. It never emits `false` and never fires on an online→online
  /// change such as wifi→mobile.
  Stream<bool> get onOnlineChanged;
}

/// Maps a `connectivity_plus` result list to a single online flag: online when
/// any interface in the list is something other than
/// [cplus.ConnectivityResult.none].
bool _isOnline(List<cplus.ConnectivityResult> results) => results.any(
  (result) => result != cplus.ConnectivityResult.none,
);

/// [Connectivity] backed by the real `connectivity_plus` plugin.
class ConnectivityPlusConnectivity implements Connectivity {
  ConnectivityPlusConnectivity({cplus.Connectivity? plugin})
    : _plugin = plugin ?? cplus.Connectivity();

  final cplus.Connectivity _plugin;

  @override
  Future<bool> get isOnline async =>
      _isOnline(await _plugin.checkConnectivity());

  @override
  Stream<bool> get onOnlineChanged => _plugin.onConnectivityChanged
      .map(_isOnline)
      .distinct()
      .where((online) => online);
}
