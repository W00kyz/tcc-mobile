import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show MapController, TileProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:route_monitor/appeals/released_stop_listener.dart';
import 'package:route_monitor/execution/task_dialog.dart';
import 'package:route_monitor/gamification/full_card_trigger.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/monitoring/collection_banner.dart';
import 'package:route_monitor/monitoring/silence_banner.dart';
import 'package:route_monitor/routing/batch_allocation.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/routing/building_card_model.dart';
import 'package:route_monitor/routing/building_sheet.dart';
import 'package:route_monitor/routing/campus_map.dart';
import 'package:route_monitor/routing/day_local_state.dart';
import 'package:route_monitor/routing/day_state_panels.dart';
import 'package:route_monitor/routing/floor_actions.dart';
import 'package:route_monitor/routing/home_notices.dart';
import 'package:route_monitor/routing/home_top_bar.dart';
import 'package:route_monitor/routing/live_approach.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/released_cleanup.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/selected_building.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_snackbars.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/floor_card.dart';
import 'package:route_monitor/ui/map_sheet.dart';
import 'package:route_monitor/ui/snackbar_lane.dart';
import 'package:route_monitor/ui/sync_indicator.dart';

/// How far above the system bar "Minha posição" and the snackbars sit when
/// the building sheet is hidden.
const double _hiddenSheetReach = 24;

/// Below this the map's camera keeps clear of the top bar and the chips.
const double _topOverlayHeight = 150;

