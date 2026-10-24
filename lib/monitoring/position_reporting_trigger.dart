import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/auth/auth_providers.dart' show sessionProvider;
import 'package:route_monitor/monitoring/monitoring_providers.dart';
import 'package:route_monitor/routing/route_providers.dart' show myDayProvider;

/// App-wide mount point for the GPS position reporter (spec §2 Ruling 5, §6)
/// and the silence watchdog (spec 2026-10-20-alocacao-automatica §7.3).
/// Watches `myDayProvider`; while today's route is `IN_PROGRESS` the reporter
/// runs for that route — in the mode the permissions allow, on the server's
/// interval — and the watchdog watches its silence; otherwise both stop. The
/// app going to and coming back from the background is relayed to the
/// watchdog. Mounted once next to `SyncTriggers` in `main.dart`.
///
///     SyncTriggers(child: PositionReportingTrigger(child: ...))
class PositionReportingTrigger extends ConsumerStatefulWidget {
  const PositionReportingTrigger({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PositionReportingTrigger> createState() =>
      _PositionReportingTriggerState();
}

class _PositionReportingTriggerState
    extends ConsumerState<PositionReportingTrigger>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (ref.read(sessionProvider) == null) return;
    final watchdog = ref.read(silenceWatchdogProvider);
    if (state == AppLifecycleState.paused) watchdog?.onAppPaused();
    if (state != AppLifecycleState.resumed) return;
    watchdog?.onAppResumed();
    // "Always" may have been granted or revoked in the system settings.
    ref.invalidate(locationModeProvider);
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    // RNF10: GPS collection must not run above the consent gate. A session that
    // still owes acceptance of the current privacy notice keeps the reporter
    // stopped regardless of route state.
    final session = ref.watch(sessionProvider);
    // Logged out: nothing is reporting and `positionReporterProvider` reads
    // `API_BASE_URL` (unset on the login screen), so don't even build it.
    if (session == null) return child;
    if (session.consentRequired) {
      _stop();
      return child;
    }

    // `ref.watch` re-runs this build on the first load and on every later
    // refetch (resume/reconnect invalidates `myDayProvider`); the last
    // known day is kept while a refetch is in flight (`asData`).
    final day = ref.watch(myDayProvider).asData?.value;
    // No successful day yet (initial load, or an error while logged out):
    // nothing to report and nothing to stop, so don't even build
    // `positionReporterProvider` (it reads `API_BASE_URL`, unset on the login
    // screen).
    if (day == null) return child;

    final route = day.route;
    if (route == null || route.status != 'IN_PROGRESS') {
      _stop();
      return child;
    }
    // Still reading the permissions (first build, or a resume): the reporter
    // keeps running as it was until the mode is known.
    final mode = ref.watch(locationModeProvider).asData?.value;
    if (mode == null) return child;
    ref
        .read(positionReporterProvider)
        .start(
          route.id,
          mode: mode,
          interval: Duration(seconds: day.positionIntervalSeconds),
        );
    ref.watch(silenceWatchdogProvider)?.startWatching();
    return child;
  }

  void _stop() {
    ref.read(positionReporterProvider).stop();
    ref.read(silenceWatchdogProvider)?.stopWatching();
  }
}
