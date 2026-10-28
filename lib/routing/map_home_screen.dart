import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show MapController, TileProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:route_monitor/appeals/released_stop_listener.dart';
import 'package:route_monitor/execution/conclude_sheet.dart';
import 'package:route_monitor/execution/in_progress_block.dart';
import 'package:route_monitor/gamification/full_card_trigger.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/monitoring/collection_banner.dart';
import 'package:route_monitor/monitoring/silence_banner.dart';
import 'package:route_monitor/routing/batch_allocation.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/routing/batch_sheet.dart';
import 'package:route_monitor/routing/campus_map.dart';
import 'package:route_monitor/routing/day_state_panels.dart';
import 'package:route_monitor/routing/home_notices.dart';
import 'package:route_monitor/routing/home_top_bar.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/stop_actions.dart';
import 'package:route_monitor/sync/sync_snackbars.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/map_sheet.dart';
import 'package:route_monitor/ui/snackbar_lane.dart';
import 'package:route_monitor/ui/sync_indicator.dart';

/// The building whose pin the worker tapped: the sheet lists its stops
/// alone and the other pins dim (redesign §6.3). Null shows the whole batch.
///
///     ref.read(selectedBuildingProvider.notifier).select('b2');
final selectedBuildingProvider = NotifierProvider<SelectedBuilding, String?>(
  SelectedBuilding.new,
);

class SelectedBuilding extends Notifier<String?> {
  @override
  String? build() => null;

  // A method, not a setter: reads as the action it is at the call site.
  // ignore: use_setters_to_change_properties
  void select(String buildingId) => state = buildingId;

  void clear() => state = null;
}

/// Below this the map's camera keeps clear of the top bar and the chips.
const double _topOverlayHeight = 150;

/// The home (`/rota`, redesign §6.2): the campus map edge to edge, the top
/// bar and chips floating over it, and the three-height sheet with the day's
/// state — the batch card and its stops while a batch is worked.
///
///     GoRoute(path: '/rota', builder: (_, _) => const MapHomeScreen())
class MapHomeScreen extends ConsumerStatefulWidget {
  const MapHomeScreen({super.key, this.mapTileProvider});

  /// Forwarded to [CampusMap] as its base-tile override. Null in production,
  /// so the map loads the bundled offline PMTiles. Widget tests inject a
  /// no-op provider here to keep vector_map_tiles' real tile pipeline (and
  /// the timers it schedules) out of `flutter_test`.
  final TileProvider? mapTileProvider;

  @override
  ConsumerState<MapHomeScreen> createState() => _MapHomeScreenState();
}

class _MapHomeScreenState extends ConsumerState<MapHomeScreen> {
  final MapController _map = MapController();
  final DraggableScrollableController _sheet = DraggableScrollableController();
  late final SnackbarLane _lane = SnackbarLane(
    contextOf: () => mounted ? context : null,
    sheet: _sheet,
  );
  LatLng? _workerPosition;

  /// The card last drawn, so the stamp listener finds the stop's building.
  BatchCard? _card;

  /// Where the lane is lent to the stop flows; kept to give it back.
  late final HomeSnackbarLaneSlot _laneSlot;

  @override
  void initState() {
    super.initState();
    _laneSlot = ref.read(homeSnackbarLaneProvider)..attach(_lane);
  }

