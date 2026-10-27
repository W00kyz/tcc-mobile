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

/// Where the worker's day is kept for offline use (RF35, RNF21).
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

/// `GET /routes/me`: today's route (if any) with its current batch.
/// Invalidate it to re-read the day after any write that changes it.
final myDayProvider = FutureProvider<MyDay>((ref) {
  return ref.watch(routeRepositoryProvider).fetchMyDay();
});
