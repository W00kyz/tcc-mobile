import 'package:flutter_test/flutter_test.dart';
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
}
