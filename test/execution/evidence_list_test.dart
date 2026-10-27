import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/evidence_list.dart';
import 'package:route_monitor/local/local_write_store.dart';

class _FakeEvidenceApi implements EvidenceApi {
  _FakeEvidenceApi(this.items, {this.error});
  final List<EvidenceItem> items;

  /// Thrown by `listEvidence` when set (a failed network call).
  final Exception? error;

  @override
  Future<List<EvidenceItem>> listEvidence(String executionId) async {
    final failure = error;
    if (failure != null) throw failure;
    return items;
  }

  @override
  Future<DateTime?> uploadNote({
    required String executionId,
    required String textBody,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<DateTime?> uploadPhoto({
    required String executionId,
    required Uint8List bytes,
    required String sha256,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) => throw UnimplementedError();
}

class _FakeLocalWriteStore implements LocalWriteStore {
  _FakeLocalWriteStore(this.rows);
  final List<PendingOperationRow> rows;

  @override
  Future<void> enqueue({
    required String id,
    required PendingOpKind kind,
    required Map<String, dynamic> payload,
    required String routeId,
  }) => throw UnimplementedError();

  @override
  Future<void> markFailed(String id, String error) =>
      throw UnimplementedError();

  @override
  Future<void> markSynced(String id) => throw UnimplementedError();

  @override
  Future<List<PendingOperationRow>> unsyncedForRoute(String routeId) async =>
      rows;

  @override
  Future<void> markStopReleased(
    String id, {
    required String routeStopId,
    required String error,
  }) => throw UnimplementedError();

  @override
  Future<void> markBlocked(String id, String error) =>
      throw UnimplementedError();

  @override
  Future<void> markRetryScheduled(
    String id, {
    required int attempts,
    required int nextAttemptAt,
  }) => throw UnimplementedError();

  @override
  Future<List<PendingOperationRow>> blockedForRoute(String routeId) =>
      throw UnimplementedError();

  @override
  Future<List<PendingOperationRow>> dueForRoute(
    String routeId, {
    required int now,
  }) => throw UnimplementedError();

  @override
  Future<List<String>> routeIdsWithWork() => throw UnimplementedError();

  @override
  Future<void> resetToPending(String id) => throw UnimplementedError();

  @override
  Future<int> localPhotoCountFor(String executionId) =>
      throw UnimplementedError();
}

PendingOperationRow _row({
  required String id,
  required PendingOpKind kind,
  required Map<String, dynamic> payload,
  PendingOpState state = PendingOpState.pending,
}) => PendingOperationRow(
  id: id,
  kind: kind,
  routeId: 'route-A',
  payload: payload,
  createdAt: 0,
  state: state,
  lastError: null,
  attempts: 0,
  nextAttemptAt: null,
);

void main() {
  test(
    'combines synced backend items with pending/failed local rows for the '
    'same execution, sorted oldest-first',
    () async {
      final api = _FakeEvidenceApi([
        EvidenceItem(
          id: 'e1',
          kind: 'PHOTO',
          capturedAt: DateTime.utc(2026, 8, 25, 8),
          createdAt: DateTime.utc(2026, 8, 25, 8, 1),
          contentUrl: '/evidence/e1/content',
          idempotencyKey: 'key-synced',
        ),
      ]);
      final photoBytes = base64Encode(Uint8List.fromList([1, 2, 3]));
      final store = _FakeLocalWriteStore([
        _row(
          id: 'op-1',
          kind: PendingOpKind.evidencePhoto,
          payload: {
            'execution_id': 'exec-1',
            'bytes_b64': photoBytes,
            'captured_at': '2026-08-25T08:05:00.000Z',
            'idempotency_key': 'key-pending',
          },
        ),
        _row(
          id: 'op-2',
          kind: PendingOpKind.evidenceNote,
          payload: {
            'execution_id': 'exec-1',
            'text_body': 'Sala trancada.',
            'captured_at': '2026-08-25T08:02:00.000Z',
          },
          state: PendingOpState.failed,
        ),
      ]);

      final entries = await loadStopEvidence(
        store: store,
        api: api,
        routeId: 'route-A',
        executionId: 'exec-1',
      );

      expect(entries, hasLength(3));
      expect(entries[0].kind, 'PHOTO');
      expect(entries[0].syncState, PendingOpState.synced);
      expect(entries[0].contentUrl, '/evidence/e1/content');
      expect(entries[1].kind, 'NOTE');
      expect(entries[1].syncState, PendingOpState.failed);
      expect(entries[1].textBody, 'Sala trancada.');
      expect(entries[2].kind, 'PHOTO');
      expect(entries[2].syncState, PendingOpState.pending);
      expect(entries[2].photoBytes, [1, 2, 3]);
      // Both sources carry the upload's idempotency key.
      expect(entries[0].idempotencyKey, 'key-synced');
      expect(entries[2].idempotencyKey, 'key-pending');
    },
  );

  test(
    'excludes local rows for a different execution and non-evidence kinds',
    () async {
      final api = _FakeEvidenceApi(const []);
      final store = _FakeLocalWriteStore([
        _row(
          id: 'op-other-exec',
          kind: PendingOpKind.evidenceNote,
          payload: {
            'execution_id': 'exec-2',
            'text_body': 'not this stop',
            'captured_at': '2026-08-25T08:05:00.000Z',
          },
        ),
        _row(
          id: 'op-checkin',
          kind: PendingOpKind.checkIn,
          payload: {
            'execution_id': 'exec-1',
            'captured_at': '2026-08-25T08:05:00.000Z',
          },
        ),
      ]);

      final entries = await loadStopEvidence(
        store: store,
        api: api,
        routeId: 'route-A',
        executionId: 'exec-1',
      );

      expect(entries, isEmpty);
    },
  );

  group('when the backend list cannot be fetched', () {
    List<PendingOperationRow> twoPendingPhotos() => [
      for (final n in [1, 2])
        _row(
          id: 'op-$n',
          kind: PendingOpKind.evidencePhoto,
          payload: {
            'execution_id': 'exec-1',
            'bytes_b64': base64Encode(Uint8List.fromList([n])),
            'captured_at': '2026-08-25T08:0$n:00.000Z',
          },
        ),
    ];

    test('a network failure falls back to the pending local rows', () async {
      final api = _FakeEvidenceApi(
        const [],
        error: DioException.connectionError(
          requestOptions: RequestOptions(path: '/executions/exec-1/evidence'),
          reason: 'offline',
        ),
      );

      final entries = await loadStopEvidence(
        store: _FakeLocalWriteStore(twoPendingPhotos()),
        api: api,
        routeId: 'route-A',
        executionId: 'exec-1',
      );

      expect(entries.where((e) => e.kind == 'PHOTO'), hasLength(2));
    });

    test('an HTTP error response still propagates', () {
      final request = RequestOptions(path: '/executions/exec-1/evidence');
      final api = _FakeEvidenceApi(
        const [],
        error: DioException.badResponse(
          statusCode: 404,
          requestOptions: request,
          response: Response<void>(requestOptions: request, statusCode: 404),
        ),
      );

      expect(
        loadStopEvidence(
          store: _FakeLocalWriteStore(twoPendingPhotos()),
          api: api,
          routeId: 'route-A',
          executionId: 'exec-1',
        ),
        throwsA(isA<DioException>()),
      );
    });

    test('a non-Dio error still propagates', () {
      final api = _FakeEvidenceApi(
        const [],
        error: const FormatException('boom'),
      );

      expect(
        loadStopEvidence(
          store: _FakeLocalWriteStore(twoPendingPhotos()),
          api: api,
          routeId: 'route-A',
          executionId: 'exec-1',
        ),
        throwsFormatException,
      );
    });
  });
}
