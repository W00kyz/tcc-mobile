import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/routing/building_card_model.dart';
import 'package:route_monitor/routing/route_repository.dart';

RouteStopSummary _stop(
  String id,
  int order,
  String buildingId, {
  String floorLabel = 'Térreo',
  String? floorId = 'f-0',
  String status = 'PENDING',
  int batch = 1,
  String? releaseReason,
  double lat = -7.2,
  double lng = -35.9,
}) => RouteStopSummary(
  id: id,
  orderIndex: order,
  batchNumber: batch,
  status: status,
  servicePointName: 'Sala $id',
  buildingId: buildingId,
  buildingName: 'Prédio $buildingId',
  floorLabel: floorLabel,
  floorId: floorId,
  latitude: lat,
  longitude: lng,
  releaseReason: releaseReason,
);

RouteSummary _route(List<RouteStopSummary> stops, {int currentBatch = 1}) =>
    RouteSummary(
      id: 'r',
      fieldWorkerName: 'João',
      routeDate: DateTime(2026, 10, 28),
      status: 'IN_PROGRESS',
      startedAt: null,
      currentBatch: currentBatch,
      stops: stops,
    );

LocalStopState _local(StopLocalStatus status) =>
    LocalStopState(status: status, updatedAt: DateTime(2026, 10, 28, 9));

List<DayBuilding> _build(
  RouteSummary route, {
  Map<String, LocalStopState> local = const {},
  Set<String> impeded = const {},
  Set<String> pendingSync = const {},
}) => buildDayBuildings(route, local, impeded, pendingSync);

SlotState _stateOf(List<DayBuilding> buildings, String id) => buildings
    .expand((b) => b.floors)
    .expand((f) => f.slots)
    .firstWhere((s) => s.stopId == id)
    .state;

