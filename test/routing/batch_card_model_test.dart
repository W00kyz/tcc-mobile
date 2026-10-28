import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/routing/route_repository.dart';

RouteStopSummary _stop(
  String id,
  int order,
  String buildingId,
  String buildingName, {
  String status = 'PENDING',
  DateTime? doneAt,
  int batch = 1,
  double lat = -7.2,
  double lng = -35.9,
  String? releaseReason,
}) => RouteStopSummary(
  id: id,
  orderIndex: order,
  batchNumber: batch,
  status: status,
  servicePointName: 'Sala $id',
  buildingId: buildingId,
  buildingName: buildingName,
  floorLabel: 'Térreo',
  latitude: lat,
  longitude: lng,
  doneAt: doneAt,
  releaseReason: releaseReason,
);

RouteSummary _route(List<RouteStopSummary> stops, {int currentBatch = 1}) =>
    RouteSummary(
      id: 'r',
      fieldWorkerName: 'João',
      routeDate: DateTime(2026, 10, 27),
      status: 'IN_PROGRESS',
      startedAt: null,
      currentBatch: currentBatch,
      stops: stops,
    );

/// CAA x3, BQ x1, REI x2 (one RELEASED), BC x2.
RouteSummary _fixture({
  String caa1Status = 'PENDING',
  DateTime? caa2DoneAt,
}) => _route([
  _stop('caa1', 1, 'b-caa', 'Central de Aulas', status: caa1Status),
  _stop(
    'caa2',
    2,
    'b-caa',
    'Central de Aulas',
    status: caa2DoneAt == null ? 'PENDING' : 'DONE',
    doneAt: caa2DoneAt,
  ),
  _stop('caa3', 3, 'b-caa', 'Central de Aulas'),
  _stop('bq1', 4, 'b-bq', 'BQ'),
  _stop('rei1', 5, 'b-rei', 'Reitoria'),
  _stop(
    'rei2',
    6,
    'b-rei',
    'Reitoria',
    status: 'RELEASED',
    releaseReason: 'IMPEDIMENT',
  ),
  _stop('bc1', 7, 'b-bc', 'Biblioteca Central'),
  _stop('bc2', 8, 'b-bc', 'Biblioteca Central'),
]);

CardSlot _slot(BatchCard card, String id) =>
    card.groups.expand((g) => g.slots).firstWhere((s) => s.stopId == id);

