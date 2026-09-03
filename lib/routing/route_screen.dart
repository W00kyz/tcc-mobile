import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show TileProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/execution/evidence_list.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/room_picker.dart';
import 'package:route_monitor/local/local_write_store.dart' show PendingOpState;
import 'package:route_monitor/local/stop_progress_store.dart'
    show StopLocalStatus;
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
          final startedLocally =
              ref.watch(routeStartedLocallyProvider(route.id)).asData?.value ??
              false;
          final started = route.startedAt != null || startedLocally;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RouteHeader(route: route, started: started),
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
                          evidenceSection: stop.status == 'IN_PROGRESS'
                              ? _StopEvidenceSection(
                                  routeId: route.id,
                                  routeStopId: stop.id,
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
                if (!started)
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

    // No network call and no try/catch here any more (Etapa 6 Task 9): the
    // write only enqueues an outbox row + a local "started" marker and kicks
    // the sync worker. The SyncWorker owns the dispatch, the 409
    // "already started" handling (spec Ruling 8) and every failure class.
    await ref
        .read(executionRepositoryProvider)
        .startRoute(
          routeId: routeId,
          latitude: position.latitude,
          longitude: position.longitude,
        );
    // Re-read the optimistic marker so the button flips now, without waiting
    // on a myRoutesProvider refetch (spec Ruling 5).
    ref.invalidate(routeStartedLocallyProvider(routeId));
  }
}

class _RouteHeader extends StatelessWidget {
  const _RouteHeader({required this.route, required this.started});

  final RouteSummary route;

  /// True when the server says the route is started OR this device has a
  /// local optimistic marker from a not-yet-synced "Iniciar rota" tap.
  final bool started;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            started ? 'Rota iniciada' : 'Rota não iniciada',
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
  const _StopTile({required this.stop, this.onConcluir, this.evidenceSection});

  final RouteStopSummary stop;

  /// The "Concluir" (check-out) action for this stop, or null to hide the
  /// button. RouteScreen passes a callback only for an `IN_PROGRESS` stop —
  /// this widget stays a plain StatelessWidget with no WidgetRef of its own,
  /// leaving the execution-repository/room-picker wiring to RouteScreen.
  final VoidCallback? onConcluir;

  /// The evidence buttons + list for this stop, or null to omit that whole
  /// block (every non-`IN_PROGRESS` stop). RouteScreen builds this as a
  /// `_StopEvidenceSection` — this widget just gives it a slot below the
  /// tile, keeping `_StopTile` itself a plain, ref-free StatelessWidget.
  final Widget? evidenceSection;

  @override
  Widget build(BuildContext context) {
    final isDone = stop.status == 'DONE';
    final window = _formatWindow(
      stop.expectedArrivalFrom,
      stop.expectedArrivalTo,
    );
    final leg = _formatLeg(stop.distanceFromPrevM, stop.durationFromPrevS);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
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
        ),
        ?evidenceSection,
      ],
    );
  }
}

/// Resolves [routeStopId]'s open `execution_id` (Ruling 17) and, only when
/// found, shows the evidence buttons + list for it. A `null` result — no
/// `OpenExecutions` row, the accepted cold-start gap for a stop that turned
/// `IN_PROGRESS` before that table existed — hides the whole section rather
/// than showing a broken action.
class _StopEvidenceSection extends ConsumerWidget {
  const _StopEvidenceSection({
    required this.routeId,
    required this.routeStopId,
  });

