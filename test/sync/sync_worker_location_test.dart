import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/execution/location_execution_id.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/day_log_store.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/sync/location_refusal.dart';
import 'package:route_monitor/sync/sync_worker.dart';

import '../support/in_memory_database.dart';
import '../support/location_sync_support.dart';

/// An evidence API whose uploads all fail with [error].
class _PhotoRefusedApi extends PhotoApi {
  _PhotoRefusedApi(super.log, this.error);

  final Exception error;

  @override
  Future<DateTime?> uploadPhoto({
    required Uint8List bytes,
    required String executionId,
    required String sha256,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async => throw error;
}

/// A store whose final write of a rejection fails.
class _RejectFailsStore extends DriftLocalWriteStore {
  // The super parameter is private (`_db`): it cannot share its name.
  // ignore: matching_super_parameters
  _RejectFailsStore(super.db);

  @override
  Future<void> markRejected(String id, String error) =>
      throw StateError('disk full');
}

void main() {
  late AppDatabase db;
  late DriftLocalWriteStore store;
  late DriftStopProgressStore progress;
  late LocationApi api;
  late List<String> log;
  late List<LocationRefusal> refusals;
  late SyncWorker worker;
  late LocationOutbox outbox;

  final execA = locationExecutionId('sA');
  final execB = locationExecutionId('sB');

  setUp(() {
    db = inMemoryDatabase();
    addTearDown(db.close);
    store = DriftLocalWriteStore(db);
    progress = DriftStopProgressStore(db);
    outbox = LocationOutbox(db);
    log = [];
    refusals = [];
    api = LocationApi(log);
    worker = locationWorker(db, api, log, onLocationRefused: refusals.add);
  });

  Future<void> seedCompletion(String stopId, String place) =>
      outbox.completion(stopId, place);

  Future<void> seedPhoto(String id, String executionId) =>
      outbox.photo(id, executionId);

  Future<PendingOperationRow?> rowOf(String id) async =>
      (await store.unsyncedForRoute('r1')).where((r) => r.id == id).firstOrNull;

  Future<PendingOpState?> stateOf(String id) async {
    final row = await (db.select(
      db.pendingOperations,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : PendingOpState.values.byName(row.state);
  }

  group('a refused location completion', () {
    setUp(() async {
      await seedCompletion('sA', 'Praça central');
      await seedPhoto('photo-A1', execA);
      await seedPhoto('photo-A2', execA);
      await seedCompletion('sB', 'Jardim');
      await seedPhoto('photo-B1', execB);
      api.refusals['sA'] = const LocationRefusedException(
        code: 'OUT_OF_RADIUS',
        distanceM: 137.4,
        radiusM: 50,
      );
    });

    test('does not block the route: the next stop still sends', () async {
      await worker.syncRoute('r1');

      expect(log, ['completion:sA', 'completion:sB', 'photo:photo-B1']);
      expect(await stateOf('done-sB'), PendingOpState.synced);
      expect((await progress.progressFor('sB'))!.status, StopLocalStatus.done);
      expect(await store.blockedForRoute('r1'), isEmpty);
    });

    test('puts the stop back to pending and drops its photo rows', () async {
      await worker.syncRoute('r1');

      expect(await progress.progressFor('sA'), isNull);
      expect(await stateOf('photo-A1'), isNull);
      expect(await stateOf('photo-A2'), isNull);
      expect(await stateOf('done-sA'), PendingOpState.rejected);
    });

    test('keeps the server reason on the rejected row', () async {
      await worker.syncRoute('r1');

      final row = await (db.select(
        db.pendingOperations,
      )..where((t) => t.id.equals('done-sA'))).getSingle();
      expect(row.lastError, contains('OUT_OF_RADIUS'));
      expect(row.lastError, contains('137'));
    });

    test('announces the place and the distance once', () async {
      await worker.syncRoute('r1');

      final refusal = refusals.single;
      expect(refusal.routeStopId, 'sA');
      expect(refusal.placeName, 'Praça central');
      expect(
        refusal.message,
        'Conclusão recusada em Praça central: você estava a 137 m do local.',
      );
    });

    test('is never retried by a later pass', () async {
      await worker.syncRoute('r1');
      log.clear();

      await worker.syncRoute('r1');

      expect(log, isEmpty);
      expect(refusals, hasLength(1));
      expect(await rowOf('done-sA'), isNull, reason: 'out of the unsent list');
    });

    test('leaves no work for the route to chase', () async {
      await worker.syncRoute('r1');

      expect(await store.routeIdsWithWork(), isEmpty);
    });
  });

  test('a refusal takes the stop back out of the day log', () async {
    final dayLog = DriftDayLogStore(db);
    final completedAt = DateTime.parse('2026-10-31T12:00:00.000Z').toLocal();
    await seedCompletion('sA', 'Praça central');
    await dayLog.recordStopDone(completedAt);
    await dayLog.recordStopDone(completedAt);
    api.refusals['sA'] = const LocationRefusedException(
      code: 'OUT_OF_RADIUS',
      distanceM: 90,
      radiusM: 50,
    );
    final counting = locationWorker(db, api, log, dayLog: dayLog);

    await counting.syncRoute('r1');

    expect((await dayLog.all()).single.pointsDone, 1);
  });

  test('a refusal never takes the day log below zero', () async {
    final dayLog = DriftDayLogStore(db);
    await seedCompletion('sA', 'Praça central');
    api.refusals['sA'] = const LocationRefusedException(
      code: 'OUT_OF_RADIUS',
      distanceM: 90,
      radiusM: 50,
    );

    await locationWorker(db, api, log, dayLog: dayLog).syncRoute('r1');

    expect(await dayLog.all(), isEmpty);
  });

  test('concluding the same stop again after a refusal is delivered, not '
      'held by a blocked scope', () async {
    await seedCompletion('sA', 'Praça central');
    api.refusals['sA'] = const LocationRefusedException(
      code: 'OUT_OF_RADIUS',
      distanceM: 90,
      radiusM: 50,
    );
    await worker.syncRoute('r1');
    log.clear();
    api.refusals.remove('sA');
    // The worker walks to the place and concludes again: same v5
    // execution_id, a new idempotency key, new photos.
    await outbox.seed('done-sA-again', PendingOpKind.locationCompletion, {
      'execution_id': execA,
      'route_stop_id': 'sA',
      'idempotency_key': 'done-sA-again',
      'latitude': -7.2,
      'longitude': -35.9,
      'accuracy_m': null,
      'completed_at': '2026-10-31T12:05:00.000Z',
      'complaints_suggestions': null,
      'place_name': 'Praça central',
    });
    await progress.upsertDone('sA', execA);
    await seedPhoto('photo-A-again', execA);

    await worker.syncRoute('r1');

    expect(log, ['completion:sA', 'photo:photo-A-again']);
    expect(await stateOf('done-sA-again'), PendingOpState.synced);
    expect(await stateOf('photo-A-again'), PendingOpState.synced);
    expect(await store.blockedForRoute('r1'), isEmpty);
  });

  test('a refusal without a location says the location was off', () async {
    await seedCompletion('sA', 'Praça central');
    api.refusals['sA'] = const LocationRefusedException(
      code: 'LOCATION_REQUIRED',
      distanceM: null,
      radiusM: null,
    );

    await worker.syncRoute('r1');

    expect(
      refusals.single.message,
      'Conclusão recusada em Praça central: sem localização ativa.',
    );
    expect(await progress.progressFor('sA'), isNull);
  });

  test('a raw 422 OUT_OF_RADIUS from the wire is a refusal too', () async {
    await seedCompletion('sA', 'Praça central');
    final options = RequestOptions(path: '/location-completions');
    api.refusals['sA'] = DioException(
      requestOptions: options,
      response: Response<dynamic>(
        requestOptions: options,
        statusCode: 422,
        data: {
          'detail': {
            'code': 'OUT_OF_RADIUS',
            'distance_m': 90.0,
            'radius_m': 50,
          },
        },
      ),
    );

    await worker.syncRoute('r1');

    expect(await stateOf('done-sA'), PendingOpState.rejected);
    expect(refusals.single.distanceM, 90.0);
  });

  test('a 409 "already" completion counts as delivered', () async {
    await seedCompletion('sA', 'Praça central');
    final options = RequestOptions(path: '/location-completions');
    api.refusals['sA'] = DioException(
      requestOptions: options,
      response: Response<dynamic>(
        requestOptions: options,
        statusCode: 409,
        data: {'detail': 'Execution already completed'},
      ),
    );

    await worker.syncRoute('r1');

    expect(await stateOf('done-sA'), PendingOpState.synced);
    expect((await progress.progressFor('sA'))!.status, StopLocalStatus.done);
    expect(refusals, isEmpty);
  });

  test('a rejection is atomic: when its last write fails, the stop is still '
      'done and its photos are still there', () async {
    await seedCompletion('sA', 'Praça central');
    await seedPhoto('photo-A1', execA);
    api.refusals['sA'] = const LocationRefusedException(
      code: 'OUT_OF_RADIUS',
      distanceM: 90,
      radiusM: 50,
    );
    final failing = locationWorker(
      db,
      api,
      log,
      store: _RejectFailsStore(db),
      onLocationRefused: refusals.add,
    );

    await expectLater(failing.syncRoute('r1'), throwsStateError);

    expect((await progress.progressFor('sA'))!.status, StopLocalStatus.done);
    expect(await stateOf('photo-A1'), PendingOpState.pending);
    expect(refusals, isEmpty);
  });

  test('a 422 OUT_OF_RADIUS on a photo row is blocked, not rejected', () async {
    await seedCompletion('sA', 'Praça central');
    await seedPhoto('photo-A1', execA);
    final options = RequestOptions(path: '/x');
    final failing = locationWorker(
      db,
      api,
      log,
      onLocationRefused: refusals.add,
      photos: _PhotoRefusedApi(
        log,
        DioException(
          requestOptions: options,
          response: Response<dynamic>(
            requestOptions: options,
            statusCode: 422,
            data: {
              'detail': {'code': 'OUT_OF_RADIUS'},
            },
          ),
        ),
      ),
    );

    await failing.syncRoute('r1');

    expect(await stateOf('photo-A1'), PendingOpState.blocked);
    expect(refusals, isEmpty);
    expect((await progress.progressFor('sA'))!.status, StopLocalStatus.done);
  });
}
