import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/execution/execution_providers.dart'
    show stopProgressForProvider;
import 'package:route_monitor/sync/location_refusal.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/ui/snackbar_lane.dart';

/// Tells the worker when the server refused a location completion (spec
/// 2026-10-30-locais-externos §6): "Conclusão recusada em {place}: você
/// estava a {n} m do local." The sync worker has already put the stop back
/// to pending in SQLite; this redraws it (its card, its sync chip) and says
/// why.
///
///     Scaffold(body: LocationRefusalListener(lane: lane, child: body))
class LocationRefusalListener extends ConsumerWidget {
  const LocationRefusalListener({
    required this.lane,
    required this.child,
    super.key,
  });

  /// The home's snackbar line.
  final SnackbarLane lane;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<LocationRefusal?>(locationRefusalAnnouncementsProvider, (
      _,
      refusal,
    ) {
      if (refusal == null) return;
      ref
        ..invalidate(stopProgressForProvider(refusal.routeStopId))
        ..invalidate(stopSyncChipProvider);
      lane.show(SnackKind.action, refusal.message);
    });
    return child;
  }
}
