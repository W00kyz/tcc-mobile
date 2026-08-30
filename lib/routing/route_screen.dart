import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_providers.dart';

class RouteScreen extends ConsumerWidget {
  const RouteScreen({super.key});

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
                Text(
                  route.startedAt == null
                      ? 'Rota não iniciada'
                      : 'Rota iniciada',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                for (final stop in route.stops)
                  ListTile(
                    leading: Icon(
                      stop.status == 'DONE'
                          ? Icons.check_circle
                          : Icons.qr_code_scanner,
                    ),
                    title: Text(stop.servicePointName),
                    trailing: stop.status == 'DONE'
                        ? null
                        : TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    ScanScreen(routeStopId: stop.id),
                              ),
                            ),
                            child: const Text('Check-in'),
                          ),
                  ),
                const Spacer(),
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
