import 'package:latlong2/latlong.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/routing/route_repository.dart';

/// How one stop of the batch card is drawn. `stamped` is a task finished on
/// its floor whose check-out has not been made; `impeded` is a task the
/// worker could not do (an impediment report), closed without being done.
enum SlotState { done, stamped, impeded, next, inProgress, pending, released }

/// What this device knows about a stop, from its local progress row.
class LocalStopState {
  const LocalStopState({required this.status, required this.updatedAt});

  factory LocalStopState.fromEntry(StopProgressEntry entry) =>
      LocalStopState(status: entry.status, updatedAt: entry.updatedAt);

  final StopLocalStatus status;
  final DateTime updatedAt;
}

class CardSlot {
  const CardSlot({
    required this.stopId,
    required this.state,
    required this.floorLabel,
    required this.stampedAt,
    required this.pendingSync,
    required this.releaseReason,
    required this.stampRotationDeg,
  });

  final String stopId;
  final SlotState state;
  final String floorLabel;

  /// When the stop was done (local check-out beats the server's `done_at`).
  final DateTime? stampedAt;
  final bool pendingSync;
  final String? releaseReason;
  final double stampRotationDeg;
}

class BuildingGroup {
  const BuildingGroup({
    required this.buildingId,
    required this.buildingName,
    required this.slots,
    required this.position,
  });

  final String buildingId;
  final String buildingName;
  final List<CardSlot> slots;

  /// Mean of the group's stop coordinates.
  final LatLng position;

  int get done => slots.where((s) => s.state == SlotState.done).length;

  /// Released stops are not counted: they went back to the pool.
  int get total => slots.where((s) => s.state != SlotState.released).length;

  /// Impeded stops count as closed: nothing more can be done about them.
  int get impeded => slots.where((s) => s.state == SlotState.impeded).length;

  bool get complete => total > 0 && done + impeded == total;
}

class BatchCard {
  const BatchCard({required this.batchNumber, required this.groups});

  final int batchNumber;
  final List<BuildingGroup> groups;

  int get done => groups.fold(0, (sum, g) => sum + g.done);
  int get total => groups.fold(0, (sum, g) => sum + g.total);
  int get released => groups
      .expand((g) => g.slots)
      .where((s) => s.state == SlotState.released)
      .length;
  bool get complete => total > 0 && done == total;

  CardSlot? get next => groups
      .expand((g) => g.slots)
      .where((s) => s.state == SlotState.next)
      .firstOrNull;
}

/// Builds the card of the route's current batch: stops grouped by building in
/// the order each building first appears.
///
///     final card = buildBatchCard(route, local, pendingSyncStopIds);
BatchCard buildBatchCard(
  RouteSummary route,
  Map<String, LocalStopState> local,
  Set<String> pendingSyncStopIds,
) => _buildCardFor(
  route,
  route.currentBatch,
  local,
  pendingSyncStopIds,
  marksNext: true,
);

/// One card per batch present in [route]'s stops, in ascending batch order
/// — the map sheet's carousel. Only the current batch's card has a `next`
/// slot: an earlier batch is finished work, and a later one is not the
/// worker's to start yet.
///
///     final cards = buildBatchCards(route, local, pendingSyncStopIds);
List<BatchCard> buildBatchCards(
  RouteSummary route,
  Map<String, LocalStopState> local,
  Set<String> pendingSyncStopIds,
) {
  final batches = {for (final stop in route.stops) stop.batchNumber}.toList()
    ..sort();
  return [
    for (final batch in batches)
      _buildCardFor(
        route,
        batch,
        local,
        pendingSyncStopIds,
        marksNext: batch == route.currentBatch,
      ),
  ];
}

