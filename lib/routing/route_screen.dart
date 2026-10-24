import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show TileProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:route_monitor/appeals/appeals_screen.dart';
import 'package:route_monitor/appeals/released_stop_listener.dart';
import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/execution/evidence_list.dart';
import 'package:route_monitor/execution/evidence_thumbnail.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/impediment_dialog.dart';
import 'package:route_monitor/execution/room_picker.dart';
import 'package:route_monitor/execution/room_resolution.dart';
import 'package:route_monitor/forms/form_providers.dart';
import 'package:route_monitor/forms/form_screen.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart' show PendingOpState;
import 'package:route_monitor/local/stop_progress_store.dart'
    show StopLocalStatus;
import 'package:route_monitor/monitoring/collection_banner.dart';
import 'package:route_monitor/monitoring/monitoring_providers.dart';
import 'package:route_monitor/monitoring/notifications_screen.dart';
import 'package:route_monitor/monitoring/silence_banner.dart';
import 'package:route_monitor/routing/batch_allocation.dart';
import 'package:route_monitor/routing/blocked_sync_screen.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/map_screen.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/start_route_panel.dart';
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
    final dayAsync = ref.watch(myDayProvider);
    // Watched here so the automatic next-batch pull lives as long as the
    // screen does (spec §6.4), and its offline banner shows below.
    final nextBatch = ref.watch(batchAllocationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.routeAppBarTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.privacy_tip_outlined),
            tooltip: AppStrings.myDataTitle,
            onPressed: () => context.push('/meus-dados'),
          ),
          const AppealsEntryButton(),
          const _NotificationsBell(),
        ],
      ),
      // The "Recorrer" snackbar when a late write finds its stop released
      // (spec §7.5).
      body: ReleasedStopListener(
        child: Column(
          children: [
            // Renders itself only while a route is IN_PROGRESS (RNF11).
            const CollectionBanner(),
            // Renders itself only while the worker is silent (spec §7.3).
            const SilenceBanner(),
            Expanded(
              child: dayAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) =>
                    const Center(child: Text(AppStrings.routeLoadError)),
                data: (day) => _buildDay(context, ref, day, nextBatch),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One state per moment of the day: no service, no route yet, a batch to
  /// work, points released (resume), nothing left.
  Widget _buildDay(
    BuildContext context,
    WidgetRef ref,
    MyDay day,
    NextBatchState nextBatch,
  ) {
    final route = day.route;
    if (route == null) {
      return day.serviceDay
          ? const StartRoutePanel()
          : const Center(child: Text(AppStrings.routeNotServiceDay));
    }
    return switch (route.status) {
      'PAUSED' => StartRoutePanel(
        paused: true,
        releaseReason: route.latestReleaseReason,
      ),
      'DONE' => const Center(child: Text(AppStrings.routeNoMorePoints)),
      _ => _buildBatch(context, ref, route, nextBatch),
    };
  }

  Widget _buildBatch(
    BuildContext context,
    WidgetRef ref,
    RouteSummary route,
    NextBatchState nextBatch,
  ) {
    final batchStops = route.currentBatchStops;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.routeBatchHeader(route.currentBatch, route.doneToday),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (nextBatch == NextBatchState.waitingForNetwork) ...[
            const SizedBox(height: 12),
            const _NextBatchOfflineBanner(),
          ],
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
            child: const Text(AppStrings.routeViewMapButton),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                // The whole batch, in order: a stop released since (an
                // impediment that reached the server, say) shows as such,
                // with no action left on it.
                for (final stop in route.stops)
                  if (stop.batchNumber == route.currentBatch)
                    stop.status == 'RELEASED'
                        ? _ReleasedStopTile(stop)
                        : _buildStopRow(context, ref, route, stop),
              ],
            ),
          ),
          if (_canCheckIn(batchStops))
            FilledButton(
              onPressed: () => _checkIn(context, ref, route),
              child: const Text(AppStrings.routeCheckInButton),
            ),
        ],
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
                builder: (_) =>
                    FormScreen(routeId: route.id, executionId: executionId),
              ),
            )
          : null,
      formIncomplete: formIncomplete,
      // PENDING too, not just IN_PROGRESS: a worker who can't even reach a
      // stop (access blocked → can't scan the QR → can't check in) must still
      // be able to signal it. Gated on an IN_PROGRESS route — the backend
      // rejects an impediment on a route that has not started (RF16). A DONE
      // stop is finished work and offers no such action.
      signalImpossibilityAction:
          route.status == 'IN_PROGRESS' &&
              (inProgress || effectiveStatus == 'PENDING')
          ? () => _signalImpossibility(context, ref, route, stop)
          : null,
    );
  }

  /// Opens [ImpedimentDialog] for a `PENDING` or `IN_PROGRESS` stop and, on a
  /// non-null result, enqueues it via `ExecutionRepository.reportImpediment`
  /// (spec RF16-RF17, alocação automática §7.1). Same shape as [_checkOut]:
  /// read the repo, call it, then a confirmation snackbar; the dialog stays
  /// ref-free (pure input collection).
  Future<void> _signalImpossibility(
    BuildContext context,
    WidgetRef ref,
    RouteSummary route,
    RouteStopSummary stop,
  ) async {
    final choice = await showDialog<ImpedimentChoice>(
      context: context,
      builder: (_) => const ImpedimentDialog(),
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
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AppStrings.routeImpedimentReported)),
    );
    // Once the impediment reached the server its stop comes back RELEASED;
    // reloading the day then is what lets an impediment on the last open
    // stop of the batch pull the next one. Offline, the pass is a no-op and
    // the reload serves the device snapshot.
    await ref.read(syncWorkerProvider).syncRoute(route.id);
    if (context.mounted) ref.invalidate(myDayProvider);
  }

  /// One route-level "Fazer check-in" action, not a per-stop button: the QR
  /// scan resolves which stop it belongs to (and can be ambiguous, Task 18).
  /// Checks for a `PENDING` stop specifically, not just "not DONE" — an
  /// `IN_PROGRESS` stop (already checked in, awaiting checkout, Task 18) has
  /// no `PENDING` candidate left on its floor, so scanning again would only
  /// get a confusing 422 FLOOR_NOT_ON_ROUTE from the backend. Only the
  /// current batch counts: it is the only one shown, on an IN_PROGRESS route.
  bool _canCheckIn(List<RouteStopSummary> batchStops) =>
      batchStops.any((stop) => stop.status == 'PENDING');

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
    final pendingStops = route.currentBatchStops
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
    ref.invalidate(myDayProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(content: Text(AppStrings.routeCheckInDone)),
      );
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
    // invalidate re-reads myDayProvider so the server view catches up too
    // — the "Concluir" button's visibility is status == 'IN_PROGRESS', and
    // the done-icon rendering in _StopTile takes over. The reload is also
    // what lets the batch controller see a finished batch and pull the next.
    ref.invalidate(myDayProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.routeCheckOutDone)),
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
      return await ref
          .read(locationServiceProvider)
          .getCurrentPosition(purpose: LocationPurpose.checkin);
      // Deliberately broad: GeolocatorLocationService can fail with a
      // StateError (permission denied), a platform exception, or a timeout
      // — all of them mean "proceed without GPS" here, never "block".
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(AppStrings.routeLocationUnavailableCheckIn),
          ),
        );
      }
      return null;
    }
  }
}