/// The home (`/rota`, redesign §6.2): the campus map edge to edge, the top
/// bar and chips floating over it, and the three-height sheet with the day's
/// state — the selected building's floor card and its scan button while the
/// route is worked (no sheet until a pin is tapped, and the worker can hide
/// it again); before it starts (or while paused), only the start button.
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
    startBarReach: _bottomReach,
  );

  /// The start bar shown in place of a sheet, as last built; null while a
  /// sheet shows.
  StartBarContent? _startBar;

  /// A route is worked but no building is selected: no sheet, the map whole.
  /// As last built, like [_startBar].
  bool _sheetHidden = false;

  /// The pins last drawn, so the stamp listener finds the stop's building.
  List<DayBuilding> _buildings = const [];

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
    ref
      ..listen<String?>(lastStampedStopProvider, (_, stopId) {
        if (stopId != null) _onStamped(stopId);
      })
      ..listen<String?>(lastImpededStopProvider, (_, stopId) {
        if (stopId != null) _onStamped(stopId);
      });
    final dayAsync = ref.watch(myDayProvider);
    _startBar = startBarOf(dayAsync.value);
    // Watched here so the automatic next-batch pull lives as long as the
    // screen does (spec §6.4), and its offline panel shows in the sheet.
    final nextBatch = ref.watch(batchAllocationProvider);
    final route = dayAsync.value?.route;
    final local = route == null
        ? const <String, LocalStopState>{}
        : watchLocalStates(ref, route);
    final pendingSync = _isWorked(route)
        ? watchPendingSyncStops(ref, route!)
        : const <String>{};
    // The batch's card still feeds the full card and the day log (the
    // gamification counts by batch).
    final card = _isWorked(route)
        ? buildBatchCard(route!, local, pendingSync)
        : null;
    final buildings = _buildings = _dayBuildings(route, local, pendingSync);
    final selectedId = ref.watch(selectedBuildingProvider);
    final pinned = buildings.any((b) => b.buildingId == selectedId)
        ? selectedId
        : null;
    _sheetHidden =
        buildings.isNotEmpty &&
        pinned == null &&
        nextBatch != NextBatchState.waitingForNetwork;
    return PopScope(
      canPop: pinned == null,
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
                      child: _campusMap(
                        route,
                        card,
                        buildings,
                        pinned,
                        constraints,
                      ),
                    ),
                    _topOverlay(route, local),
                    _myPositionButton(constraints.maxHeight),
                    if (!_sheetHidden)
                      _sheetFor(dayAsync, local, buildings, pinned, nextBatch),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// No sheet over the map: the start bar shows instead, or the building
  /// sheet is hidden.
  bool get _noSheet => _startBar != null || _sheetHidden;

  /// The day once read (a reload keeps showing it); while the first read
  /// fails — Riverpod retries it meanwhile — the error and "Tentar de novo";
  /// before it, the card's skeleton.
  Widget _sheetFor(
    AsyncValue<MyDay> dayAsync,
    Map<String, LocalStopState> local,
    List<DayBuilding> buildings,
    String? pinned,
    NextBatchState nextBatch,
  ) {
    final day = dayAsync.value;
    if (day != null) {
      return _daySheet(day, local, buildings, pinned, nextBatch);
    }
    if (dayAsync.hasError) return _panelSheet(const LoadErrorPanel());
    return _panelSheet(const CardSkeleton());
  }

  /// What the map, "Minha posição" and the snackbars clear at the bottom
  /// when no sheet shows: the start bar (with its caption, if any), or just
  /// the system bar and some air once the worker hid the building sheet.
  double _bottomReach(BuildContext context) {
    if (_startBar != null) {
      return startBarHeight(context, withCaption: _startBar?.caption != null);
    }
    return MediaQuery.paddingOf(context).bottom + _hiddenSheetReach;
  }

  /// A new batch (or route) starts with no building highlighted: a
  /// selection left from the last batch would still dim the pins and
  /// underline a building when the next batch is in the same one (the
  /// common case).
  void _clearSelectionOnNewBatch() {
    ref.listen<AsyncValue<MyDay>>(myDayProvider, (previous, next) {
      forgetReleasedStops(ref, next.value?.route);
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

  /// A route whose batch is on the map: anything but paused or done.
  bool _isWorked(RouteSummary? route) =>
      route != null && route.status != 'PAUSED' && route.status != 'DONE';

  /// The day's pins: every batch's buildings, numbered in route order, while
  /// a batch is on the map. The impeded stops come from the local outbox, so
  /// an impediment greys its pin at once, offline too.
  List<DayBuilding> _dayBuildings(
    RouteSummary? route,
    Map<String, LocalStopState> local,
    Set<String> pendingSync,
  ) {
    if (!_isWorked(route)) return const [];
    final impeded =
        ref.watch(impededStopIdsProvider(route!.id)).value ?? const <String>{};
    return buildDayBuildings(route, local, impeded, pendingSync);
  }

  Widget _campusMap(
    RouteSummary? route,
    BatchCard? card,
    List<DayBuilding> buildings,
    String? selectedBuildingId,
    BoxConstraints constraints,
  ) {
    final top = MediaQuery.paddingOf(context).top + _topOverlayHeight;
    return CampusMap(
      data: card == null
          ? RouteMapData(stops: const [], legs: const [])
          : buildRouteMapData(
              route!,
              buildings: buildings,
              approach: watchLiveApproach(ref, route, buildings),
              worker: ref.watch(workerPositionProvider),
            ),
      buildings: buildings,
      selectedBuildingId: selectedBuildingId,
      workerPosition: ref.watch(workerPositionProvider),
      controller: _map,
      onPinTap: _selectBuilding,
      onMapTap: _clearSelection,
      // Symmetric: each pin's name is centred above its teardrop, so it
      // overhangs both sides equally.
      overlayPadding: EdgeInsets.fromLTRB(
        48,
        top,
        48,
        _noSheet
            ? _bottomReach(context) + 24
            : constraints.maxHeight * kMapSheetInitial + 24,
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

  /// "Minha posição", at the right just above the sheet (or the start bar,
  /// or the bottom edge once the sheet is hidden); hidden while the sheet is
  /// open past half, where it would sit under the top bar.
  Widget _myPositionButton(double height) {
    final hasSheet = !_noSheet;
    return ListenableBuilder(
      listenable: _sheet,
      builder: (context, _) {
        final size = _sheet.isAttached ? _sheet.size : kMapSheetInitial;
        final p =
            Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
        final above = hasSheet ? height * size : _bottomReach(context);
        return Positioned(
          right: 16,
          bottom: above + 16,
          child: Visibility(
            visible: !hasSheet || size <= kMapSheetInitial + 0.05,
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

  /// One state per moment of the day: no service, no route yet or paused
  /// (the start bar, no sheet), a route to work, nothing left.
  Widget _daySheet(
    MyDay day,
    Map<String, LocalStopState> local,
    List<DayBuilding> buildings,
    String? pinned,
    NextBatchState nextBatch,
  ) {
    final start = _startBar;
    if (start != null) {
      return StartDayBar(label: start.label, caption: start.caption);
    }
    final route = day.route;
    if (route == null) return _panelSheet(const NoServicePanel());
    return switch (route.status) {
      // Not final before the workday ends: points released later go back to
      // the pool, and "Verificar de novo" asks for them (spec §1).
      'DONE' => _panelSheet(DonePanel(doneToday: dayDoneCount(route, local))),
      _ => _buildingSheet(route, buildings, pinned, nextBatch),
    };
  }

  Widget _panelSheet(Widget panel) => MapSheet(
    controller: _sheet,
    header: panel,
    body: const SizedBox.shrink(),
  );

  /// The route being worked: the tapped building's header, floor card and
  /// scan button. With no building tapped the build leaves the sheet out
  /// ([_sheetHidden]), bar the next-batch offline notice, which has no
  /// building to hang on.
  Widget _buildingSheet(
    RouteSummary route,
    List<DayBuilding> buildings,
    String? pinned,
    NextBatchState nextBatch,
  ) {
    final offline = nextBatch == NextBatchState.waitingForNetwork;
    final building = buildings.where((b) => b.buildingId == pinned).firstOrNull;
    if (building == null) {
      return _panelSheet(
        offline ? const NextBatchOfflinePanel() : const CardSkeleton(),
      );
    }
    return MapSheet(
      controller: _sheet,
      onDismissed: _clearSelection,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (offline) const NextBatchOfflinePanel(),
          BuildingSheetHeader(
            building: building,
            selected:
                building.buildingId != nextBuilding(buildings)?.buildingId,
          ),
        ],
      ),
      body: _floorCard(route, building),
      stickyFooter: scanFooterFor(route, buildings, building),
    );
  }

  Widget _floorCard(RouteSummary route, DayBuilding building) => FloorCard(
    key: ValueKey('floor-card-of-${building.buildingId}'),
    building: building,
    onSlotTap: (slot, _) => showSlotTask(context, ref, route, slot),
    animateStopId: ref.watch(lastStampedStopProvider),
    animateImpededStopId: ref.watch(lastImpededStopProvider),
  );

  /// After a stamp (done or impossible, redesign §6.6): the stop's building
  /// is selected — a building tapped before does not hold the sheet (final
  /// review I-5), and a hidden sheet comes back — the map centres on it and
  /// the sheet comes to half height, where its floor card, and the stamp
  /// falling on it, show.
  void _onStamped(String stopId) {
    final building = _buildings
        .where(
          (b) => b.floors.any((f) => f.slots.any((s) => s.stopId == stopId)),
        )
        .firstOrNull;
    if (building == null) return _clearSelection();
    ref.read(selectedBuildingProvider.notifier).select(building.buildingId);
    _map.move(building.position, _map.camera.zoom);
    _sheetToHalf();
  }

  /// Pin tap: select the building, centre the map on it and bring the sheet
  /// to half height, showing that building's floor card.
  void _selectBuilding(DayBuilding building) {
    ref.read(selectedBuildingProvider.notifier).select(building.buildingId);
    _forgetStamp();
    _map.move(building.position, _map.camera.zoom);
    _sheetToHalf();
  }

  /// Brings an open sheet to half height; a sheet still to be built starts
  /// there.
  void _sheetToHalf() {
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
  void _forgetStamp() {
    ref.read(lastStampedStopProvider.notifier).clear();
    ref.read(lastImpededStopProvider.notifier).clear();
  }

  /// One GPS read, drawn as the worker's dot and centred on.
  Future<void> _locateMe() async {
    try {
      final here = await ref
          .read(locationServiceProvider)
          .getCurrentPosition(purpose: LocationPurpose.tracking);
      if (!mounted) return;
      final position = LatLng(here.latitude, here.longitude);
      ref.read(workerPositionProvider.notifier).update(position);
      _map.move(position, _map.camera.zoom);
      // Deliberately broad, like the check-in's GPS read: any failure means
      // "no position now", never a crash.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      _lane.show(SnackKind.action, AppStrings.routeLocationUnavailable);
    }
  }
}