/// The card of [batchNumber]: its stops in route order, grouped by building
/// in the order each building first appears. With [marksNext], the first
/// open stop is the `next` slot.
BatchCard _buildCardFor(
  RouteSummary route,
  int batchNumber,
  Map<String, LocalStopState> local,
  Set<String> pendingSyncStopIds, {
  required bool marksNext,
}) {
  final stops = route.stops.where((s) => s.batchNumber == batchNumber).toList()
    ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

  var nextAssigned = !marksNext;
  final slotsByBuilding = <String, List<CardSlot>>{};
  final stopsByBuilding = <String, List<RouteStopSummary>>{};
  for (final stop in stops) {
    final slot = _slotOf(
      stop,
      local[stop.id],
      pendingSyncStopIds,
      mayBeNext: !nextAssigned,
    );
    if (slot.state == SlotState.next) nextAssigned = true;
    slotsByBuilding.putIfAbsent(stop.buildingId, () => []).add(slot);
    stopsByBuilding.putIfAbsent(stop.buildingId, () => []).add(stop);
  }
  return BatchCard(
    batchNumber: batchNumber,
    groups: _groupsOf(stopsByBuilding, slotsByBuilding),
  );
}

CardSlot _slotOf(
  RouteStopSummary stop,
  LocalStopState? localState,
  Set<String> pendingSyncStopIds, {
  required bool mayBeNext,
}) {
  final localDone = localState?.status == StopLocalStatus.done;
  final state = _slotStateOf(stop, localState, mayBeNext: mayBeNext);
  return CardSlot(
    stopId: stop.id,
    state: state,
    floorLabel: stop.floorLabel,
    // When the stop was done: the local check-out beats the server's.
    stampedAt: state != SlotState.done
        ? null
        : (localDone ? localState!.updatedAt : stop.doneAt),
    pendingSync: pendingSyncStopIds.contains(stop.id),
    releaseReason: stop.releaseReason,
    stampRotationDeg: stampRotationFor(stop.id),
  );
}

/// The stop's effective state: released, then a local or server done, then
/// a local stamp, then a local or server in-progress; otherwise the first
/// open stop is `next` when [mayBeNext], and the rest are pending.
SlotState _slotStateOf(
  RouteStopSummary stop,
  LocalStopState? localState, {
  required bool mayBeNext,
}) {
  if (stop.status == 'RELEASED') return SlotState.released;
  if (localState?.status == StopLocalStatus.done || stop.status == 'DONE') {
    return SlotState.done;
  }
  if (localState?.status == StopLocalStatus.stamped) return SlotState.stamped;
  if (localState?.status == StopLocalStatus.inProgress ||
      stop.status == 'IN_PROGRESS') {
    return SlotState.inProgress;
  }
  return mayBeNext ? SlotState.next : SlotState.pending;
}

List<BuildingGroup> _groupsOf(
  Map<String, List<RouteStopSummary>> stopsByBuilding,
  Map<String, List<CardSlot>> slotsByBuilding,
) => [
  for (final entry in stopsByBuilding.entries)
    BuildingGroup(
      buildingId: entry.key,
      buildingName: entry.value.first.buildingName,
      slots: slotsByBuilding[entry.key]!,
      position: LatLng(
        _mean(entry.value.map((s) => s.latitude)),
        _mean(entry.value.map((s) => s.longitude)),
      ),
    ),
];

double _mean(Iterable<double> values) =>
    values.fold<double>(0, (a, b) => a + b) / values.length;

/// Deterministic tilt in [-9, 9] degrees for a stop's stamp. FNV-1a, not
/// `String.hashCode`, which is not stable across runs.
double stampRotationFor(String stopId) {
  var hash = 0x811c9dc5;
  for (final unit in stopId.codeUnits) {
    hash = ((hash ^ (unit & 0xff)) * 0x01000193) & 0xffffffff;
    if (unit > 0xff) {
      hash = ((hash ^ (unit >> 8)) * 0x01000193) & 0xffffffff;
    }
  }
  return ((hash % 19) - 9).toDouble();
}

/// Stops done today: those the server reports `DONE` plus those done on this
/// device that the server does not know yet.
int dayDoneCount(RouteSummary route, Map<String, LocalStopState> local) => route
    .stops
    .where(
      (s) =>
          s.status == 'DONE' ||
          (s.status != 'RELEASED' &&
              local[s.id]?.status == StopLocalStatus.done),
    )
    .length;