/// The app-bar bell that opens [NotificationsScreen], with a count badge while
/// there are unread notifications (RF49). A failed/loading count shows no badge
/// rather than a spinner in the header.
class _NotificationsBell extends ConsumerWidget {
  const _NotificationsBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider).asData?.value ?? 0;
    final button = IconButton(
      icon: const Icon(Icons.notifications_outlined),
      tooltip: AppStrings.routeNotificationsTooltip,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
      ),
    );
    if (unread == 0) return button;
    return Badge(label: Text('$unread'), child: button);
  }
}

/// "Conecte-se para receber mais pontos": the batch is finished on this
/// device but the next one could not be pulled; it is retried as soon as the
/// connection comes back (spec §6.4).
class _NextBatchOfflineBanner extends StatelessWidget {
  const _NextBatchOfflineBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: scheme.tertiaryContainer,
      child: Row(
        children: [
          Icon(Icons.wifi_off, color: scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppStrings.routeNextBatchOffline,
              style: TextStyle(color: scheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
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
                  AppStrings.routeSyncBlockedBanner,
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (status.pending > 0) {
      return Row(
        children: [
          Expanded(
            child: Text(AppStrings.routePendingSync(status.pending)),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () => _syncNow(ref),
            child: const Text(AppStrings.routeSyncNowButton),
          ),
        ],
      );
    }

    return const Row(
      children: [
        Icon(Icons.cloud_done, size: 16, color: Colors.green),
        SizedBox(width: 8),
        Text(AppStrings.routeAllSynced),
      ],
    );
  }

  /// Drains every route, then re-runs the next-batch pull: the outbox was
  /// what the pull was waiting for.
  Future<void> _syncNow(WidgetRef ref) async {
    final allocation = ref.read(batchAllocationProvider.notifier);
    await ref.read(syncWorkerProvider).syncAll();
    await allocation.retry();
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
      StopSyncChip.pending => (AppStrings.routeChipPending, Colors.orange),
      StopSyncChip.blocked => (AppStrings.routeChipBlocked, Colors.red),
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
  /// hide the action — RouteScreen passes a callback for a `PENDING` or
  /// `IN_PROGRESS` stop (never a DONE one). Same plain-callback pattern as
  /// [onConcluir]/[formFillAction] so this widget stays ref-free.
  final VoidCallback? signalImpossibilityAction;

  @override
  Widget build(BuildContext context) {
    final isDone = effectiveStatus == 'DONE';
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
            ],
          ),
          subtitle: leg == null ? null : Text(AppStrings.routeLeg(leg)),
          trailing: onConcluir == null && formFillAction == null
              ? null
              : TextButton(
                  onPressed: onConcluir,
                  child: const Text(AppStrings.routeConcludeButton),
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
                    child: const Text(AppStrings.routeFillFormButton),
                  ),
                if (formIncomplete)
                  const Text(AppStrings.routeFormIncompleteHint),
                if (signalImpossibilityAction != null)
                  TextButton(
                    onPressed: signalImpossibilityAction,
                    child: const Text(
                      AppStrings.routeSignalImpossibilityButton,
                    ),
                  ),
              ],
            ),
          ),
        ?evidenceSection,
      ],
    );
  }
}

