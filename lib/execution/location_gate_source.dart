import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:route_monitor/execution/location_gate.dart';
import 'package:route_monitor/routing/location_service.dart';

/// The live gate of one location stop, behind a seam so widget tests never
/// reach the Geolocator platform channel.
// A single-method interface on purpose, like `LocationService`.
// ignore: one_member_abstracts
abstract class LocationGateSource {
  /// A gate on every change of the location service or of the position, until
  /// the subscription is cancelled. [radiusMeters] is the route's
  /// `check_radius_meters`.
  Stream<LocationGate> watch(LatLng target, double radiusMeters);
}

/// The real source. Only exercisable on a device; the rule it feeds is
/// covered by `test/execution/location_gate_test.dart`.
class GeolocatorLocationGateSource implements LocationGateSource {
  @override
  Stream<LocationGate> watch(LatLng target, double radiusMeters) =>
      trackLocationGate(
        serviceEnabled: _serviceStates(),
        fixes: _positions,
        target: target,
        radiusMeters: radiusMeters,
      );

  Stream<bool> _serviceStates() async* {
    yield await Geolocator.isLocationServiceEnabled();
    yield* Geolocator.getServiceStatusStream().map(
      (status) => status == ServiceStatus.enabled,
    );
  }

  /// Asks for the permission when it is still undecided; a refusal is thrown
  /// and reads as `locationOff` (the worker is told to turn location on).
  Stream<Coordinates> _positions() async* {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError(
        'Location permission is $permission; the gate of a location stop '
        'needs it to read the position.',
      );
    }
    yield* Geolocator.getPositionStream(
      locationSettings: locationSettingsFor(LocationPurpose.checkin),
    ).map(
      (p) => Coordinates(latitude: p.latitude, longitude: p.longitude),
    );
  }
}

final locationGateSourceProvider = Provider<LocationGateSource>(
  (ref) => GeolocatorLocationGateSource(),
);

/// What identifies one live gate: the stop's coordinates and the route's check
/// radius (part of the key so a changed radius re-evaluates the gate).
typedef LocationGateKey = ({LatLng target, double radiusMeters});

/// The live gate of the stop at a target (its coordinates) within the route's
/// radius; disposed with the dialog watching it, which stops the GPS.
final StreamProviderFamily<LocationGate, LocationGateKey> locationGateProvider =
    StreamProvider.autoDispose.family<LocationGate, LocationGateKey>(
      (ref, key) => ref
          .watch(locationGateSourceProvider)
          .watch(key.target, key.radiusMeters),
    );
