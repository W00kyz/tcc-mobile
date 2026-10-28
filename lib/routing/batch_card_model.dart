import 'package:latlong2/latlong.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/routing/route_repository.dart';

/// How one stop of the batch card is drawn.
enum SlotState { done, next, inProgress, pending, released }

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

  bool get complete => total > 0 && done == total;
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
BatchCard buildBatchCard(
  RouteSummary route,
  Map<String, LocalStopState> local,
  Set<String> pendingSyncStopIds,
) {
  final stops =
      route.stops.where((s) => s.batchNumber == route.currentBatch).toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

  var nextAssigned = false;
  final slotsByBuilding = <String, List<CardSlot>>{};
  final stopsByBuilding = <String, List<RouteStopSummary>>{};
  for (final stop in stops) {
    final localState = local[stop.id];
    final SlotState state;
    DateTime? stampedAt;
    if (stop.status == 'RELEASED') {
      state = SlotState.released;
    } else if (localState?.status == StopLocalStatus.done ||
        stop.status == 'DONE') {
      state = SlotState.done;
      stampedAt = localState?.status == StopLocalStatus.done
          ? localState!.updatedAt
          : stop.doneAt;
    } else if (localState?.status == StopLocalStatus.inProgress ||
        stop.status == 'IN_PROGRESS') {
      state = SlotState.inProgress;
    } else if (!nextAssigned) {
      nextAssigned = true;
      state = SlotState.next;
    } else {
      state = SlotState.pending;
    }
    slotsByBuilding
        .putIfAbsent(stop.buildingId, () => [])
        .add(
          CardSlot(
            stopId: stop.id,
            state: state,
            floorLabel: stop.floorLabel,
            stampedAt: stampedAt,
            pendingSync: pendingSyncStopIds.contains(stop.id),
            releaseReason: stop.releaseReason,
            stampRotationDeg: stampRotationFor(stop.id),
          ),
        );
    stopsByBuilding.putIfAbsent(stop.buildingId, () => []).add(stop);
  }

  final groups = [
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
  return BatchCard(batchNumber: route.currentBatch, groups: groups);
}

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
