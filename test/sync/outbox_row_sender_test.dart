import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
import 'package:route_monitor/sync/outbox_row_sender.dart';

import '../support/in_memory_database.dart';

/// A [Dio] adapter that records the request and answers [status] with [body].
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.status, this.body);

  final int status;
  final Map<String, dynamic> body;
  RequestOptions? request;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        'date': ['Sat, 31 Oct 2026 12:00:05 GMT'],
      },
    );
  }
}

class _NoEvidenceApi implements EvidenceApi {
  const _NoEvidenceApi();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A fresh payload per call: a test may edit it.
Map<String, dynamic> _payload() => {
  'execution_id': 'exec-1',
  'route_stop_id': 'stop-1',
  'idempotency_key': 'key-1',
  'latitude': -7.215,
  'longitude': -35.915,
  'accuracy_m': 8.5,
  'completed_at': '2026-10-31T12:00:00.000Z',
  'complaints_suggestions': 'bebedouro solto',
};

PendingOperationRow _completionRow() => PendingOperationRow(
  id: 'key-1',
  kind: PendingOpKind.locationCompletion,
  routeId: 'r1',
  payload: _payload(),
  createdAt: 1,
  state: PendingOpState.pending,
  lastError: null,
  attempts: 0,
  nextAttemptAt: null,
);

void main() {
  late AppDatabase db;
  late DriftStopProgressStore progress;
  late DriftSyncMetaStore meta;

  setUp(() {
    db = inMemoryDatabase();
    addTearDown(db.close);
    progress = DriftStopProgressStore(db);
    meta = DriftSyncMetaStore(db);
  });

  OutboxRowSender senderOver(_ScriptedAdapter adapter) => OutboxRowSender(
    executionApi: DioExecutionApi(
      Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = adapter,
    ),
    evidenceApi: const _NoEvidenceApi(),
    stopProgress: progress,
    syncMeta: meta,
  );

  test('a location completion posts the queued payload and marks the stop '
      'done locally', () async {
    final adapter = _ScriptedAdapter(201, {
      'execution_id': 'exec-1',
      'route_stop_id': 'stop-1',
      'completed_at': '2026-10-31T12:00:00Z',
      'validation_flags': <String>[],
      'review_status': 'NOT_REQUIRED',
    });
    await meta.setClockOffsetSeconds(-3.5);

    final serverDate = await senderOver(adapter).send(_completionRow());

    final request = adapter.request!;
    expect(request.method, 'POST');
    expect(request.path, '/location-completions');
    expect(request.data, {
      'route_stop_id': 'stop-1',
      'execution_id': 'exec-1',
      'idempotency_key': 'key-1',
      'latitude': -7.215,
      'longitude': -35.915,
      'accuracy_m': 8.5,
      'completed_at': '2026-10-31T12:00:00.000Z',
      'client_clock_offset_seconds': -3.5,
      'complaints_suggestions': 'bebedouro solto',
    });
    expect(serverDate, DateTime.utc(2026, 10, 31, 12, 0, 5));
    final entry = (await progress.progressFor('stop-1'))!;
    expect(entry.status, StopLocalStatus.done);
    expect(entry.executionId, 'exec-1');
  });

  test('a blank accuracy and note are sent as absent keys', () async {
    final adapter = _ScriptedAdapter(201, {});
    final row = _completionRow();
    row.payload
      ..['accuracy_m'] = null
      ..['complaints_suggestions'] = null;

    await senderOver(adapter).send(row);

    final body = adapter.request!.data as Map<String, dynamic>;
    expect(body.containsKey('accuracy_m'), isFalse);
    expect(body.containsKey('complaints_suggestions'), isFalse);
  });

  test(
    'a 422 OUT_OF_RADIUS becomes a typed refusal and writes nothing',
    () async {
      final adapter = _ScriptedAdapter(422, {
        'detail': {
          'code': 'OUT_OF_RADIUS',
          'distance_m': 137.25,
          'radius_m': 50,
          'detail': 'longe',
        },
      });

      final sending = senderOver(adapter).send(_completionRow());

      await expectLater(
        sending,
        throwsA(
          isA<LocationRefusedException>()
              .having((e) => e.code, 'code', 'OUT_OF_RADIUS')
              .having((e) => e.distanceM, 'distanceM', 137.25)
              .having((e) => e.radiusM, 'radiusM', 50),
        ),
      );
      expect(await progress.progressFor('stop-1'), isNull);
    },
  );

  test('a 422 LOCATION_REQUIRED carries no distance', () async {
    final adapter = _ScriptedAdapter(422, {
      'detail': {'code': 'LOCATION_REQUIRED', 'detail': 'sem posição'},
    });

    await expectLater(
      senderOver(adapter).send(_completionRow()),
      throwsA(
        isA<LocationRefusedException>()
            .having((e) => e.code, 'code', 'LOCATION_REQUIRED')
            .having((e) => e.distanceM, 'distanceM', isNull),
      ),
    );
  });

  test('any other 422 stays a DioException', () async {
    final adapter = _ScriptedAdapter(422, {
      'detail': {'code': 'NOT_A_LOCATION_STOP', 'detail': 'x'},
    });

    await expectLater(
      senderOver(adapter).send(_completionRow()),
      throwsA(isA<DioException>()),
    );
  });
}
