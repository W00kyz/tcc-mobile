import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/checkin/checkin_providers.dart';

// checkInRepositoryProvider and qrVerifierProvider both build on top of the
// env.dart getters (see env_test.dart), which throw StateError under plain
// `flutter test` because no --dart-define is passed. Riverpod wraps any
// error a provider's body throws in a ProviderException, so that is the
// shape a container read surfaces here — a ProviderContainer read is the
// same seam ScanScreen uses in production, so this confirms the wiring
// fails loudly instead of silently building a repository against an empty
// base URL, regardless of whether a session is present yet.
final Matcher _throwsWrappedStateError = throwsA(
  isA<ProviderException>().having(
    (exception) => exception.exception,
    'exception',
    isA<StateError>(),
  ),
);

void main() {
  test(
    'checkInRepositoryProvider surfaces the missing API_BASE_URL failure '
    'with no session',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(checkInRepositoryProvider),
        _throwsWrappedStateError,
      );
    },
  );

  test(
    'checkInRepositoryProvider surfaces the missing API_BASE_URL failure '
    'with a session present',
    () {
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWithBuild(
            (ref, notifier) => const Session(
              accessToken: 'a-test-token',
              refreshToken: 'a-refresh-token',
              role: 'FIELD_WORKER',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        () => container.read(checkInRepositoryProvider),
        _throwsWrappedStateError,
      );
    },
  );

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
