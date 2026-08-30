import 'package:geolocator/geolocator.dart';

class Coordinates {
  const Coordinates({required this.latitude, required this.longitude});
  final double latitude;
  final double longitude;
}

// A single-method interface is deliberate here, not an oversight: it is the
// seam that keeps widget tests off the real GPS/platform channel
// (docs/CLAUDE.base.md — Dependencies: "wrap third-party libs behind a thin
// interface").
// ignore: one_member_abstracts
abstract class LocationService {
  Future<Coordinates> getCurrentPosition();
}

// Real GPS implementation. Only exercisable on a physical Android device
// (QR/GPS don't work on the emulator — CLAUDE.md), so it is wired to a
// device test in Task 19 rather than a unit test here.
class GeolocatorLocationService implements LocationService {
  @override
  Future<Coordinates> getCurrentPosition() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final requested = await Geolocator.requestPermission();
      if (requested == LocationPermission.denied ||
          requested == LocationPermission.deniedForever) {
        throw StateError(
          'Location permission denied; RF29/RF34 cannot capture GPS without it.',
        );
      }
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return Coordinates(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }
}
