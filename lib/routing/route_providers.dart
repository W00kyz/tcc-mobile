import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/execution/execution_providers.dart'
    show appDatabaseProvider;
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/route_snapshot_cache.dart';

final locationServiceProvider = Provider<LocationService>(
  (ref) => GeolocatorLocationService(),
);

/// Where today's route list is kept for offline use (RF35, RNF21).
final routeSnapshotCacheProvider = Provider<RouteSnapshotCache>(
  (ref) => DriftRouteSnapshotCache(ref.watch(appDatabaseProvider)),
);

final routeRepositoryProvider = Provider<RouteRepository>((ref) {
  final dio = buildSessionDio(ref);
  return DioRouteRepository(
    dio,
    cache: ref.watch(routeSnapshotCacheProvider),
    userId: ref.watch(sessionProvider)?.userId,
  );
});

final myRoutesProvider = FutureProvider<List<RouteSummary>>((ref) {
  return ref.watch(routeRepositoryProvider).fetchMyRoutes();
});
