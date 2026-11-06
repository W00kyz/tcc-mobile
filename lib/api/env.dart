/// Build-time configuration, never hardcoded (docs/CLAUDE.base.md,
/// mobile/CLAUDE.md — QR/GPS don't exist in an emulator, and the base
/// address changes with the test network).
///
/// Usage:
///     flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000 \
///                  --dart-define=QR_PUBLIC_KEY_HEX=<output of backend Task 7>
///
/// Optional, for manual tests away from the campus (the test stack's seed
/// prints the full line). Without them the build is the campus one:
///     flutter run ... \
///         --dart-define=CAMPUS_TILES_ASSET=assets/tambor.pmtiles \
///         --dart-define=CAMPUS_CENTER=-7.2567,-35.8900
library;

import 'package:latlong2/latlong.dart';

/// Archive the map draws when `CAMPUS_TILES_ASSET` is not given.
const String kDefaultCampusTilesAsset = 'assets/campus.pmtiles';

/// Where the map opens when `CAMPUS_CENTER` is not given: the UFCG Campina
/// Grande campus (`kCampusCenter` in `campus_map.dart` is this value).
const LatLng kDefaultCampusCenter = LatLng(-7.2167, -35.9097);

String apiBaseUrlFromEnvironment() {
  const value = String.fromEnvironment('API_BASE_URL');
  if (value.isEmpty) {
    throw StateError(
      'API_BASE_URL not set; pass '
      '--dart-define=API_BASE_URL=http://<host>:8000.',
    );
  }
  return value;
}

String qrPublicKeyHexFromEnvironment() {
  const value = String.fromEnvironment('QR_PUBLIC_KEY_HEX');
  if (value.isEmpty) {
    throw StateError(
      'QR_PUBLIC_KEY_HEX not set; run '
      '`uv run python -m app.scripts.generate_qr_keypair` in the backend '
      'and pass --dart-define=QR_PUBLIC_KEY_HEX=<value>.',
    );
  }
  return value;
}

/// The bundled tiles archive the map opens: `--dart-define=CAMPUS_TILES_ASSET`
/// or, without it, `assets/campus.pmtiles`. The asset must be declared in
/// `pubspec.yaml`.
///
///     final bytes = await rootBundle.load(campusTilesAssetFromEnvironment());
String campusTilesAssetFromEnvironment() =>
    campusTilesAsset(const String.fromEnvironment('CAMPUS_TILES_ASSET'));

/// [raw] (the `CAMPUS_TILES_ASSET` value), or the campus archive when empty.
/// Split from [campusTilesAssetFromEnvironment] because
/// `String.fromEnvironment` is a compile-time constant a test cannot vary.
///
///     campusTilesAsset('');                       // assets/campus.pmtiles
///     campusTilesAsset('assets/tambor.pmtiles');  // assets/tambor.pmtiles
String campusTilesAsset(String raw) =>
    raw.isEmpty ? kDefaultCampusTilesAsset : raw;

/// Where the map opens when there is no route to fit:
/// `--dart-define=CAMPUS_CENTER=<lat>,<lng>`, or the campus without it.
///
///     initialCenter: campusCenterFromEnvironment()
///
/// Throws [FormatException] for a malformed value (see [parseCampusCenter]).
LatLng campusCenterFromEnvironment() => parseCampusCenter(
  const String.fromEnvironment('CAMPUS_CENTER'),
  fallback: kDefaultCampusCenter,
);

/// Parses `"<lat>,<lng>"` (decimal degrees); [fallback] when [raw] is empty.
///
///     parseCampusCenter('-7.2567,-35.8900', fallback: kCampusCenter);
///     // LatLng(-7.2567, -35.89)
///
/// Throws [FormatException] naming the value when it is not two numbers or
/// the latitude is outside ±90 or the longitude outside ±180: a typo in a
/// build flag must fail at start, not open the map in the ocean.
LatLng parseCampusCenter(String raw, {required LatLng fallback}) {
  if (raw.isEmpty) return fallback;
  final parts = raw.split(',');
  final lat = parts.length == 2 ? double.tryParse(parts[0].trim()) : null;
  final lng = parts.length == 2 ? double.tryParse(parts[1].trim()) : null;
  // Written as "not within" so NaN (which `double.tryParse` accepts) fails.
  if (lat == null || lng == null || !(lat.abs() <= 90 && lng.abs() <= 180)) {
    throw FormatException(
      'CAMPUS_CENTER "$raw" is not valid; expected "<lat>,<lng>" with '
      'latitude within ±90 and longitude within ±180, '
      'e.g. -7.2567,-35.8900.',
    );
  }
  return LatLng(lat, lng);
}
