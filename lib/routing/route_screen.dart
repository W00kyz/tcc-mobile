import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show TileProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/execution/evidence_list.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/impediment_dialog.dart';
import 'package:route_monitor/execution/room_picker.dart';
import 'package:route_monitor/execution/room_resolution.dart';
import 'package:route_monitor/forms/form_providers.dart';
import 'package:route_monitor/forms/form_screen.dart';
import 'package:route_monitor/local/local_write_store.dart' show PendingOpState;
import 'package:route_monitor/local/stop_progress_store.dart'
    show StopLocalStatus;
import 'package:route_monitor/routing/blocked_sync_screen.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/map_screen.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A completed scan+GPS read, threaded from `_scanAndLocate` into a
/// check-in or check-out attempt.
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
                _SyncBanner(routeId: route.id),
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
                        _buildStopRow(context, ref, route, stop),
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

  /// Builds one stop's tile with its *effective* status (spec Ruling 5): a
  /// local `done` beats a local `inProgress` beats the server `stop.status`,
  /// so a not-yet-synced check-in/out shows on the tile immediately. The
  /// `ref.watch` lives here (a `ConsumerWidget`) so `_StopTile` itself stays
  /// a plain, ref-free `StatelessWidget`.
  Widget _buildStopRow(
    BuildContext context,
    WidgetRef ref,
    RouteSummary route,
    RouteStopSummary stop,
  ) {
    final progress = ref.watch(stopProgressForProvider(stop.id)).asData?.value;
    final effectiveStatus = switch (progress?.status) {
      StopLocalStatus.done => 'DONE',
      StopLocalStatus.inProgress => 'IN_PROGRESS',
      null => stop.status,
    };
    final syncChip =
        ref.watch(stopSyncChipProvider((route.id, stop.id))).asData?.value ??
        StopSyncChip.none;
    final inProgress = effectiveStatus == 'IN_PROGRESS';
    final stopForm = stop.form;
    final executionId = progress?.executionId;
    // Default `false` (not "unknown -> allow") while the completeness query
    // is still loading — a form-gated stop must never let check-out through
    // before we actually know the draft is complete.
    final formComplete =
        inProgress &&
        stopForm != null &&
        executionId != null &&
        (ref.watch(formDraftCompleteProvider(executionId)).asData?.value ??
            false);
    final formIncomplete = inProgress && stopForm != null && !formComplete;
    return _StopTile(
      stop: stop,
      effectiveStatus: effectiveStatus,
      syncChip: syncChip,
      onConcluir: inProgress && (stopForm == null || formComplete)
          ? () => _checkOut(context, ref, route, stop)
          : null,
      evidenceSection: inProgress
          ? _StopEvidenceSection(routeId: route.id, routeStopId: stop.id)
          : null,
      formFillAction: (inProgress && stopForm != null && executionId != null)
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FormScreen(executionId: executionId),
              ),
            )
          : null,
      formIncomplete: formIncomplete,
      signalImpossibilityAction: inProgress
          ? () => _signalImpossibility(context, ref, route, stop)
          : null,
    );
  }

  /// Opens [ImpedimentDialog] for an `IN_PROGRESS` stop and, on a non-null
  /// result, enqueues the report through `ExecutionRepository.reportImpediment`
  /// (spec RF16-RF17). The "resto da rota" switch is only offered when more
  /// than one `PENDING` stop still remains — with one or zero left there is no
  /// remainder worth signalling separately from this stop. Same shape as
  /// [_checkOut]: read the repo, call it, then a confirmation snackbar; the
  /// dialog stays ref-free (pure input collection).
  Future<void> _signalImpossibility(
    BuildContext context,
    WidgetRef ref,
    RouteSummary route,
    RouteStopSummary stop,
  ) async {
    final pendingCount = route.stops.where((s) => s.status == 'PENDING').length;
    final choice = await showDialog<ImpedimentChoice>(
      context: context,
      builder: (_) => ImpedimentDialog(showRemainderSwitch: pendingCount > 1),
    );
    if (choice == null || !context.mounted) return;

    await ref
        .read(executionRepositoryProvider)
        .reportImpediment(
          routeId: route.id,
          routeStopId: choice.scope == 'ROUTE_REMAINDER' ? null : stop.id,
          scope: choice.scope,
          reason: choice.reason,
          note: choice.note,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibilidade sinalizada.')),
      );
    }
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

    // Since Etapa 6 the room is resolved on the device, before the enqueue
    // (spec Ruling 4) — the check-in flow is offline-first and there is no
    // server 409 to lean on. `resolveRoomLocally` always lands on a concrete
    // route_stop_id: either it resolves one automatically or the field
    // worker picks from the pending stops (Ruling P8 — nothing is ever
    // enqueued with a null route_stop_id).
    final pendingStops = route.stops
        .where((stop) => stop.status == 'PENDING')
        .toList();
    final resolution = resolveRoomLocally(
      pendingStops: pendingStops,
      latitude: scan.coordinates?.latitude,
      longitude: scan.coordinates?.longitude,
    );

    final String routeStopId;
    switch (resolution) {
      case ResolvedRoom(routeStopId: final resolved):
        routeStopId = resolved;
      case AmbiguousRooms(:final candidates):
        final chosen = await showRoomPicker(context, candidates);
        // Dismissed without choosing → the check-in is cancelled, nothing is
        // written (Etapa 5's behaviour).
        if (chosen == null || !context.mounted) return;
        routeStopId = chosen.routeStopId;
    }

    // The repository only enqueues + writes local state now (spec Ruling 2):
    // it never throws `AmbiguousRoomException` or a network error, so there
    // is nothing to catch here.
    final executionId = await ref
        .read(executionRepositoryProvider)
        .checkIn(
          routeId: route.id,
          routeStopId: routeStopId,
          qrPayload: scan.rawValue,
          latitude: scan.coordinates?.latitude,
          longitude: scan.coordinates?.longitude,
        );
    // The FormSchema lives on the route's stop list, not on the execution
    // repository — snapshot the draft here, right after check-in succeeds
    // and before the stale `route.stops` view gets invalidated below.
    // `snapshotFrom` is idempotent (Task 11), so a retried check-in on the
    // same executionId never clobbers an answer already drafted.
    final checkedInStop = route.stops.firstWhere((s) => s.id == routeStopId);
    if (checkedInStop.form != null) {
      await ref
          .read(formDraftStoreProvider)
          .snapshotFrom(executionId, routeStopId, checkedInStop.form!);
    }
    ref.invalidate(myRoutesProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Check-in registrado.')));
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

    // Check-out is always per-stop — the UI already knows which IN_PROGRESS
    // stop it is concluding, so there is no room to resolve. The repository
    // only enqueues + writes local state (spec Ruling 2): no
    // `AmbiguousRoomException`, no network error, nothing to catch.
    await ref
        .read(executionRepositoryProvider)
        .checkOut(
          routeId: route.id,
          routeStopId: stop.id,
          qrPayload: scan.rawValue,
          latitude: scan.coordinates?.latitude,
          longitude: scan.coordinates?.longitude,
          checkoutIdempotencyKey: _uuid.v4(),
        );
    // A local check-out flips the stop to DONE now (spec Ruling 5); this
    // invalidate re-reads myRoutesProvider so the server view catches up too
    // — the "Concluir" button's visibility is status == 'IN_PROGRESS', and
    // the done-icon rendering in _StopTile takes over.
    ref.invalidate(myRoutesProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check-out registrado.')),
      );
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

/// The top-of-screen sync banner (spec Ruling 5). Renders nothing while the
/// status stream has not emitted yet (`.loading`/`.error`).
class _SyncBanner extends ConsumerWidget {
  const _SyncBanner({required this.routeId});

  final String routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(routeSyncStatusProvider(routeId)).asData?.value;
    if (status == null) return const SizedBox.shrink();

    if (status.state == RouteSyncState.blocked || status.blocked > 0) {
      final scheme = Theme.of(context).colorScheme;
      return InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BlockedSyncScreen(routeId: routeId),
          ),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: scheme.errorContainer,
          child: Row(
            children: [
              Icon(Icons.sync_problem, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sincronização bloqueada — toque para ver',
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (status.pending > 0) {
      final noun = status.pending == 1 ? 'ação' : 'ações';
      return Row(
        children: [
          Expanded(
            child: Text(
              '${status.pending} $noun aguardando sincronização',
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () => ref.read(syncWorkerProvider).syncAll(),
            child: const Text('Sincronizar agora'),
          ),
        ],
      );
    }

    return const Row(
      children: [
        Icon(Icons.cloud_done, size: 16, color: Colors.green),
        SizedBox(width: 8),
        Text('Tudo sincronizado'),
      ],
    );
  }
}

/// A compact inline chip flagging a stop's outbox state — amber "Pendente"
/// for a not-yet-synced row, red "Bloqueado" for a hard-blocked one. Matches
/// the evidence sync icons' colours (`Colors.orange` / `Colors.red`).
class _StopSyncChipLabel extends StatelessWidget {
  const _StopSyncChipLabel(this.chip);

  final StopSyncChip chip;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (chip) {
      StopSyncChip.pending => ('Pendente', Colors.orange),
      StopSyncChip.blocked => ('Bloqueado', Colors.red),
      StopSyncChip.none => ('', Colors.transparent),
    };
    return Chip(
      label: Text(label, style: TextStyle(color: color)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({
    required this.stop,
    required this.effectiveStatus,
    this.syncChip = StopSyncChip.none,
    this.onConcluir,
    this.evidenceSection,
    this.formFillAction,
    this.formIncomplete = false,
    this.signalImpossibilityAction,
  });

  final RouteStopSummary stop;

  /// The status actually rendered — a local optimistic override of
  /// `stop.status` (spec Ruling 5), resolved by `RouteScreen._buildStopRow`.
  final String effectiveStatus;

  /// Whether this stop has an unsynced (`pending`) or hard-`blocked` outbox
  /// row, surfaced as a small inline chip next to the stop name.
  final StopSyncChip syncChip;

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

  /// Pushes [FormScreen] for this stop's open execution, or null to hide the
  /// "Preencher formulário" action — set only for an `IN_PROGRESS` stop that
  /// carries a [RouteStopSummary.form]. Kept as a plain callback (same
  /// pattern as [onConcluir]) so this widget stays ref-free.
  final VoidCallback? formFillAction;

  /// True while this stop's form-gated check-out is blocked on an
  /// incomplete draft — shows a hint below the tile explaining why
  /// "Concluir" is disabled.
  final bool formIncomplete;

  /// Opens the "Sinalizar impossibilidade" dialog for this stop, or null to
  /// hide the action — RouteScreen passes a callback only for an `IN_PROGRESS`
  /// stop. Same plain-callback pattern as [onConcluir]/[formFillAction] so this
  /// widget stays ref-free.
  final VoidCallback? signalImpossibilityAction;

  @override
  Widget build(BuildContext context) {
    final isDone = effectiveStatus == 'DONE';
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
              if (syncChip != StopSyncChip.none)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _StopSyncChipLabel(syncChip),
                ),
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
          trailing: onConcluir == null && formFillAction == null
              ? null
              : TextButton(
                  onPressed: onConcluir,
                  child: const Text('Concluir'),
                ),
        ),
        if (formFillAction != null ||
            formIncomplete ||
            signalImpossibilityAction != null)
          Padding(
            padding: const EdgeInsets.only(left: 56, right: 16, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (formFillAction != null)
                  TextButton(
                    onPressed: formFillAction,
                    child: const Text('Preencher formulário'),
                  ),
                if (formIncomplete)
                  const Text('Preencha o formulário para concluir.'),
                if (signalImpossibilityAction != null)
                  TextButton(
                    onPressed: signalImpossibilityAction,
                    child: const Text('Sinalizar impossibilidade'),
                  ),
              ],
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
