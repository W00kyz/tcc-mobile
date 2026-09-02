import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/checkin/checkin_providers.dart';

// qrVerifierProvider builds on top of env.dart's getter (see env_test.dart),
// which throws StateError under plain `flutter test` because no
// --dart-define is passed. Riverpod wraps any error a provider's body
// throws in a ProviderException, so that is the shape a container read
// surfaces here — a ProviderContainer read is the same seam ScanScreen uses
// in production, so this confirms the wiring fails loudly instead of
// silently building a verifier against an empty public key.
final Matcher _throwsWrappedStateError = throwsA(
  isA<ProviderException>().having(
    (exception) => exception.exception,
    'exception',
    isA<StateError>(),
  ),
);

void main() {
  test(
    'qrVerifierProvider surfaces the missing QR_PUBLIC_KEY_HEX failure',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(qrVerifierProvider),
        _throwsWrappedStateError,
      );
    },
  );
}
