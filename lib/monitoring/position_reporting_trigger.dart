import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/auth/auth_providers.dart' show sessionProvider;
import 'package:route_monitor/monitoring/monitoring_providers.dart';
import 'package:route_monitor/routing/route_providers.dart' show myDayProvider;

/// Keeps the GPS position reporter (spec §2 Ruling 5, §6) and the silence
/// watchdog (spec 2026-10-20-alocacao-automatica §7.3) in step with the day:
/// while today's route is `IN_PROGRESS` the reporter runs for it — in the
/// mode the permissions allow, on the server's interval — and the watchdog
/// watches its silence; otherwise both stop.
///
/// IMPORTANT: a provider, not a widget build. Riverpod re-runs it whenever
/// the session, the day, the mode, the reporter or the watchdog change, with
/// or without frames — and with the screen locked there are none, while
/// token refreshes and day reloads keep happening.
///
///     container.listen(positionReportingProvider, (_, _) {});
final positionReportingProvider = Provider<void>((ref) {
  // RNF10: GPS collection must not run above the consent gate. A session that
  // still owes acceptance of the current privacy notice keeps the reporter
  // stopped regardless of route state. Only these two facts are watched: a
  // token refresh must not even re-run this.
  final consentRequired = ref.watch(
    sessionProvider.select((session) => session?.consentRequired),
  );
  // Logged out: nothing is reporting and `positionReporterProvider` reads
  // `API_BASE_URL` (unset on the login screen), so don't even build it.
  if (consentRequired == null) return;
  if (consentRequired) return _stopReporting(ref);

  // `.value` keeps the last known day while a reload is in flight or after
  // it failed (offline): a reload must never stop the reporter.
  final day = ref.watch(myDayProvider).value;
  // No day yet (initial load, or an error while logged out): nothing to
  // report and nothing to stop, so don't even build
  // `positionReporterProvider`.
  if (day == null) return;

  final route = day.route;
  if (route == null || route.status != 'IN_PROGRESS') {
    return _stopReporting(ref);
  }
  // Still reading the permissions for the first time: wait for the mode.
  final mode = ref.watch(locationModeProvider).value;
  if (mode == null) return;
  // Watched, so a rebuilt reporter or watchdog (another user, new limits) is
  // started again right here.
  ref
      .watch(positionReporterProvider)
      .start(
        route.id,
        mode: mode,
        interval: Duration(seconds: day.positionIntervalSeconds),
      );
  ref.watch(silenceWatchdogProvider)?.startWatching();
});

void _stopReporting(Ref ref) {
  ref.read(positionReporterProvider).stop();
  ref.read(silenceWatchdogProvider)?.stopWatching();
}

/// App-wide mount point that keeps [positionReportingProvider] alive and
/// relays the app going to and coming back from the background to the
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
    ref.watch(positionReportingProvider);
    return widget.child;
  }
}
