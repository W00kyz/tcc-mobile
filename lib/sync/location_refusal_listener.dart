import 'dart:async';

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
/// why. A refusal comes from the running worker's callback, from
/// `SyncTriggers` finding one the background drain applied while the app was
/// away, or from a look at SQLite as the home mounts; each is told once (kept
/// in memory for this run, acknowledged in SQLite for the next).
///
///     Scaffold(body: LocationRefusalListener(lane: lane, child: body))
class LocationRefusalListener extends ConsumerStatefulWidget {
  const LocationRefusalListener({
    required this.lane,
    required this.child,
    super.key,
  });

  /// The home's snackbar line.
  final SnackbarLane lane;
  final Widget child;

  @override
  ConsumerState<LocationRefusalListener> createState() =>
      _LocationRefusalListenerState();
}

class _LocationRefusalListenerState
    extends ConsumerState<LocationRefusalListener> {
  /// The refusals already told in this run: the announcement and the resume
  /// check may name the same one before its acknowledgement is written.
  final Set<String> _told = {};

  @override
  void initState() {
    super.initState();
    // The home mounts after the app started: refusals the background drain
    // applied before that were announced to nobody.
    WidgetsBinding.instance.addPostFrameCallback((_) => _tellMissed());
  }

  Future<void> _tellMissed() async {
    final missed = await ref.read(refusalNoticesProvider).unannounced();
    if (mounted) missed.forEach(_tell);
  }

  void _tell(LocationRefusal refusal) {
    if (!_told.add(refusal.operationId)) return;
    ref
      ..invalidate(stopProgressForProvider(refusal.routeStopId))
      ..invalidate(stopSyncChipProvider);
    widget.lane.show(SnackKind.action, refusal.message);
    unawaited(
      ref.read(refusalNoticesProvider).acknowledge(refusal.operationId),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<LocationRefusal?>(locationRefusalAnnouncementsProvider, (
      _,
      refusal,
    ) {
      if (refusal != null) _tell(refusal);
    });
    return widget.child;
  }
}