  @override
  void dispose() {
    _laneSlot.detach(_lane);
    _map.dispose();
    _sheet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clearSelectionOnNewBatch();
    ref.listen<String?>(lastStampedStopProvider, (_, stopId) {
      if (stopId != null) _onStamped(stopId);
    });
    final dayAsync = ref.watch(myDayProvider);
    // Watched here so the automatic next-batch pull lives as long as the
    // screen does (spec §6.4), and its offline panel shows in the sheet.
    final nextBatch = ref.watch(batchAllocationProvider);
    final route = dayAsync.value?.route;
    final local = route == null
        ? const <String, LocalStopState>{}
        : watchLocalStates(ref, route);
    final card = _isWorked(route)
        ? buildBatchCard(route!, local, watchPendingSyncStops(ref, route))
        : null;
    _card = card;
    final selected = _selectedGroup(card, ref.watch(selectedBuildingProvider));
    return PopScope(
      canPop: selected == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        // The "Recorrer" snackbar when a late write finds its stop released
        // (spec §7.5).
        body: ReleasedStopListener(
          lane: _lane,
          child: SyncSnackbars(
            routeId: route?.id,
            lane: _lane,
            // The full card when the batch's last stamp lands, and the day
            // log (redesign §6.8).
            child: FullCardTrigger(
              card: card,
              routeId: route?.id,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    Positioned.fill(
                      child: _campusMap(route, card, selected, constraints),
                    ),
                    _topOverlay(route, local),
                    _myPositionButton(constraints.maxHeight),
                    _sheetFor(dayAsync, local, card, selected, nextBatch),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The day once read (a reload keeps showing it); while the first read
  /// fails — Riverpod retries it meanwhile — the error and "Tentar de novo";
  /// before it, the card's skeleton.
  Widget _sheetFor(
    AsyncValue<MyDay> dayAsync,
    Map<String, LocalStopState> local,
    BatchCard? card,
    BuildingGroup? selected,
    NextBatchState nextBatch,
  ) {
    final day = dayAsync.value;
    if (day != null) return _daySheet(day, local, card, selected, nextBatch);
    if (dayAsync.hasError) return _panelSheet(const LoadErrorPanel());
    return _panelSheet(const _CardSkeleton());
  }

  /// A new batch (or route) starts with the whole card: a selection left
  /// from the last batch would reopen in building mode — with no card — when
  /// the next batch is in the same building (the common case).
  void _clearSelectionOnNewBatch() {
    ref.listen<AsyncValue<MyDay>>(myDayProvider, (previous, next) {
      _forgetReleasedObservations(next.value?.route);
      final before = previous?.value?.route;
      final after = next.value?.route;
      if (before?.id == after?.id &&
          before?.currentBatch == after?.currentBatch) {
        return;
      }
      _clearSelection();
      _forgetStamp();
    });
  }

  /// A released stop is no longer the worker's: its observation draft goes.
  /// `invalidate` on a draft never opened is a no-op, so nothing is created.
  void _forgetReleasedObservations(RouteSummary? route) {
    for (final stop in route?.stops ?? const <RouteStopSummary>[]) {
      if (stop.status == 'RELEASED') {
        ref.invalidate(observationDraftProvider(stop.id));
      }
    }
  }

  /// A route whose batch is on the map: anything but paused or done.
  bool _isWorked(RouteSummary? route) =>
      route != null && route.status != 'PAUSED' && route.status != 'DONE';

  BuildingGroup? _selectedGroup(BatchCard? card, String? buildingId) {
    if (buildingId == null) return null;
    return card?.groups.where((g) => g.buildingId == buildingId).firstOrNull;
  }

  Widget _campusMap(
    RouteSummary? route,
    BatchCard? card,
    BuildingGroup? selected,
    BoxConstraints constraints,
  ) {
    final top = MediaQuery.paddingOf(context).top + _topOverlayHeight;
    return CampusMap(
      data: card == null
          ? RouteMapData(stops: const [], legs: const [])
          : buildRouteMapData(route!, card: card),
      groups: card?.groups ?? const [],
      selectedBuildingId: selected?.buildingId,
      workerPosition: _workerPosition,
      controller: _map,
      onPinTap: _selectBuilding,
      onMapTap: _clearSelection,
      // Wider on the right: each pin's label hangs to the right of its
      // circle.
      overlayPadding: EdgeInsets.fromLTRB(
        48,
        top,
        168,
        constraints.maxHeight * kMapSheetInitial + 24,
      ),
      tileProviderOverride: widget.mapTileProvider,
    );
  }

  /// The top bar, then the chips, inside the status-bar inset only.
  Widget _topOverlay(RouteSummary? route, Map<String, LocalStopState> local) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _topBar(route, local),
              // Renders itself only while a route is IN_PROGRESS (RNF11).
              const CollectionBanner(),
              // Renders itself only while the worker is silent (spec §7.3).
              const SilenceBanner(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(RouteSummary? route, Map<String, LocalStopState> local) {
    if (route == null) return const HomeTopBar();
    return HomeTopBar(
      route: route,
      done: dayDoneCount(route, local),
      total: route.stops.where((s) => s.status != 'RELEASED').length,
      syncSlot: route.status == 'IN_PROGRESS'
          ? RouteSyncIndicator(routeId: route.id)
          : null,
    );
  }

  /// "Minha posição", at the right just above the sheet; hidden while the
  /// sheet is open past half, where it would sit under the top bar.
  Widget _myPositionButton(double height) {
    return ListenableBuilder(
      listenable: _sheet,
      builder: (context, _) {
        final size = _sheet.isAttached ? _sheet.size : kMapSheetInitial;
        final p =
            Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
        return Positioned(
          right: 16,
          bottom: height * size + 16,
          child: Visibility(
            visible: size <= kMapSheetInitial + 0.05,
            child: FloatingActionButton(
              heroTag: null,
              backgroundColor: p.white,
              foregroundColor: p.ink,
              tooltip: AppStrings.myPositionTooltip,
              onPressed: _locateMe,
              child: const Icon(Icons.my_location),
            ),
          ),
        );
      },
    );
  }

  /// One state per moment of the day: no service, no route yet, a batch to
  /// work, points released (resume), nothing left.
  Widget _daySheet(
    MyDay day,
    Map<String, LocalStopState> local,
    BatchCard? card,
    BuildingGroup? selected,
    NextBatchState nextBatch,
  ) {
    final route = day.route;
    if (route == null) {
      return _panelSheet(
        day.serviceDay ? const StartDayPanel() : const NoServicePanel(),
      );
    }
    return switch (route.status) {
      'PAUSED' => _panelSheet(
        PausedPanel(releaseReason: route.latestReleaseReason),
      ),
      // Not final before the workday ends: points released later go back to
      // the pool, and "Verificar de novo" asks for them (spec §1).
      'DONE' => _panelSheet(DonePanel(doneToday: dayDoneCount(route, local))),
      _ => _batchSheet(route, card!, selected, nextBatch),
    };
  }

  Widget _panelSheet(Widget panel) => MapSheet(
    controller: _sheet,
    header: panel,
    body: const SizedBox.shrink(),
  );

  Widget _batchSheet(
    RouteSummary route,
    BatchCard card,
    BuildingGroup? selected,
    NextBatchState nextBatch,
  ) {
    final footer = canCheckIn(route.currentBatchStops)
        ? FilledButton.icon(
            onPressed: () => startCheckIn(context, ref, route),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text(AppStrings.scanQrButton),
          )
        : null;
    final inProgress = _inProgressBlock(route, card);
    if (selected != null) {
      return MapSheet(
        controller: _sheet,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?inProgress,
            BuildingHeader(group: selected),
          ],
        ),
        body: BuildingStops(route: route, group: selected),
        stickyFooter: footer,
      );
    }
    return MapSheet(
      controller: _sheet,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (nextBatch == NextBatchState.waitingForNetwork)
            const NextBatchOfflinePanel(),
          inProgress ?? NextStopRow(route: route, card: card),
        ],
      ),
      body: BatchOverview(route: route, card: card),
      stickyFooter: footer,
    );
  }

  /// The stop in progress, in place of "Próxima parada" (redesign §6.2);
  /// also over a selected building's list, so its photos and "Concluir"
  /// never hide behind a pin tap.
  Widget? _inProgressBlock(RouteSummary route, BatchCard card) {
    final slot = inProgressSlotOf(card);
    if (slot == null) return null;
    final stop = route.stops.firstWhere((s) => s.id == slot.stopId);
    return InProgressBlock(
      key: ValueKey('in-progress-${stop.id}'),
      route: route,
      stop: stop,
    );
  }

  /// After a written check-out (redesign §6.6): the map centres on the
  /// stop's building and the sheet comes to half height, where the card —
  /// and the stamp falling on it — shows.
  void _onStamped(String stopId) {
    final group = _card?.groups
        .where((g) => g.slots.any((slot) => slot.stopId == stopId))
        .firstOrNull;
    if (group != null) _map.move(group.position, _map.camera.zoom);
    if (!_sheet.isAttached) return;
    unawaited(
      _sheet.animateTo(
        kMapSheetInitial,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ),
    );
  }

  /// Pin tap: select the building, centre the map on it and bring the sheet
  /// to half height with that building's stops.
  void _selectBuilding(BuildingGroup group) {
    ref.read(selectedBuildingProvider.notifier).select(group.buildingId);
    _forgetStamp();
    _map.move(group.position, _map.camera.zoom);
    if (!_sheet.isAttached) return;
    unawaited(
      _sheet.animateTo(
        kMapSheetInitial,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ),
    );
  }

  void _clearSelection() => ref.read(selectedBuildingProvider.notifier).clear();

  /// A stamp falls once: a card rebuilt later (a pin tap, a new batch) must
  /// not replay it.
  void _forgetStamp() => ref.read(lastStampedStopProvider.notifier).clear();

  /// One GPS read, drawn as the worker's dot and centred on.
  Future<void> _locateMe() async {
    try {
      final here = await ref
          .read(locationServiceProvider)
          .getCurrentPosition(purpose: LocationPurpose.tracking);
      if (!mounted) return;
      final position = LatLng(here.latitude, here.longitude);
      setState(() => _workerPosition = position);
      _map.move(position, _map.camera.zoom);
      // Deliberately broad, like the check-in's GPS read: any failure means
      // "no position now", never a crash.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      _lane.show(SnackKind.action, AppStrings.routeLocationUnavailable);
    }
  }
}

/// While the day loads: the card's shape, empty (spec §6.10).
class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    return Container(
      height: 160,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.rule),
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}