void main() {
  group('buildBatchCard', () {
    test('groups by building in route order', () {
      final card = buildBatchCard(_fixture(), {}, {});
      expect(card.groups.map((g) => g.buildingName), [
        'Central de Aulas',
        'BQ',
        'Reitoria',
        'Biblioteca Central',
      ]);
      expect(card.batchNumber, 1);
    });

    test('released stops leave the total', () {
      final card = buildBatchCard(_fixture(), {}, {});
      expect(card.total, 7);
      expect(card.released, 1);
      final rei = card.groups.firstWhere((g) => g.buildingId == 'b-rei');
      expect(rei.total, 1);
      expect(_slot(card, 'rei2').state, SlotState.released);
      expect(_slot(card, 'rei2').releaseReason, 'IMPEDIMENT');
    });

    test('local done beats server status', () {
      final at = DateTime(2026, 10, 27, 10, 20);
      final card = buildBatchCard(
        _fixture(caa1Status: 'IN_PROGRESS'),
        {'caa1': LocalStopState(status: StopLocalStatus.done, updatedAt: at)},
        {},
      );
      final slot = _slot(card, 'caa1');
      expect(slot.state, SlotState.done);
      expect(slot.stampedAt!.hour, 10);
      expect(slot.stampedAt!.minute, 20);
    });

    test('server done uses doneAt', () {
      final at = DateTime(2026, 10, 27, 9, 5);
      final card = buildBatchCard(_fixture(caa2DoneAt: at), {}, {});
      final slot = _slot(card, 'caa2');
      expect(slot.state, SlotState.done);
      expect(slot.stampedAt, at);
    });

    test('next is the first pending in route order, and only one', () {
      final card = buildBatchCard(
        _fixture(),
        {
          'caa1': LocalStopState(
            status: StopLocalStatus.done,
            updatedAt: DateTime(2026, 10, 27, 8),
          ),
        },
        {},
      );
      expect(card.next!.stopId, 'caa2');
      final slots = card.groups.expand((g) => g.slots);
      expect(slots.where((s) => s.state == SlotState.next).length, 1);
      expect(_slot(card, 'caa3').state, SlotState.pending);
    });

    test('inProgress from local status', () {
      final card = buildBatchCard(
        _fixture(),
        {
          'caa1': LocalStopState(
            status: StopLocalStatus.inProgress,
            updatedAt: DateTime(2026, 10, 27, 8),
          ),
        },
        {},
      );
      expect(_slot(card, 'caa1').state, SlotState.inProgress);
      expect(card.next!.stopId, 'caa2');
    });

    test('pendingSync flag set from the set', () {
      final card = buildBatchCard(_fixture(), {}, {'bq1'});
      expect(_slot(card, 'bq1').pendingSync, isTrue);
      expect(_slot(card, 'caa1').pendingSync, isFalse);
    });

    test('single-building batch', () {
      final route = _route([
        _stop('a', 1, 'b1', 'Prédio', lat: -7, lng: -35),
        _stop('b', 2, 'b1', 'Prédio', lng: -35.4),
      ]);
      final card = buildBatchCard(route, {}, {});
      expect(card.groups, hasLength(1));
      expect(card.groups.single.position.latitude, closeTo(-7.1, 1e-9));
      expect(card.groups.single.position.longitude, closeTo(-35.2, 1e-9));
    });

    test('only the current batch is on the card', () {
      final route = _route([
        _stop('old', 1, 'b1', 'Prédio', status: 'DONE'),
        _stop('cur', 2, 'b1', 'Prédio', batch: 2),
      ], currentBatch: 2);
      final card = buildBatchCard(route, {}, {});
      expect(card.batchNumber, 2);
      expect(card.total, 1);
    });

    test('complete when every non-released slot is done', () {
      final route = _route([
        _stop('a', 1, 'b1', 'Prédio'),
        _stop('r', 2, 'b1', 'Prédio', status: 'RELEASED'),
      ]);
      final at = DateTime(2026, 10, 27, 11);
      final done = buildBatchCard(route, {
        'a': LocalStopState(status: StopLocalStatus.done, updatedAt: at),
      }, {});
      expect(done.complete, isTrue);
      expect(done.groups.single.complete, isTrue);
      expect(done.next, isNull);
      expect(buildBatchCard(route, {}, {}).complete, isFalse);
    });
  });

  group('stampRotationFor', () {
    test('is stable and bounded', () {
      expect(stampRotationFor('abc'), stampRotationFor('abc'));
      final random = Random(7);
      for (var i = 0; i < 200; i++) {
        final id = List.generate(
          36,
          (_) => random.nextInt(16).toRadixString(16),
        ).join();
        expect(stampRotationFor(id), inInclusiveRange(-9, 9));
      }
    });
  });

  group('dayDoneCount', () {
    test('adds local dones not yet DONE on the server', () {
      final route = _fixture(caa2DoneAt: DateTime(2026, 10, 27, 9));
      final local = {
        'caa2': LocalStopState(
          status: StopLocalStatus.done,
          updatedAt: DateTime(2026, 10, 27, 9),
        ),
        'caa1': LocalStopState(
          status: StopLocalStatus.done,
          updatedAt: DateTime(2026, 10, 27, 10),
        ),
        'bq1': LocalStopState(
          status: StopLocalStatus.inProgress,
          updatedAt: DateTime(2026, 10, 27, 10),
        ),
      };
      expect(dayDoneCount(route, local), 2);
    });
  });
}
