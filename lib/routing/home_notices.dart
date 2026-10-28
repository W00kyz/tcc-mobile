import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/ui/snackbar_lane.dart';

/// Holds the map home's [SnackbarLane] while the home is mounted, so the
/// stop flows (`stop_actions.dart`) and the sheet's panels reach it without
/// a widget of their own. The home attaches it in `initState` and detaches
/// it in `dispose`: the lane never outlives its screen.
///
///     ref.read(homeSnackbarLaneProvider).attach(lane);
final homeSnackbarLaneProvider = Provider<HomeSnackbarLaneSlot>(
  (ref) => HomeSnackbarLaneSlot(),
);

class HomeSnackbarLaneSlot {
  SnackbarLane? _lane;

  /// The mounted home's lane, or null with no home on screen.
  SnackbarLane? get lane => _lane;

  // A method, not a setter: it pairs with [detach] at the call sites.
  // ignore: use_setters_to_change_properties
  void attach(SnackbarLane lane) => _lane = lane;

  /// Only the lane that is attached goes: a newer home keeps its own.
  void detach(SnackbarLane lane) {
    if (identical(_lane, lane)) _lane = null;
  }
}

/// Where the confirmation of a map-home action goes, decided now — call it
/// before any `await`, while [context] is mounted. Through the home's lane
/// it floats above the sheet and never covers "Escanear QR" (spec §5,
/// §6.7); with no home mounted, on the plain messenger.
///
///     final notify = homeNotifier(ref, context);
///     await write();
///     notify(AppStrings.routeCheckInDone);
void Function(String) homeNotifier(WidgetRef ref, BuildContext context) {
  final lane = ref.read(homeSnackbarLaneProvider).lane;
  final messenger = ScaffoldMessenger.maybeOf(context);
  return (text) {
    if (lane != null) return lane.show(SnackKind.action, text);
    messenger?.showSnackBar(SnackBar(content: Text(text)));
  };
}
