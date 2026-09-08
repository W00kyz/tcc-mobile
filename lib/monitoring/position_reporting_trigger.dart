import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/auth/auth_providers.dart' show sessionProvider;
import 'package:route_monitor/monitoring/monitoring_providers.dart';
import 'package:route_monitor/routing/route_providers.dart'
    show myRoutesProvider;

/// App-wide mount point for the GPS position reporter (spec §2 Ruling 5, §6).
/// Watches `myRoutesProvider`; while it holds a route whose `status` is
/// `IN_PROGRESS` the reporter is started for that route, otherwise it is
/// stopped. Mounted once next to `SyncTriggers` in `main.dart`.
///
///     SyncTriggers(child: PositionReportingTrigger(child: ...))
class PositionReportingTrigger extends ConsumerWidget {
  const PositionReportingTrigger({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // RNF10: GPS collection must not run above the consent gate. A session that
    // still owes acceptance of the current privacy notice keeps the reporter
    // stopped regardless of route state.
    final session = ref.watch(sessionProvider);
    // Logged out: nothing is reporting and `positionReporterProvider` reads
    // `API_BASE_URL` (unset on the login screen), so don't even build it.
    if (session == null) return child;
    if (session.consentRequired) {
      ref.read(positionReporterProvider).stop();
      return child;
    }

    // `ref.watch` re-runs this build on the first load and on every later
    // refetch (resume/reconnect invalidates `myRoutesProvider`); the last
    // known list is kept while a refetch is in flight (`asData`).
    final routes = ref.watch(myRoutesProvider).asData?.value;
    // No successful route list yet (initial load, or an error while logged
    // out — `myRoutesProvider` has no cache-on-error): nothing to report and
    // nothing to stop, so don't even build `positionReporterProvider` (it
    // reads `API_BASE_URL`, unset on the login screen).
    if (routes == null) return child;

    final reporter = ref.read(positionReporterProvider);
    for (final route in routes) {
      if (route.status == 'IN_PROGRESS') {
        reporter.start(route.id);
        return child;
      }
    }
    reporter.stop();
    return child;
  }
}
