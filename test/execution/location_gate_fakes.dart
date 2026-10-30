import 'dart:async';

import 'package:latlong2/latlong.dart';
import 'package:route_monitor/execution/location_gate.dart';
import 'package:route_monitor/execution/location_gate_source.dart';

/// A [LocationGateSource] the test drives by hand: every watcher first gets
/// the current gate, then each one passed to [emit]. Never touches Geolocator.
class FakeLocationGateSource implements LocationGateSource {
  FakeLocationGateSource([
    this._current = const LocationGate(GateState.searching),
  ]);

  final StreamController<LocationGate> _changes =
      StreamController<LocationGate>.broadcast();
  final List<LatLng> watchedTargets = [];
  final List<double> watchedRadii = [];
  LocationGate _current;

  void emit(LocationGate gate) {
    _current = gate;
    _changes.add(gate);
  }

  @override
  Stream<LocationGate> watch(LatLng target, double radiusMeters) async* {
    watchedTargets.add(target);
    watchedRadii.add(radiusMeters);
    yield _current;
    yield* _changes.stream;
  }
}
