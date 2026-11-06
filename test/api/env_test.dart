import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_monitor/api/env.dart';

// Under plain `flutter test` (no --dart-define passed), String.fromEnvironment
// is empty for both keys, so both throw paths are directly exercisable here
// without any fixture. This is the regression test for "malformed/missing
// key silently degrading vs. crashing" — the app must fail loudly and early,
// not build a Dio client with an empty base URL or a QrVerifier with an
// empty public key.
void main() {
  test(
    'apiBaseUrlFromEnvironment throws when API_BASE_URL is not set',
    () {
      expect(apiBaseUrlFromEnvironment, throwsStateError);
    },
  );

  test(
    'qrPublicKeyHexFromEnvironment throws when QR_PUBLIC_KEY_HEX is not set',
    () {
      expect(qrPublicKeyHexFromEnvironment, throwsStateError);
    },
  );

  group('campus tiles asset', () {
    test('campus_tiles_asset_defaults_to_the_campus_archive', () {
      expect(campusTilesAsset(''), 'assets/campus.pmtiles');
      expect(campusTilesAssetFromEnvironment(), 'assets/campus.pmtiles');
    });

    test('campus_tiles_asset_uses_the_given_archive', () {
      expect(
        campusTilesAsset('assets/tambor.pmtiles'),
        'assets/tambor.pmtiles',
      );
    });
  });

  group('parseCampusCenter', () {
    const fallback = kDefaultCampusCenter;

    test('parse_campus_center_reads_lat_lng', () {
      expect(
        parseCampusCenter('-7.2567,-35.8900', fallback: fallback),
        const LatLng(-7.2567, -35.89),
      );
    });

    test('parse_campus_center_tolerates_spaces_around_the_parts', () {
      expect(
        parseCampusCenter(' -7.2567 , -35.89 ', fallback: fallback),
        const LatLng(-7.2567, -35.89),
      );
    });

    test('parse_campus_center_uses_the_fallback_when_empty', () {
      expect(parseCampusCenter('', fallback: fallback), fallback);
      expect(campusCenterFromEnvironment(), kDefaultCampusCenter);
    });

    test('parse_campus_center_rejects_malformed_values', () {
      for (final raw in [
        'abc',
        'a,b',
        '1,2,3',
        '-7.2567',
        '-7.2567,',
        '91,0',
        '-90.5,0',
        '0,181',
        '0,-180.1',
        'NaN,0',
      ]) {
        expect(
          () => parseCampusCenter(raw, fallback: fallback),
          throwsFormatException,
          reason: raw,
        );
      }
    });

    test('parse_campus_center_accepts_the_range_limits', () {
      expect(
        parseCampusCenter('-90,180', fallback: fallback),
        const LatLng(-90, 180),
      );
    });
  });
}