  final String routeId;
  final String routeStopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressAsync = ref.watch(stopProgressForProvider(routeStopId));
    return progressAsync.when(
      // A `done` stop no longer offers evidence-add buttons (Etapa 5 §6.3):
      // only an `inProgress` entry opens the section.
      data: (entry) =>
          entry == null || entry.status != StopLocalStatus.inProgress
          ? const SizedBox.shrink()
          : _EvidenceSection(routeId: routeId, executionId: entry.executionId),
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

/// The "Adicionar foto"/"Adicionar observação" buttons and the evidence list
/// for one stop's open execution.
class _EvidenceSection extends ConsumerWidget {
  const _EvidenceSection({required this.routeId, required this.executionId});

  final String routeId;
  final String executionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (routeId, executionId);
    final itemsAsync = ref.watch(stopEvidenceProvider(query));

    return Padding(
      padding: const EdgeInsets.only(left: 56, right: 16, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => _addPhoto(context, ref, query),
                icon: const Icon(Icons.add_a_photo),
                label: const Text('Adicionar foto'),
              ),
              TextButton.icon(
                onPressed: () => _addNote(context, ref, query),
                icon: const Icon(Icons.note_add),
                label: const Text('Adicionar observação'),
              ),
            ],
          ),
          itemsAsync.when(
            data: (items) =>
                items.isEmpty ? const SizedBox.shrink() : _EvidenceList(items),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (_, _) =>
                const Text('Não foi possível carregar as evidências.'),
          ),
        ],
      ),
    );
  }

  Future<void> _addPhoto(
    BuildContext context,
    WidgetRef ref,
    (String, String) query,
  ) async {
    try {
      final photo = await ref.read(evidenceCaptureProvider).takePhoto();
      if (photo == null) return; // The field worker cancelled the camera.
      await ref
          .read(executionRepositoryProvider)
          .addPhoto(routeId: query.$1, executionId: query.$2, photo: photo);
      ref.invalidate(stopEvidenceProvider(query));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Foto adicionada.')));
      }
      // Deliberately broad: a compression failure (StateError), a network
      // failure (DioException) or any other capture/upload error all map to
      // the same generic message here, same discipline as check-in/out.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível adicionar a foto.')),
        );
      }
    }
  }

  Future<void> _addNote(
    BuildContext context,
    WidgetRef ref,
    (String, String) query,
  ) async {
    final text = await _showNoteDialog(context);
    if (text == null || text.isEmpty || !context.mounted) return;

    try {
      await ref
          .read(executionRepositoryProvider)
          .addNote(routeId: query.$1, executionId: query.$2, text: text);
      ref.invalidate(stopEvidenceProvider(query));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Observação adicionada.')),
        );
      }
      // Deliberately broad: same rationale as _addPhoto above.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível adicionar a observação.'),
          ),
        );
      }
    }
  }
}

/// A `showDialog` + single `TextField` — simplest idiomatic Flutter shape
/// for a short free-text prompt, no need for the dashboard's React-modal
/// pattern here. Returns the trimmed text, or null if cancelled/dismissed.
Future<String?> _showNoteDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Adicionar observação'),
      content: TextField(
        controller: controller,
        maxLength: 2000,
        maxLines: 4,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Descreva a observação'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
}

class _EvidenceList extends StatelessWidget {
  const _EvidenceList(this.items);

  final List<EvidenceListEntry> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final item in items) _EvidenceTile(item)],
    );
  }
}

class _EvidenceTile extends ConsumerWidget {
  const _EvidenceTile(this.item);

  final EvidenceListEntry item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _thumbnail(ref),
          const SizedBox(width: 8),
          Expanded(
            child: Text(item.kind == 'NOTE' ? (item.textBody ?? '') : 'Foto'),
          ),
          const SizedBox(width: 8),
          _syncIcon(),
        ],
      ),
    );
  }

  Widget _thumbnail(WidgetRef ref) {
    if (item.kind != 'PHOTO') return const SizedBox.shrink();
    if (item.photoBytes != null) {
      return Image.memory(
        item.photoBytes!,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
      );
    }
    if (item.contentUrl != null) {
      // NetworkImage's own `headers` map is enough for the bearer token here
      // — simpler than a custom Dio-backed ImageProvider, and the offline
      // map screen already established that a plain network fetch (no
      // redirect handling needed) is fine for this backend. Reads the base
      // URL through apiBaseUrlProvider (not apiBaseUrlFromEnvironment()
      // directly) so a test can override it with a fixed value instead of
      // requiring a real --dart-define.
      final token = ref.watch(sessionProvider)?.accessToken;
      final baseUrl = ref.watch(apiBaseUrlProvider);
      return Image(
        image: NetworkImage(
          '$baseUrl${item.contentUrl}',
          headers: token == null ? null : {'Authorization': 'Bearer $token'},
        ),
        width: 40,
        height: 40,
        fit: BoxFit.cover,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _syncIcon() {
    switch (item.syncState) {
      case PendingOpState.synced:
        return const Icon(Icons.cloud_done, size: 16, color: Colors.green);
      case PendingOpState.pending:
        return const Icon(Icons.cloud_upload, size: 16, color: Colors.orange);
      case PendingOpState.failed:
        return const Icon(Icons.error, size: 16, color: Colors.red);
      case PendingOpState.blocked:
        // Retry budget exhausted (Etapa 6 Ruling 6): needs manual action,
        // not just another automatic attempt.
        return const Icon(Icons.block, size: 16, color: Colors.red);
    }
  }
}