void main() {
  group('buildDayBuildings order and numbering', () {
    test('numbers buildings 1..n by first order index', () {
      final route = _route([
        _stop('c1', 3, 'C'),
        _stop('a1', 1, 'A'),
        _stop('b1', 2, 'B'),
      ]);
      final buildings = _build(route);
      expect(buildings.map((b) => b.buildingId), ['A', 'B', 'C']);
      expect(buildings.map((b) => b.number), [1, 2, 3]);
    });

    test('orders across batches, not batch by batch', () {
      final route = _route([
        _stop('a1', 1, 'A'),
        _stop('b1', 2, 'B'),
        _stop('a2', 3, 'A', batch: 2),
      ]);
      expect(_build(route).map((b) => b.buildingId), ['A', 'B']);
    });

    test('drops a building with only released stops and renumbers', () {
      final route = _route([
        _stop('a1', 1, 'A'),
        _stop(
          'b1',
          2,
          'B',
          status: 'RELEASED',
          releaseReason: 'LOCATION_SILENCE',
        ),
        _stop('c1', 3, 'C'),
      ]);
      final buildings = _build(route);
      expect(buildings.map((b) => b.buildingId), ['A', 'C']);
      expect(buildings.map((b) => b.number), [1, 2]);
    });

    test('keeps an impeded-only building: it is visible', () {
      final route = _route([
        _stop(
          'a1',
          1,
          'A',
          status: 'RELEASED',
          releaseReason: 'IMPEDIMENT',
        ),
      ]);
      expect(_build(route).map((b) => b.buildingId), ['A']);
    });

    test('position is the mean of the visible stops', () {
      final route = _route([
        _stop('a1', 1, 'A', lat: -7, lng: -35),
        _stop('a2', 2, 'A', lat: -8, lng: -36),
        _stop(
          'a3',
          3,
          'A',
          lat: -50,
          lng: -50,
          status: 'RELEASED',
          releaseReason: 'LOCATION_SILENCE',
        ),
      ]);
      final position = _build(route).single.position;
      expect(position.latitude, closeTo(-7.5, 1e-9));
      expect(position.longitude, closeTo(-35.5, 1e-9));
    });
  });

  group('floors', () {
    final route = _route([
      _stop('s1', 1, 'A', floorId: 'f-2', floorLabel: '2º andar'),
      _stop('s2', 2, 'A'),
      _stop('s3', 4, 'A', floorId: 'f-2', floorLabel: '2º andar'),
      _stop('s4', 3, 'A'),
    ]);

    test('come out in first-appearance order with slots by order', () {
      final floors = _build(route).single.floors;
      expect(floors.map((f) => f.floorId), ['f-2', 'f-0']);
      expect(floors.map((f) => f.label), ['2º andar', 'Térreo']);
      expect(floors[0].slots.map((s) => s.stopId), ['s1', 's3']);
      expect(floors[1].slots.map((s) => s.stopId), ['s2', 's4']);
    });

    test('group by label when the snapshot has no floor id', () {
      final old = _route([
        _stop('s1', 1, 'A', floorId: null, floorLabel: '1º andar'),
        _stop('s2', 2, 'A', floorId: null),
        _stop('s3', 3, 'A', floorId: null, floorLabel: '1º andar'),
      ]);
      final floors = _build(old).single.floors;
      expect(floors.map((f) => f.label), ['1º andar', 'Térreo']);
      expect(floors.first.floorId, isNull);
      expect(floors.first.slots, hasLength(2));
    });

    test('drop a floor with only released stops', () {
      final mixed = _route([
        _stop('s1', 1, 'A'),
        _stop(
          's2',
          2,
          'A',
          floorId: 'f-1',
          floorLabel: '1º andar',
          status: 'RELEASED',
          releaseReason: 'END_OF_DAY',
        ),
      ]);
      expect(_build(mixed).single.floors.map((f) => f.floorId), ['f-0']);
    });

    test('carry the sync flag and a deterministic stamp tilt', () {
      final slot = _build(
        route,
        pendingSync: {'s1'},
      ).single.floors.first.slots.first;
      expect(slot.pendingSync, isTrue);
      expect(slot.stampRotationDeg, stampRotationFor('s1'));
    });
  });

  group('slot state precedence', () {
    test('impeded: an id in the impeded set beats everything', () {
      final route = _route([_stop('s1', 1, 'A', status: 'DONE')]);
      final b = _build(route, impeded: {'s1'});
      expect(_stateOf(b, 's1'), SlotState.impeded);
    });

    test('impeded: a RELEASED stop with an IMPEDIMENT reason', () {
      final route = _route([
        _stop('s1', 1, 'A', status: 'RELEASED', releaseReason: 'IMPEDIMENT'),
      ]);
      expect(_stateOf(_build(route), 's1'), SlotState.impeded);
    });

    test('released: any other release reason', () {
      final route = _route([
        _stop('s1', 1, 'A'),
        _stop('s2', 2, 'A', status: 'RELEASED', releaseReason: 'END_OF_DAY'),
      ]);
      expect(_stateOf(_build(route), 's2'), SlotState.released);
    });

    test('done: local check-out beats a stamp and the server status', () {
      final route = _route([_stop('s1', 1, 'A', status: 'IN_PROGRESS')]);
      final b = _build(route, local: {'s1': _local(StopLocalStatus.done)});
      expect(_stateOf(b, 's1'), SlotState.done);
    });

    test('done: the server status alone', () {
      final route = _route([_stop('s1', 1, 'A', status: 'DONE')]);
      expect(_stateOf(_build(route), 's1'), SlotState.done);
    });

    test('stamped: local stamp beats a server in-progress', () {
      final route = _route([_stop('s1', 1, 'A', status: 'IN_PROGRESS')]);
      final b = _build(route, local: {'s1': _local(StopLocalStatus.stamped)});
      expect(_stateOf(b, 's1'), SlotState.stamped);
    });

    test('inProgress: local row or server status', () {
      final route = _route([
        _stop('s1', 1, 'A'),
        _stop('s2', 2, 'A', status: 'IN_PROGRESS'),
      ]);
      final b = _build(
        route,
        local: {'s1': _local(StopLocalStatus.inProgress)},
      );
      expect(_stateOf(b, 's1'), SlotState.inProgress);
      expect(_stateOf(b, 's2'), SlotState.inProgress);
    });

    test('next: the first open stop of the current batch only', () {
      final route = _route([
        _stop('s1', 1, 'A', status: 'DONE'),
        _stop('s2', 2, 'A'),
        _stop('s3', 3, 'A'),
      ]);
      final b = _build(route);
      expect(_stateOf(b, 's2'), SlotState.next);
      expect(_stateOf(b, 's3'), SlotState.pending);
    });

    test('pending: open stops of an earlier or later batch', () {
      final route = _route([
        _stop('s1', 1, 'A'),
        _stop('s2', 2, 'A', batch: 2),
        _stop('s3', 3, 'A', batch: 3),
      ], currentBatch: 2);
      final b = _build(route);
      expect(_stateOf(b, 's1'), SlotState.pending);
      expect(_stateOf(b, 's2'), SlotState.next);
      expect(_stateOf(b, 's3'), SlotState.pending);
    });
  });

  group('FloorRow', () {
    FloorRow floorWith(Map<String, StopLocalStatus> states) {
      final route = _route([
        for (var i = 0; i < 3; i++) _stop('s${i + 1}', i + 1, 'A'),
      ]);
      final local = {
        for (final e in states.entries) e.key: _local(e.value),
      };
      return _build(route, local: local).single.floors.single;
    }

    test('an in-progress slot: open check-in, not ready to leave', () {
      final floor = floorWith({'s1': StopLocalStatus.inProgress});
      expect(floor.hasOpenCheckIn, isTrue);
      expect(floor.readyForCheckOut, isFalse);
    });

    test('a stamped slot with the rest pending: ready to leave', () {
      final floor = floorWith({'s1': StopLocalStatus.stamped});
      expect(floor.hasOpenCheckIn, isTrue);
      expect(floor.readyForCheckOut, isTrue);
    });

    test('stamped and in progress together: not ready', () {
      final floor = floorWith({
        's1': StopLocalStatus.stamped,
        's2': StopLocalStatus.inProgress,
      });
      expect(floor.readyForCheckOut, isFalse);
    });

    test('pending and next slots do not block the exit', () {
      final floor = floorWith({
        's1': StopLocalStatus.stamped,
        's2': StopLocalStatus.done,
      });
      expect(
        floor.slots.map((s) => s.state),
        [SlotState.stamped, SlotState.done, SlotState.next],
      );
      expect(floor.readyForCheckOut, isTrue);
    });

    test('stamped and impeded together: ready to leave', () {
      final route = _route([
        for (var i = 0; i < 2; i++) _stop('s${i + 1}', i + 1, 'A'),
      ]);
      final floor = _build(
        route,
        local: {'s1': _local(StopLocalStatus.stamped)},
        impeded: {'s2'},
      ).single.floors.single;
      expect(floor.readyForCheckOut, isTrue);
    });

    test('impeded only: no check-in open, nothing to leave', () {
      final route = _route([_stop('s1', 1, 'A')]);
      final floor = _build(route, impeded: {'s1'}).single.floors.single;
      expect(floor.slots.single.state, SlotState.impeded);
      expect(floor.hasOpenCheckIn, isFalse);
      expect(floor.readyForCheckOut, isFalse);
    });

    test('openFloorOfDay finds the checked-in floor and its building', () {
      final route = _route([_stop('s1', 1, 'A'), _stop('s2', 2, 'B')]);
      final buildings = _build(
        route,
        local: {'s2': _local(StopLocalStatus.inProgress)},
      );
      final open = openFloorOfDay(buildings);
      expect(open?.building.buildingId, 'B');
      expect(open?.floor.slots.single.stopId, 's2');
      expect(openFloorOfDay(_build(route)), isNull);
    });

    test('no check-in at all: neither open nor ready', () {
      final floor = floorWith({'s1': StopLocalStatus.done});
      expect(floor.hasOpenCheckIn, isFalse);
      expect(floor.readyForCheckOut, isFalse);
    });
  });

  group('DayBuilding', () {
    test('complete counts done and impeded, ignores released', () {
      final route = _route([
        _stop('s1', 1, 'A', status: 'DONE'),
        _stop('s2', 2, 'A', status: 'RELEASED', releaseReason: 'IMPEDIMENT'),
        _stop('s3', 3, 'A', status: 'RELEASED', releaseReason: 'END_OF_DAY'),
      ]);
      final building = _build(route).single;
      expect(building.complete, isTrue);
      expect(building.openTasks, 0);
    });

    test('openTasks counts pending, next, in-progress and stamped', () {
      final route = _route([
        for (var i = 1; i <= 5; i++) _stop('s$i', i, 'A'),
      ]);
      final building = _build(
        route,
        local: {
          's1': _local(StopLocalStatus.done),
          's2': _local(StopLocalStatus.stamped),
          's3': _local(StopLocalStatus.inProgress),
        },
      ).single;
      expect(building.openTasks, 4);
      expect(building.complete, isFalse);
    });
  });

  group('nextBuilding and openFloorOf', () {
    final route = _route([
      _stop('a1', 1, 'A', status: 'DONE'),
      _stop('b1', 2, 'B'),
      _stop('b2', 3, 'B', floorId: 'f-1', floorLabel: '1º andar'),
    ]);

    test('nextBuilding is the one holding the next slot', () {
      expect(nextBuilding(_build(route))?.buildingId, 'B');
    });

    test('nextTaskStopId skips a task reported impossible here', () {
      final route = _route([_stop('s1', 1, 'A'), _stop('s2', 2, 'B')]);
      expect(nextTaskStopId(_build(route)), 's1');
      expect(nextTaskStopId(_build(route, impeded: {'s1'})), 's2');
    });

    test('nextBuilding is null when nothing is open', () {
      final done = _route([_stop('a1', 1, 'A', status: 'DONE')]);
      expect(nextBuilding(_build(done)), isNull);
    });

    test('openFloorOf is the floor with a check-in open', () {
      final b = _build(
        route,
        local: {'b2': _local(StopLocalStatus.stamped)},
      ).last;
      expect(openFloorOf(b)?.floorId, 'f-1');
    });

    test('openFloorOf is null with no check-in open', () {
      expect(openFloorOf(_build(route).last), isNull);
    });
  });

  group('checkInCandidates', () {
    test('returns only PENDING stops of the current batch on that floor', () {
      final route = _route([
        _stop('s1', 1, 'A'),
        _stop('s2', 2, 'A', status: 'IN_PROGRESS'),
        _stop('s3', 3, 'A', status: 'DONE'),
        _stop('s4', 4, 'A', batch: 2),
        _stop('s5', 5, 'A', floorId: 'f-1'),
        _stop('s6', 6, 'A', status: 'RELEASED', releaseReason: 'END_OF_DAY'),
        _stop('s7', 7, 'A'),
      ]);
      expect(checkInCandidates(route, 'f-0').map((s) => s.id), ['s1', 's7']);
    });
  });
}
