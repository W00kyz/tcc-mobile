import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/local/app_database.dart';

// executionApiProvider builds on top of env.dart's apiBaseUrlFromEnvironment
// (see env_test.dart), which throws StateError under plain `flutter test`
// because no --dart-define is passed. Riverpod wraps any error a provider's
// body throws in a ProviderException — once more for each provider it went
// through (here `apiBaseUrlProvider`) — so that is the shape a container read
// surfaces here, regardless of whether a session is present yet.
final Matcher _throwsWrappedStateError = throwsA(
  isA<ProviderException>().having(_rootCause, 'root cause', isA<StateError>()),
);

Object _rootCause(ProviderException exception) {
  var cause = exception.exception;
  while (cause is ProviderException) {
    cause = cause.exception;
  }
  return cause;
}

void main() {
  test(
    'executionApiProvider surfaces the missing API_BASE_URL failure '
    'with no session',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(executionApiProvider),
        _throwsWrappedStateError,
      );
    },
  );

  test(
    'executionApiProvider surfaces the missing API_BASE_URL failure '
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
        () => container.read(executionApiProvider),
        _throwsWrappedStateError,
      );
    },
  );

  test(
    'evidenceApiProvider surfaces the missing API_BASE_URL failure the same '
    'way executionApiProvider does',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(evidenceApiProvider),
        _throwsWrappedStateError,
      );
    },
  );

  test(
    'appDatabaseProvider is a singleton — every reader shares one '
    'AppDatabase instance for the on-device file',
    () {
      // Task 16's review: never construct a second AppDatabase() for the
      // same on-device SQLite file. This only reads the provider (Provider
      // caches its result), it never runs a query, so it never touches the
      // lazy executor's real platform channel.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final first = container.read(appDatabaseProvider);
      final second = container.read(appDatabaseProvider);

      expect(first, isA<AppDatabase>());
      expect(identical(first, second), isTrue);
    },
  );
}
