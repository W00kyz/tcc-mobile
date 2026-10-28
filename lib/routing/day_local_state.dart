import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/sync_providers.dart';

// What this device adds to the server's view of the day, watched by the map
// home so a local write redraws the pins and the floor card at once.

/// What this device knows about each stop of [route], from its local
/// progress rows (watched, so a check-in/out redraws the card).
///
///     final local = watchLocalStates(ref, route);
Map<String, LocalStopState> watchLocalStates(
  WidgetRef ref,
  RouteSummary route,
) => {
  for (final stop in route.stops)
    if (ref.watch(stopProgressForProvider(stop.id)).asData?.value
        case final entry?)
      stop.id: LocalStopState.fromEntry(entry),
};

/// The route's stops with an outbox row not yet delivered — every batch's,
/// since the day's pins show them all (a batch just finished may still be
/// uploading).
///
///     final pending = watchPendingSyncStops(ref, route);
Set<String> watchPendingSyncStops(WidgetRef ref, RouteSummary route) => {
  for (final stop in route.stops)
    if ((ref.watch(stopSyncChipProvider((route.id, stop.id))).asData?.value ??
            StopSyncChip.none) !=
        StopSyncChip.none)
      stop.id,
};
