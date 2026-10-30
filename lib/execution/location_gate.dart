import 'dart:async';

import 'package:latlong2/latlong.dart';

import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/scan_proximity.dart';

/// Where a worker stands against the "Concluir tarefa" gate of a location stop.
enum GateState { ready, locationOff, searching, tooFar }

/// One reading of the gate. [distanceM] is set for `ready` and `tooFar`;
/// [fix] is the position that decided it, kept for the completion.
class LocationGate {
  const LocationGate(this.state, {this.distanceM, this.fix});

  final GateState state;
  final double? distanceM;
  final Coordinates? fix;
}

/// The single rule of the gate. Unlike `isNearBuilding`, a missing fix does
/// NOT count as near: a place is concluded by being there, so the worker with
/// no position yet is still `searching`. A stale [fix] with the location
/// service off is ignored.
///
///     gateFor(serviceEnabled: true, fix: fix, target: place).state;
LocationGate gateFor({
  required bool serviceEnabled,
  required Coordinates? fix,
  required LatLng target,
  double radiusMeters = kScanProximityMeters,
}) {
  if (!serviceEnabled) return const LocationGate(GateState.locationOff);
  if (fix == null) return const LocationGate(GateState.searching);
  final distance = const Distance()(
    LatLng(fix.latitude, fix.longitude),
    target,
  );
  final state = distance <= radiusMeters ? GateState.ready : GateState.tooFar;
  return LocationGate(state, distanceM: distance, fix: fix);
}

/// The live gate: re-evaluated on every change of the location service and on
/// every fix. [fixes] is a factory because a platform position stream does not
/// survive the service going off — it is subscribed anew each time the service
/// comes on, and the fix of before is dropped (back to `searching`). A [fixes]
/// error (permission denied) reads as `locationOff`: the same remedy.
///
///     trackLocationGate(
///       serviceEnabled: serviceStates,
///       fixes: () => positions,
///       target: place,
///     ).listen(show);
Stream<LocationGate> trackLocationGate({
  required Stream<bool> serviceEnabled,
  required Stream<Coordinates> Function() fixes,
  required LatLng target,
  double radiusMeters = kScanProximityMeters,
}) {
  return _GateTracker(serviceEnabled, fixes, target, radiusMeters).stream;
}

class _GateTracker {
  _GateTracker(this._service, this._fixes, this._target, this._radius) {
    _out = StreamController<LocationGate>(
      onListen: () => _serviceSub = _service.listen(_onService),
      onCancel: _stop,
    );
  }

  final Stream<bool> _service;
  final Stream<Coordinates> Function() _fixes;
  final LatLng _target;
  final double _radius;
  late final StreamController<LocationGate> _out;
  StreamSubscription<bool>? _serviceSub;
  StreamSubscription<Coordinates>? _fixSub;
  bool _enabled = false;
  Coordinates? _fix;

  Stream<LocationGate> get stream => _out.stream;

  void _onService(bool enabled) {
    _enabled = enabled;
    _fix = null;
    unawaited(_fixSub?.cancel());
    _fixSub = enabled
        ? _fixes().listen(_onFix, onError: (_) => _onFixError())
        : null;
    _emit();
  }

  void _onFix(Coordinates fix) {
    _fix = fix;
    _emit();
  }

  void _onFixError() {
    unawaited(_fixSub?.cancel());
    _fixSub = null;
    _out.add(const LocationGate(GateState.locationOff));
  }

  void _emit() => _out.add(
    gateFor(
      serviceEnabled: _enabled,
      fix: _fix,
      target: _target,
      radiusMeters: _radius,
    ),
  );

  Future<void> _stop() async {
    await _fixSub?.cancel();
    await _serviceSub?.cancel();
  }
}