/// A stop of the current batch the server released (back in the pool, spec
/// §7): its name and why, and no action — nothing on it is the worker's any
/// more.
class _ReleasedStopTile extends StatelessWidget {
  const _ReleasedStopTile(this.stop);

  final RouteStopSummary stop;

  @override
  Widget build(BuildContext context) {
    final reason = stop.releaseReason;
    return ListTile(
      enabled: false,
      leading: CircleAvatar(
        radius: 14,
        child: Text('${stop.orderIndex}', style: const TextStyle(fontSize: 12)),
      ),
      title: Text(stop.servicePointName),
      subtitle: Text(
        AppStrings.routeStopReleased(
          reason == null ? null : AppStrings.releaseReasonLabel(reason),
        ),
      ),
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
                label: const Text(AppStrings.routeAddPhotoButton),
              ),
              TextButton.icon(
                onPressed: () => _addNote(context, ref, query),
                icon: const Icon(Icons.note_add),
                label: const Text(AppStrings.routeAddNoteButton),
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
            error: (_, _) => const Text(AppStrings.routeEvidenceLoadError),
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
        ).showSnackBar(
          const SnackBar(content: Text(AppStrings.routePhotoAdded)),
        );
      }
      // Deliberately broad: a compression failure (StateError), a network
      // failure (DioException) or any other capture/upload error all map to
      // the same generic message here, same discipline as check-in/out.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.routePhotoAddError)),
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
          const SnackBar(content: Text(AppStrings.routeNoteAdded)),
        );
      }
      // Deliberately broad: same rationale as _addPhoto above.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(AppStrings.routeNoteAddError),
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
      title: const Text(AppStrings.formAddNoteDialogTitle),
      content: TextField(
        controller: controller,
        maxLength: 2000,
        maxLines: 4,
        autofocus: true,
        decoration: const InputDecoration(hintText: AppStrings.routeNoteHint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text(AppStrings.commonCancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text(AppStrings.commonSave),
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
          EvidenceThumbnail(item),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.kind == 'NOTE'
                  ? (item.textBody ?? '')
                  : AppStrings.routeEvidencePhotoLabel,
            ),
          ),
          const SizedBox(width: 8),
          _syncIcon(),
        ],
      ),
    );
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
