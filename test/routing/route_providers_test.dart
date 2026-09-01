import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';

class _FakeRouteRepository implements RouteRepository {
  @override
  Future<List<RouteSummary>> fetchMyRoutes({DateTime? date}) async => const [];

  @override
  Future<RouteSummary> startRoute({
    required String routeId,
    required double latitude,
    required double longitude,
  }) async {
    throw UnimplementedError('not exercised in this test');
  }
}

// routeRepositoryProvider builds on top of env.dart's
// apiBaseUrlFromEnvironment (see env_test.dart), which throws StateError
// under plain `flutter test` because no --dart-define is passed. Riverpod
// wraps any error a provider's body throws in a ProviderException, so that
// is the shape a container read surfaces here. That failure must surface
// unchanged regardless of whether a session is present yet.
final Matcher _throwsWrappedStateError = throwsA(
  isA<ProviderException>().having(
    (exception) => exception.exception,
    'exception',
    isA<StateError>(),
  ),
);

void main() {
  test('locationServiceProvider builds the real GeolocatorLocationService', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(locationServiceProvider),
      isA<GeolocatorLocationService>(),
    );
  });

  test(
    'routeRepositoryProvider surfaces the missing API_BASE_URL failure '
    'with no session',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(routeRepositoryProvider),
        _throwsWrappedStateError,
      );
    },
  );

  test(
    'routeRepositoryProvider surfaces the missing API_BASE_URL failure '
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
        () => container.read(routeRepositoryProvider),
        _throwsWrappedStateError,
      );
    },
  );

  test('myRoutesProvider delegates to routeRepositoryProvider', () async {
    final container = ProviderContainer(
      overrides: [
        routeRepositoryProvider.overrideWithValue(_FakeRouteRepository()),
      ],
    );
    addTearDown(container.dispose);

    final routes = await container.read(myRoutesProvider.future);

    expect(routes, isEmpty);
  });
}
