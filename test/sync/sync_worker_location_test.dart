import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/execution/location_execution_id.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/released_stop_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
import 'package:route_monitor/sync/location_refusal.dart';
import 'package:route_monitor/sync/sync_worker.dart';

import '../support/fake_connectivity.dart';
import '../support/in_memory_database.dart';

/// Answers each location completion from [refusals] (by stop id) or accepts
/// it; every call lands in [log].
class _LocationApi implements ExecutionApi {
  _LocationApi(this.log);

  final List<String> log;
  final Map<String, Exception> refusals = {};

  @override
  Future<DateTime?> completeByLocation({
    required String executionId,
    required String routeStopId,
    required String idempotencyKey,
    required double latitude,
    required double longitude,
    required DateTime completedAt,
    double? accuracyM,
    double? clientClockOffsetSeconds,
    String? complaintsSuggestions,
  }) async {
    log.add('completion:$routeStopId');
    final refusal = refusals[routeStopId];
    if (refusal != null) throw refusal;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PhotoApi implements EvidenceApi {
  _PhotoApi(this.log);

  final List<String> log;

  @override
  Future<DateTime?> uploadPhoto({
    required String executionId,
    required Uint8List bytes,
    required String sha256,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async {
    log.add('photo:$idempotencyKey');
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoReleasedStops implements ReleasedStopStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late DriftLocalWriteStore store;
  late DriftStopProgressStore progress;
  late _LocationApi api;
  late List<String> log;
  late List<LocationRefusal> refusals;
  late SyncWorker worker;
  var clock = 0;

  final execA = locationExecutionId('sA');
  final execB = locationExecutionId('sB');

  setUp(() {
    clock = 0;
    db = inMemoryDatabase();
    addTearDown(db.close);
    store = DriftLocalWriteStore(db);
    progress = DriftStopProgressStore(db);
    log = [];
    refusals = [];
    api = _LocationApi(log);
    worker = SyncWorker(
      store,
      progress,
      DriftSyncMetaStore(db),
      FakeConnectivity(isOnline: true),
      api,
      _PhotoApi(log),
      _NoReleasedStops(),
      onLocationRefused: refusals.add,
    );
  });

  /// One row at a fixed `createdAt`, so the FIFO order is the test's.
  Future<void> seed(
    String id,
    PendingOpKind kind,
    Map<String, dynamic> payload, {
    PendingOpState state = PendingOpState.pending,
  }) => db
      .into(db.pendingOperations)
      .insert(
        PendingOperationsCompanion.insert(
          id: id,
          kind: kind.name,
          routeId: 'r1',
          payloadJson: jsonEncode(payload),
          createdAt: clock++,
          state: Value(state.name),
        ),
      );

  Future<void> seedCompletion(String stopId, String place) async {
    await seed('done-$stopId', PendingOpKind.locationCompletion, {
      'execution_id': locationExecutionId(stopId),
      'route_stop_id': stopId,
      'idempotency_key': 'done-$stopId',
      'latitude': -7.2,
      'longitude': -35.9,
      'accuracy_m': null,
      'completed_at': '2026-10-31T12:00:00.000Z',
      'complaints_suggestions': null,
      'place_name': place,
    });
    await progress.upsertDone(stopId, locationExecutionId(stopId));
  }

  Future<void> seedPhoto(String id, String executionId) =>
      seed(id, PendingOpKind.evidencePhoto, {
        'execution_id': executionId,
        'bytes_b64': 'AAAA',
        'sha256': 'h',
        'captured_at': '2026-10-31T11:59:00.000Z',
        'idempotency_key': id,
      });

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
}
