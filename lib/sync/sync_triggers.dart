import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/sync/sync_providers.dart';

/// App-wide observer that drains the outbox on the two automatic triggers of
/// spec Ruling 11 that no single screen owns: the app returning to the
/// foreground (`AppLifecycleState.resumed`) and connectivity being regained
/// (`Connectivity.onOnlineChanged`). The post-enqueue kick (Task 8) and the
/// manual "Sincronizar agora" button (Task 11) cover the other two.
///
/// Mounted once, wrapping every route via `MaterialApp.router`'s `builder`:
///
///     MaterialApp.router(
///       builder: (context, child) =>
///           SyncTriggers(child: child ?? const SizedBox.shrink()),
///     )
class SyncTriggers extends ConsumerStatefulWidget {
  const SyncTriggers({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SyncTriggers> createState() => _SyncTriggersState();
}

class _SyncTriggersState extends ConsumerState<SyncTriggers>
    with WidgetsBindingObserver {
  // A raw subscription rather than a `StreamProvider` + `ref.listenManual`:
  // the regained-connectivity edge only needs to call `syncAll()`, so a
  // `StreamProvider` would add a provider to cache a value nothing reads.
  StreamSubscription<bool>? _onlineRegained;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _onlineRegained = ref
        .read(connectivityProvider)
        .onOnlineChanged
        .listen((_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_onlineRegained?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  /// Fire-and-forget: a trigger asks the worker to drain, it does not wait for
  /// the pass. `SyncWorker` already guards against overlapping drains.
  void _sync() {
    unawaited(ref.read(syncWorkerProvider).syncAll());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
