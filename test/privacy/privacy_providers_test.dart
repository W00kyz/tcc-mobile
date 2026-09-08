import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/privacy/consent_providers.dart';
import 'package:route_monitor/privacy/my_data_providers.dart';

// consentRepositoryProvider / myDataApiProvider build on apiBaseUrlFromEnvironment
// (env.dart), which throws StateError under plain `flutter test` because no
// --dart-define is passed. Riverpod wraps a provider-body throw in a
// ProviderException — same contract asserted in route_providers_test.dart.
final Matcher _throwsWrappedStateError = throwsA(
  isA<ProviderException>().having(
    (exception) => exception.exception,
    'exception',
    isA<StateError>(),
  ),
);

void main() {
  test(
    'consentRepositoryProvider surfaces the missing API_BASE_URL failure',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(consentRepositoryProvider),
        _throwsWrappedStateError,
      );
    },
  );

  test('myDataApiProvider surfaces the missing API_BASE_URL failure', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(() => container.read(myDataApiProvider), _throwsWrappedStateError);
  });
}
