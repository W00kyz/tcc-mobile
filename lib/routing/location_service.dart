import 'package:geolocator/geolocator.dart';

class Coordinates {
  const Coordinates({required this.latitude, required this.longitude});
  final double latitude;
  final double longitude;
}

/// Why the caller must declare a purpose: RNF22 asks the app to spare the
/// device battery. A one-shot check-in/check-out fix wants the best possible
/// accuracy (`checkin`), but the periodic in-route position stream
/// (`position_reporter.dart`) runs for hours — there it trades a little
/// precision for `LocationAccuracy.medium` plus a 25 m `distanceFilter`
/// (`tracking`), so the GPS chip can stay idle between meaningful moves.
enum LocationPurpose { checkin, tracking }

/// Pure mapping from intent to platform settings — no `Geolocator` call, so it
/// is unit-testable without a device (`test/routing/location_service_test.dart`).
///
/// Example:
/// ```dart
/// final settings = locationSettingsFor(LocationPurpose.tracking);
/// // settings.accuracy == LocationAccuracy.medium, settings.distanceFilter == 25
/// ```
LocationSettings locationSettingsFor(LocationPurpose purpose) {
  switch (purpose) {
    case LocationPurpose.checkin:
      return const LocationSettings(accuracy: LocationAccuracy.high);
    case LocationPurpose.tracking:
      return const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 25,
      );
  }
}

// A single-method interface is deliberate here, not an oversight: it is the
// seam that keeps widget tests off the real GPS/platform channel
// (docs/CLAUDE.base.md — Dependencies: "wrap third-party libs behind a thin
// interface").
// ignore: one_member_abstracts
abstract class LocationService {
  Future<Coordinates> getCurrentPosition({required LocationPurpose purpose});
}

// Real GPS implementation. Only exercisable on a physical Android device
// (QR/GPS don't work on the emulator — CLAUDE.md), so it is wired to a
// device test in Task 19 rather than a unit test here.
class GeolocatorLocationService implements LocationService {
  @override
  Future<Coordinates> getCurrentPosition({
    required LocationPurpose purpose,
  }) async {
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
      locationSettings: locationSettingsFor(purpose),
    );
    return Coordinates(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }
}
