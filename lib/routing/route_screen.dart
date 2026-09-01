import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show TileProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/map_screen.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';

/// Formats an arrival window as `HH:MM–HH:MM` (RF14). Returns `null` when
/// neither bound is set, and a single `HH:MM` when only one bound is present.
String? _formatWindow(DateTime? from, DateTime? to) {
  if (from == null && to == null) return null;
  if (from != null && to != null) {
    return '${_hhmm(from)}–${_hhmm(to)}';
  }
  return _hhmm(from ?? to!);
}

String _hhmm(DateTime time) {
  // INTENTIONAL: read .hour/.minute straight off the DateTime, no .toLocal().
  // Arrival windows come from the backend as wall-clock times tagged UTC
  // (system-wide convention — see dashboard RouteBuilderPage `extractTime`).
  // Adding .toLocal() here would shift every window by the UTC offset.
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// Formats the travel-from-previous leg as `N m · N min` (RF12). Returns `null`
/// when the distance is unknown; drops the time part when the duration is.
String? _formatLeg(double? distanceM, double? durationS) {
  if (distanceM == null) return null;
  final distance = '${distanceM.round()} m';
  if (durationS == null) return distance;
  return '$distance · ${(durationS / 60).round()} min';
}

class RouteScreen extends ConsumerWidget {
  const RouteScreen({super.key, this.mapTileProvider});

  /// Forwarded to [MapScreen] as its base-tile override. Null in production, so
  /// the map loads the bundled offline PMTiles. Widget tests inject a no-op
  /// provider here to keep vector_map_tiles' real tile pipeline (and the timers
  /// it schedules) out of `flutter_test` when they navigate to the map.
  final TileProvider? mapTileProvider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routesAsync = ref.watch(myRoutesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Rota de hoje')),
      body: routesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            const Center(child: Text('Não foi possível carregar sua rota.')),
        data: (routes) {
          if (routes.isEmpty) {
            return const Center(
              child: Text('Nenhuma rota atribuída para hoje.'),
            );
          }
          final route = routes.first;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RouteHeader(route: route),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MapScreen(
                        route: route,
                        tileProviderOverride: mapTileProvider,
                      ),
                    ),
                  ),
                  child: const Text('Ver no mapa'),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    children: [
                      for (final stop in route.stops) _StopTile(stop: stop),
                    ],
                  ),
                ),
                if (route.startedAt == null)
                  FilledButton(
                    onPressed: () => _startRoute(context, ref, route.id),
                    child: const Text('Iniciar rota'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _startRoute(
    BuildContext context,
    WidgetRef ref,
    String routeId,
  ) async {
    final location = ref.read(locationServiceProvider);
    final Coordinates position;
    try {
      position = await location.getCurrentPosition();
      // Deliberately broad: GeolocatorLocationService can fail with a
      // StateError (permission denied), a platform exception, or a timeout
      // — all of them map to the same user-facing message here.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível obter sua localização.'),
          ),
        );
      }
      return;
    }

    try {
      await ref
          .read(routeRepositoryProvider)
          .startRoute(
            routeId: routeId,
            latitude: position.latitude,
            longitude: position.longitude,
          );
      ref.invalidate(myRoutesProvider);
      // Deliberately broad: the backend can reject this with 403 (route not
      // yours), 404, or 409 (already started) — every DioException from this
      // call must reach the user as feedback instead of propagating as an
      // unhandled async error.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível iniciar a rota.')),
        );
      }
    }
  }
}

class _RouteHeader extends StatelessWidget {
  const _RouteHeader({required this.route});

  final RouteSummary route;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            route.startedAt == null ? 'Rota não iniciada' : 'Rota iniciada',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (route.routeType == 'OCCASIONAL')
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Chip(label: Text('EVENTUAL')),
          ),
      ],
    );
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({required this.stop});

  final RouteStopSummary stop;

  @override
  Widget build(BuildContext context) {
    final isDone = stop.status == 'DONE';
    final window = _formatWindow(
      stop.expectedArrivalFrom,
      stop.expectedArrivalTo,
    );
    final leg = _formatLeg(stop.distanceFromPrevM, stop.durationFromPrevS);

    return ListTile(
      leading: CircleAvatar(
        radius: 14,
        // Smaller than default so a 2-digit orderIndex (routes with >= 10
        // stops) still fits inside the r=14 circle without clipping.
        child: Text(
          '${stop.orderIndex}',
          style: const TextStyle(fontSize: 12),
        ),
      ),
      title: Row(
        children: [
          Icon(
            isDone ? Icons.check_circle : Icons.qr_code_scanner,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(stop.servicePointName)),
          if (stop.pointType == 'OCCASIONAL')
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Chip(label: Text('Ponto eventual')),
            ),
        ],
      ),
      subtitle: window == null && leg == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leg != null) Text('a $leg'),
                if (window != null) Text('Janela: $window'),
              ],
            ),
      trailing: isDone
          ? null
          : TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ScanScreen(routeStopId: stop.id),
                ),
              ),
              child: const Text('Check-in'),
            ),
    );
  }
}
