import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show TileProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/room_picker.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/map_screen.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A completed scan+GPS read, threaded from `_scanAndLocate` into a
/// check-in/check-out attempt and any of its room-picker retries.
class _Scan {
  const _Scan(this.rawValue, this.coordinates);
  final String rawValue;
  final Coordinates? coordinates;
}

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
                      for (final stop in route.stops)
                        _StopTile(
                          stop: stop,
                          onConcluir: stop.status == 'IN_PROGRESS'
                              ? () => _checkOut(context, ref, route, stop)
                              : null,
                        ),
                    ],
                  ),
                ),
                if (route.startedAt == null)
                  FilledButton(
                    onPressed: () => _startRoute(context, ref, route.id),
                    child: const Text('Iniciar rota'),
                  ),
                if (_canCheckIn(route))
                  FilledButton(
                    onPressed: () => _checkIn(context, ref, route),
                    child: const Text('Fazer check-in'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// One route-level "Fazer check-in" action, not a per-stop button: the QR
  /// scan resolves which stop it belongs to (and can be ambiguous, Task 18).
  /// Checks for a `PENDING` stop specifically, not just "not DONE" — an
  /// `IN_PROGRESS` stop (already checked in, awaiting checkout, Task 18) has
  /// no `PENDING` candidate left on its floor, so scanning again would only
  /// get a confusing 422 FLOOR_NOT_ON_ROUTE from the backend.
  bool _canCheckIn(RouteSummary route) =>
      route.status == 'IN_PROGRESS' &&
      route.stops.any((stop) => stop.status == 'PENDING');

  Future<void> _checkIn(
    BuildContext context,
    WidgetRef ref,
    RouteSummary route,
  ) async {
    final scan = await _scanAndLocate(context, ref);
    if (scan == null || !context.mounted) return;

    // Generated once per tap, in scope for both the first attempt and any
    // room-picker retry below — Ruling 16: one tap on "Fazer check-in" is
    // one logical attempt, even when a 409 makes it take two network calls.
    final idempotencyKey = _uuid.v4();
    await _attemptCheckIn(
      context,
      ref,
      route: route,
      scan: scan,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<void> _attemptCheckIn(
    BuildContext context,
    WidgetRef ref, {
    required RouteSummary route,
    required _Scan scan,
    required String idempotencyKey,
    String? routeStopId,
  }) async {
    try {
      await ref
          .read(executionRepositoryProvider)
          .checkIn(
            routeId: route.id,
            qrPayload: scan.rawValue,
            latitude: scan.coordinates?.latitude,
            longitude: scan.coordinates?.longitude,
            idempotencyKey: idempotencyKey,
            routeStopId: routeStopId,
          );
      ref.invalidate(myRoutesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Check-in registrado.')));
      }
    } on AmbiguousRoomException catch (e) {
      if (!context.mounted) return;
      final chosen = await showRoomPicker(context, e.candidates);
      if (chosen == null || !context.mounted) return;
      await _attemptCheckIn(
        context,
        ref,
        route: route,
        scan: scan,
        idempotencyKey: idempotencyKey,
        routeStopId: chosen.routeStopId,
      );
      // Deliberately broad: any other failure — DioException (network/HTTP)
      // or otherwise — maps to the same generic message here.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível registrar o check-in.'),
          ),
        );
      }
    }
  }

  Future<void> _checkOut(
    BuildContext context,
    WidgetRef ref,
    RouteSummary route,
    RouteStopSummary stop,
  ) async {
    final scan = await _scanAndLocate(context, ref);
    if (scan == null || !context.mounted) return;

    // Same one-tap-one-attempt rule as _checkIn's idempotencyKey above.
    final checkoutIdempotencyKey = _uuid.v4();
    await _attemptCheckOut(
      context,
      ref,
      route: route,
      scan: scan,
      routeStopId: stop.id,
      checkoutIdempotencyKey: checkoutIdempotencyKey,
    );
  }

  Future<void> _attemptCheckOut(
    BuildContext context,
    WidgetRef ref, {
    required RouteSummary route,
    required _Scan scan,
    required String routeStopId,
    required String checkoutIdempotencyKey,
  }) async {
    try {
      await ref
          .read(executionRepositoryProvider)
          .checkOut(
            routeId: route.id,
            routeStopId: routeStopId,
            qrPayload: scan.rawValue,
            latitude: scan.coordinates?.latitude,
            longitude: scan.coordinates?.longitude,
            checkoutIdempotencyKey: checkoutIdempotencyKey,
          );
      // A successful check-out flips the stop to DONE on the backend; this
      // invalidate is what makes it "leave the list" (the Concluir button's
      // visibility condition is status == 'IN_PROGRESS', and the existing
      // done-icon rendering in _StopTile takes over) — no client-side
      // filtering needed.
      ref.invalidate(myRoutesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check-out registrado.')),
        );
      }
    } on AmbiguousRoomException catch (e) {
      // Defense in depth (Ruling 16) — check-out already sends its own stop
      // as routeStopId, so this is rare, but two open check-ins on the same
      // floor can still trigger it; handled identically to check-in's.
      if (!context.mounted) return;
      final chosen = await showRoomPicker(context, e.candidates);
      if (chosen == null || !context.mounted) return;
      await _attemptCheckOut(
        context,
        ref,
        route: route,
        scan: scan,
        routeStopId: chosen.routeStopId,
        checkoutIdempotencyKey: checkoutIdempotencyKey,
      );
      // Deliberately broad: every other failure — including the ordinary
      // 422 NO_OPEN_CHECKIN DioException — maps to the same generic message,
      // same discipline as every other error path in this file.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível registrar o check-out.'),
          ),
        );
      }
    }
  }

  /// Pushes [ScanScreen] and, if a value came back, pairs it with a
  /// tolerant GPS read — the shared first half of both check-in and
  /// check-out (Ruling 16: check-out reuses check-in's scan+GPS dance).
  /// Returns null when the scan was dismissed or the context is no longer
  /// mounted afterward.
  Future<_Scan?> _scanAndLocate(BuildContext context, WidgetRef ref) async {
    final rawValue = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const ScanScreen()),
    );
    if (rawValue == null || !context.mounted) return null;

    final coordinates = await _tryGetPosition(context, ref);
    return _Scan(rawValue, coordinates);
  }

  /// GPS is tolerated as unavailable here (RF29/RNF13 — a basement has no
  /// signal): the backend's Layer 7 already treats a missing position as
  /// ACCEPT+flag, so a failure here must not block the check-in, only note
  /// it to the field worker.
  Future<Coordinates?> _tryGetPosition(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      return await ref.read(locationServiceProvider).getCurrentPosition();
      // Deliberately broad: GeolocatorLocationService can fail with a
      // StateError (permission denied), a platform exception, or a timeout
      // — all of them mean "proceed without GPS" here, never "block".
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível obter sua localização; check-in seguirá '
              'sem GPS.',
            ),
          ),
        );
      }
      return null;
    }
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
  const _StopTile({required this.stop, this.onConcluir});

  final RouteStopSummary stop;

  /// The "Concluir" (check-out) action for this stop, or null to hide the
  /// button. RouteScreen passes a callback only for an `IN_PROGRESS` stop —
  /// this widget stays a plain StatelessWidget with no WidgetRef of its own,
  /// leaving the execution-repository/room-picker wiring to RouteScreen.
  final VoidCallback? onConcluir;

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
      trailing: onConcluir == null
          ? null
          : TextButton(
              onPressed: onConcluir,
              child: const Text('Concluir'),
            ),
    );
  }
}
