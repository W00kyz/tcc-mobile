import 'package:latlong2/latlong.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/routing/route_repository.dart';

/// One floor of a building: the tasks of the day on it, in route order.
class FloorRow {
  const FloorRow({
    required this.floorId,
    required this.label,
    required this.slots,
  });

  /// Null for a snapshot cached before the backend sent floor ids.
  final String? floorId;
  final String label;
  final List<CardSlot> slots;

  bool _has(SlotState state) => slots.any((s) => s.state == state);

  /// A check-in is open from the floor's first scan until its exit scan, so a
  /// floor whose tasks are all stamped still has one.
  bool get hasOpenCheckIn =>
      _has(SlotState.inProgress) || _has(SlotState.stamped);

  /// Some task was stamped and none is still being worked. Pending and next
  /// slots are ignored: a later batch's stop on this floor is never checked
  /// in, so it must not block the exit.
  bool get readyForCheckOut =>
      _has(SlotState.stamped) && !_has(SlotState.inProgress);
}

/// A building of the day, numbered by its place in the route.
class DayBuilding {
  const DayBuilding({
    required this.buildingId,
    required this.name,
    required this.number,
    required this.position,
    required this.floors,
  });

  final String buildingId;
  final String name;

  /// 1..n among the buildings with something to show.
  final int number;

  /// Mean of the coordinates of the building's stops.
  final LatLng position;
  final List<FloorRow> floors;

  Iterable<CardSlot> get _slots => floors.expand((f) => f.slots);

  /// Released slots went back to the pool; they count for nothing.
  int get _counted => _slots.where((s) => s.state != SlotState.released).length;

  int get _closed => _slots
      .where((s) => s.state == SlotState.done || s.state == SlotState.impeded)
      .length;

  /// Every task is done or impeded.
  bool get complete => _counted > 0 && _closed == _counted;

  /// Tasks still to be done or checked out.
  int get openTasks => _counted - _closed;
}

/// The day's buildings, floors and task slots, across every batch. A building
/// with no visible slot (every stop released, none for an impediment) is
/// dropped before numbering.
///
///     final buildings = buildDayBuildings(route, local, impeded, pending);
List<DayBuilding> buildDayBuildings(
  RouteSummary route,
  Map<String, LocalStopState> local,
  Set<String> impededStopIds,
  Set<String> pendingSyncStopIds,
) {
  final nextId = _nextStopId(route, local, impededStopIds);
  CardSlot slotOf(RouteStopSummary stop) => _slotOf(
    stop,
    local[stop.id],
    impededStopIds,
    pendingSyncStopIds,
    isNext: stop.id == nextId,
  );
  final visible = _stopsByBuilding(route)
      .where((stops) => stops.any((s) => !_isReleased(s, impededStopIds)))
      .toList();
  return [
    for (final (index, stops) in visible.indexed)
      _buildingOf(stops, index + 1, impededStopIds, slotOf),
  ];
}

/// The building holding the `next` slot, or null when nothing is open.
DayBuilding? nextBuilding(List<DayBuilding> buildings) => buildings
    .where(
      (b) => b.floors.any((f) => f.slots.any((s) => s.state == SlotState.next)),
    )
    .firstOrNull;

/// The floor of [building] with a check-in open, if any.
FloorRow? openFloorOf(DayBuilding building) =>
    building.floors.where((f) => f.hasOpenCheckIn).firstOrNull;

/// The stops the worker can check in to on [floorId]: `PENDING` ones of the
/// current batch, in route order.
List<RouteStopSummary> checkInCandidates(RouteSummary route, String floorId) =>
    _sortedStops(route)
        .where(
          (s) =>
              s.batchNumber == route.currentBatch &&
              s.status == 'PENDING' &&
              s.floorId == floorId,
        )
        .toList();

List<RouteStopSummary> _sortedStops(RouteSummary route) =>
    route.stops.toList()..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

/// Stops grouped by building, buildings in order of their first stop.
Iterable<List<RouteStopSummary>> _stopsByBuilding(RouteSummary route) {
  final byBuilding = <String, List<RouteStopSummary>>{};
  for (final stop in _sortedStops(route)) {
    byBuilding.putIfAbsent(stop.buildingId, () => []).add(stop);
  }
  return byBuilding.values;
}

