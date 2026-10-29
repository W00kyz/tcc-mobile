// The tracker's constructor forwards public named params to private fields,
// so tests inject fakes by a public name (same idiom as position_reporter).
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show NotifierProviderFamily;
import 'package:latlong2/latlong.dart';
import 'package:route_monitor/auth/auth_providers.dart' show buildSessionDio;
import 'package:route_monitor/execution/room_resolution.dart'
    show haversineMeters;
import 'package:route_monitor/routing/approach_api.dart';
import 'package:route_monitor/routing/building_card_model.dart';
import 'package:route_monitor/routing/route_repository.dart';

/// The worker's last known position: the "Minha posição" read and every fix
/// the position reporter takes while the route is in progress. Null until
/// the first one — and then the map draws exactly as it did without it.
///
///     ref.read(workerPositionProvider.notifier).update(LatLng(-7.21, -35.9));
final workerPositionProvider = NotifierProvider<WorkerPosition, LatLng?>(
  WorkerPosition.new,
);

class WorkerPosition extends Notifier<LatLng?> {
  @override
  LatLng? build() => null;

  // A method, not a setter: reads as the action it is at the call site.
  // ignore: use_setters_to_change_properties
  void update(LatLng position) => state = position;
}

/// The stop the live first leg walks to: the card's "Próxima parada" (the
/// first PENDING stop of the batch, in route order — never reordered here).
/// A provider family key, so compared by value.
@immutable
class ApproachTarget {
  const ApproachTarget({required this.stopId, required this.position});

  final String stopId;

  /// The stop's own coordinates: where a straight fallback line ends.
  final LatLng position;

  @override
  bool operator ==(Object other) =>
      other is ApproachTarget &&
      other.stopId == stopId &&
      other.position == position;

  @override
  int get hashCode => Object.hash(stopId, position);
}

/// What the map draws from the worker to the next stop: the street path, or
/// a straight hop flagged [approximate] (drawn dashed) when offline or when
/// the server could not route it.
class LiveApproach {
  const LiveApproach({required this.points, required this.approximate});

  /// Worker first, in `LatLng(lat, lng)` order.
  final List<LatLng> points;
  final bool approximate;
}

/// Decides when to ask the server for the live first leg, and what to draw
/// meanwhile. Pure Dart over an injected [ApproachApi] and clock, so the
/// throttling is testable without a widget or a timer.
///
/// A fetch is due on the first position, then only when the worker moved
/// more than [minMoveM] since the last fetch and at least [minInterval] has
/// passed. A new next stop means a new tracker (one per [ApproachTarget]).
///
///     final tracker = ApproachTracker(api: api, target: target);
///     final now = tracker.current(here); // draw this right away
///     if (tracker.isDue(here)) draw(await tracker.fetch(here));
class ApproachTracker {
  ApproachTracker({
    required ApproachApi api,
    required this.target,
    DateTime Function() now = DateTime.now,
  }) : _api = api,
       _now = now;

  static const double minMoveM = 25;
  static const Duration minInterval = Duration(seconds: 15);

  final ApproachApi _api;
  final DateTime Function() _now;
  final ApproachTarget target;

  LiveApproach? _lastGood;
  LatLng? _fetchedFrom;
  DateTime? _fetchedAt;
  bool _inFlight = false;

  /// The last street path if any, else a straight hop from [position].
  LiveApproach current(LatLng position) => _lastGood ?? _straightFrom(position);

  bool isDue(LatLng position) {
    final from = _fetchedFrom;
    final at = _fetchedAt;
    if (_inFlight) return false;
    if (from == null || at == null) return true;
    if (_now().difference(at) < minInterval) return false;
    return _metersBetween(from, position) > minMoveM;
  }

  /// Asks the server from [position]. A street path that ends at [target]
  /// becomes the last good one; anything else — offline, 503, 204, or the
  /// server's next stop not yet the app's (an unsynced check-out) — keeps
  /// the last good path, or falls back to a straight hop.
  Future<LiveApproach> fetch(LatLng position) async {
    _inFlight = true;
    _fetchedFrom = position;
    _fetchedAt = _now();
    final leg = await _tryFetch(position);
    _inFlight = false;
    if (leg == null || !_reachesTarget(leg)) return current(position);
    return _lastGood = LiveApproach(points: leg.points, approximate: false);
  }

  Future<ApproachLeg?> _tryFetch(LatLng position) async {
    try {
      return await _api.fetchApproach(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } on Object {
      // Deliberately broad: any failure means "no street path now", drawn
      // as a dashed line — never a crash on the map.
      return null;
    }
  }

  bool _reachesTarget(ApproachLeg leg) =>
      leg.routeStopId == target.stopId && leg.points.length >= 2;

  LiveApproach _straightFrom(LatLng position) =>
      LiveApproach(points: [position, target.position], approximate: true);
}

double _metersBetween(LatLng a, LatLng b) =>
    haversineMeters(a.latitude, a.longitude, b.latitude, b.longitude);

/// The live first leg to the day's next task, for a widget that draws it:
/// null without a worker position (the map draws as it always did) or
/// without a next task. The next task is the day model's — it knows the
/// local stamps and impediments the server has not heard of yet.
///
///     final approach = watchLiveApproach(ref, route, buildings);
LiveApproach? watchLiveApproach(
  WidgetRef ref,
  RouteSummary route,
  List<DayBuilding> buildings,
) {
  final position = ref.watch(workerPositionProvider);
  final nextId = nextTaskStopId(buildings);
  if (position == null || nextId == null) return null;
  final stop = route.stops.firstWhere((s) => s.id == nextId);
  final target = ApproachTarget(
    stopId: stop.id,
    position: LatLng(stop.latitude, stop.longitude),
  );
  return ref.watch(liveApproachProvider(target));
}

final approachApiProvider = Provider<ApproachApi>(
  (ref) => DioApproachApi(buildSessionDio(ref)),
);

/// Test seam for the tracker's clock.
final approachClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// The live first leg to [ApproachTarget]: null while there is no worker
/// position; otherwise what [ApproachTracker] says to draw, refreshed as the
/// position moves. Auto-disposed, so the next stop changing starts over with
/// a fresh fetch.
///
///     final approach = ref.watch(liveApproachProvider(target));
final NotifierProviderFamily<
  LiveApproachNotifier,
  LiveApproach?,
  ApproachTarget
>
liveApproachProvider = NotifierProvider.autoDispose
    .family<LiveApproachNotifier, LiveApproach?, ApproachTarget>(
      LiveApproachNotifier.new,
    );

class LiveApproachNotifier extends Notifier<LiveApproach?> {
  LiveApproachNotifier(this._target);

  final ApproachTarget _target;
  late ApproachTracker _tracker;

  @override
  LiveApproach? build() {
    _tracker = ApproachTracker(
      api: ref.read(approachApiProvider),
      target: _target,
      now: ref.read(approachClockProvider),
    );
    // Listened, not watched: a new position must not rebuild this notifier
    // and lose the tracker's throttle and last good path.
    ref.listen<LatLng?>(workerPositionProvider, (_, position) {
      if (position != null) _follow(position);
    });
    final position = ref.read(workerPositionProvider);
    if (position == null) return null;
    scheduleMicrotask(() => _follow(position));
    return _tracker.current(position);
  }

  void _follow(LatLng position) {
    if (!ref.mounted) return;
    state = _tracker.current(position);
    if (!_tracker.isDue(position)) return;
    unawaited(
      _tracker.fetch(position).then((approach) {
        if (ref.mounted) state = approach;
      }),
    );
  }
}
