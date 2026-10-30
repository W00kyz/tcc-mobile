import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_monitor/execution/location_gate.dart';
import 'package:route_monitor/routing/location_service.dart';

const LatLng _target = LatLng(-7.2, -35.9);
const double _radius = 50;

/// A fix [metres] due north of [_target] (1 degree of latitude is a constant
/// ~111.19 km on the sphere `latlong2` uses).
Coordinates _fixAt(double metres) => Coordinates(
  latitude: _target.latitude + metres / 111194.9266,
  longitude: _target.longitude,
);

void main() {
  group('gateFor', () {
    test('service off is locationOff even with a stale fix', () {
      final gate = gateFor(
        serviceEnabled: false,
        fix: _fixAt(0),
        target: _target,
        radiusMeters: _radius,
      );

      expect(gate.state, GateState.locationOff);
    });

    test('service off without a fix is locationOff', () {
      final gate = gateFor(
        serviceEnabled: false,
        fix: null,
        target: _target,
        radiusMeters: _radius,
      );

      expect(gate.state, GateState.locationOff);
    });

    test('service on and no fix is searching, not near', () {
      final gate = gateFor(
        serviceEnabled: true,
        fix: null,
        target: _target,
        radiusMeters: _radius,
      );

      expect(gate.state, GateState.searching);
      expect(gate.distanceM, isNull);
      expect(gate.fix, isNull);
    });

    test('49 m is ready', () {
      final fix = _fixAt(49);
      final gate = gateFor(
        serviceEnabled: true,
        fix: fix,
        target: _target,
        radiusMeters: _radius,
      );

      expect(gate.state, GateState.ready);
      expect(gate.distanceM, closeTo(49, 0.5));
      expect(gate.fix, same(fix));
    });

    test('a fix exactly on the radius is ready (inclusive)', () {
      final fix = _fixAt(80);
      final exact = const Distance()(
        _target,
        LatLng(fix.latitude, fix.longitude),
      );

      final onTheEdge = gateFor(
        serviceEnabled: true,
        fix: fix,
        target: _target,
        radiusMeters: exact,
      );
      final justOutside = gateFor(
        serviceEnabled: true,
        fix: fix,
        target: _target,
        radiusMeters: exact - 0.001,
      );

      expect(onTheEdge.state, GateState.ready);
      expect(justOutside.state, GateState.tooFar);
    });

    test(
      "the server's radius rules: 60 m is tooFar at 50 m, ready at 65 m",
      () {
        final fix = _fixAt(60);

        final strict = gateFor(
          serviceEnabled: true,
          fix: fix,
          target: _target,
          radiusMeters: 50,
        );
        final lenient = gateFor(
          serviceEnabled: true,
          fix: fix,
          target: _target,
          radiusMeters: 65,
        );

        expect(strict.state, GateState.tooFar);
        expect(strict.distanceM, closeTo(60, 0.5));
        expect(lenient.state, GateState.ready);
      },
    );

    test('far away is tooFar and keeps the fix', () {
      final fix = _fixAt(1500);
      final gate = gateFor(
        serviceEnabled: true,
        fix: fix,
        target: _target,
        radiusMeters: _radius,
      );

      expect(gate.state, GateState.tooFar);
      expect(
        gate.distanceM,
        const Distance()(_target, LatLng(fix.latitude, fix.longitude)),
      );
      expect(gate.distanceM, greaterThan(1400));
      expect(gate.fix, same(fix));
    });
  });

  group('trackLocationGate', () {
    late StreamController<bool> service;
    late StreamController<Coordinates> fixes;
    late List<LocationGate> seen;

    setUp(() {
      service = StreamController<bool>();
      fixes = StreamController<Coordinates>.broadcast();
      seen = [];
      addTearDown(service.close);
      addTearDown(fixes.close);
      trackLocationGate(
        serviceEnabled: service.stream,
        fixes: () => fixes.stream,
        target: _target,
        radiusMeters: _radius,
      ).listen(seen.add);
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('follows the service and the fixes', () async {
      service.add(true);
      await settle();
      fixes.add(_fixAt(500));
      await settle();
      fixes.add(_fixAt(10));
      await settle();
      service.add(false);
      await settle();

      expect(seen.map((g) => g.state), [
        GateState.searching,
        GateState.tooFar,
        GateState.ready,
        GateState.locationOff,
      ]);
    });

    test('a fix from before the service went off is not reused', () async {
      service.add(true);
      await settle();
      fixes.add(_fixAt(10));
      await settle();
      service.add(false);
      await settle();
      service.add(true);
      await settle();

      expect(seen.last.state, GateState.searching);
    });

    test('a fixes error reads as locationOff', () async {
      service.add(true);
      await settle();
      fixes.addError(StateError('permission denied'));
      await settle();

      expect(seen.last.state, GateState.locationOff);
    });
  });
}
