import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/api/api_client.dart';
import 'package:route_monitor/api/env.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_repository.dart';

final locationServiceProvider = Provider<LocationService>(
  (ref) => GeolocatorLocationService(),
);

final routeRepositoryProvider = Provider<RouteRepository>((ref) {
  final session = ref.watch(sessionProvider);
  final dio = buildDio(
    baseUrl: apiBaseUrlFromEnvironment(),
    accessToken: session?.accessToken,
  );
  return DioRouteRepository(dio);
});

final myRoutesProvider = FutureProvider<List<RouteSummary>>((ref) {
  return ref.watch(routeRepositoryProvider).fetchMyRoutes();
});