DayBuilding _buildingOf(
  List<RouteStopSummary> stops,
  int number,
  Set<String> impededStopIds,
  CardSlot Function(RouteStopSummary) slotOf,
) {
  final shown = stops.where((s) => !_isReleased(s, impededStopIds)).toList();
  return DayBuilding(
    buildingId: stops.first.buildingId,
    name: stops.first.buildingName,
    number: number,
    position: LatLng(
      _mean(shown.map((s) => s.latitude)),
      _mean(shown.map((s) => s.longitude)),
    ),
    floors: _floorsOf(stops, shown, slotOf),
  );
}

/// Floors in order of their first stop; a floor with only released stops is
/// left out. Grouped by floor id, or by label for a snapshot without ids.
List<FloorRow> _floorsOf(
  List<RouteStopSummary> stops,
  List<RouteStopSummary> shown,
  CardSlot Function(RouteStopSummary) slotOf,
) {
  final keep = shown.map(_floorKey).toSet();
  final byFloor = <String, List<RouteStopSummary>>{};
  for (final stop in stops.where((s) => keep.contains(_floorKey(s)))) {
    byFloor.putIfAbsent(_floorKey(stop), () => []).add(stop);
  }
  return [
    for (final floorStops in byFloor.values)
      FloorRow(
        floorId: floorStops.first.floorId,
        label: floorStops.first.floorLabel,
        slots: floorStops.map(slotOf).toList(),
      ),
  ];
}

String _floorKey(RouteStopSummary stop) =>
    stop.floorId != null ? 'id:${stop.floorId}' : 'label:${stop.floorLabel}';

bool _isImpeded(RouteStopSummary stop, Set<String> impededStopIds) =>
    impededStopIds.contains(stop.id) ||
    (stop.status == 'RELEASED' && stop.releaseReason == 'IMPEDIMENT');

bool _isReleased(RouteStopSummary stop, Set<String> impededStopIds) =>
    stop.status == 'RELEASED' && !_isImpeded(stop, impededStopIds);

/// The first stop of the current batch that no other state claims.
String? _nextStopId(
  RouteSummary route,
  Map<String, LocalStopState> local,
  Set<String> impededStopIds,
) => _sortedStops(route)
    .where(
      (s) =>
          s.batchNumber == route.currentBatch &&
          _closedOrActiveState(s, local[s.id], impededStopIds) == null,
    )
    .firstOrNull
    ?.id;

CardSlot _slotOf(
  RouteStopSummary stop,
  LocalStopState? localState,
  Set<String> impededStopIds,
  Set<String> pendingSyncStopIds, {
  required bool isNext,
}) {
  final state =
      _closedOrActiveState(stop, localState, impededStopIds) ??
      (isNext ? SlotState.next : SlotState.pending);
  final localDone = localState?.status == StopLocalStatus.done;
  return CardSlot(
    stopId: stop.id,
    state: state,
    floorLabel: stop.floorLabel,
    stampedAt: state != SlotState.done
        ? null
        : (localDone ? localState!.updatedAt : stop.doneAt),
    pendingSync: pendingSyncStopIds.contains(stop.id),
    releaseReason: stop.releaseReason,
    stampRotationDeg: stampRotationFor(stop.id),
  );
}

/// Every state that does not depend on the stop's place in the queue, in
/// precedence order: impeded, released, done, stamped, in progress. Null for
/// an open stop, which is `next` or `pending`.
SlotState? _closedOrActiveState(
  RouteStopSummary stop,
  LocalStopState? localState,
  Set<String> impededStopIds,
) {
  if (_isImpeded(stop, impededStopIds)) return SlotState.impeded;
  if (stop.status == 'RELEASED') return SlotState.released;
  final localStatus = localState?.status;
  if (localStatus == StopLocalStatus.done || stop.status == 'DONE') {
    return SlotState.done;
  }
  if (localStatus == StopLocalStatus.stamped) return SlotState.stamped;
  if (localStatus == StopLocalStatus.inProgress ||
      stop.status == 'IN_PROGRESS') {
    return SlotState.inProgress;
  }
  return null;
}

double _mean(Iterable<double> values) =>
    values.fold<double>(0, (a, b) => a + b) / values.length;
