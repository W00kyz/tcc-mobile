import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/api/api_client.dart' show photoUploadSendTimeout;
import 'package:route_monitor/execution/evidence_api.dart';

void main() {
  test('uploadPhoto posts multipart file, sha256 and captured_at', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    late RequestOptions captured;
    dio.httpClientAdapter = _FakeAdapter(
      statusCode: 201,
      body: const {
        'id': 'e1',
        'kind': 'PHOTO',
        'text_body': null,
        'captured_at': '2026-08-25T08:20:00.000Z',
        'content_type': 'image/jpeg',
        'byte_size': 5,
        'created_at': '2026-08-25T08:20:01.000Z',
        'content_url': '/evidence/e1/content',
      },
      onRequest: (options) => captured = options,
    );
    final api = DioEvidenceApi(dio);

    await api.uploadPhoto(
      executionId: 'exec-1',
      bytes: Uint8List.fromList([1, 2, 3]),
      sha256: 'deadbeef',
      capturedAt: DateTime.utc(2026, 8, 25, 8, 20),
      idempotencyKey: 'idem-photo-1',
    );

    expect(captured.path, '/executions/exec-1/evidence/photo');
    final body = captured.data as FormData;
    final fields = {for (final f in body.fields) f.key: f.value};
    expect(fields['sha256'], 'deadbeef');
    expect(fields['captured_at'], '2026-08-25T08:20:00.000Z');
    expect(fields['idempotency_key'], 'idem-photo-1');
    expect(body.files.single.key, 'file');
    expect(body.files.single.value.filename, 'evidence.jpg');
    // A photo on a weak field link needs longer than the app-wide budget.
    expect(captured.sendTimeout, photoUploadSendTimeout);
  });

  test('uploadNote posts text_body and captured_at as JSON', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    late RequestOptions captured;
    dio.httpClientAdapter = _FakeAdapter(
      statusCode: 201,
      body: const {
        'id': 'e2',
        'kind': 'NOTE',
        'text_body': 'Vazamento no teto.',
        'captured_at': '2026-08-25T08:20:00.000Z',
        'content_type': null,
        'byte_size': null,
        'created_at': '2026-08-25T08:20:01.000Z',
        'content_url': null,
      },
      onRequest: (options) => captured = options,
    );
    final api = DioEvidenceApi(dio);

    await api.uploadNote(
      executionId: 'exec-1',
      textBody: 'Vazamento no teto.',
      capturedAt: DateTime.utc(2026, 8, 25, 8, 20),
      idempotencyKey: 'idem-note-1',
    );

    expect(captured.path, '/executions/exec-1/evidence/note');
    final body = captured.data as Map;
    expect(body['text_body'], 'Vazamento no teto.');
    expect(body['captured_at'], '2026-08-25T08:20:00.000Z');
    expect(body['idempotency_key'], 'idem-note-1');
  });

  test('listEvidence parses every EvidenceItemOut field', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeListAdapter([
        {
          'id': 'e1',
          'kind': 'PHOTO',
          'text_body': null,
          'captured_at': '2026-08-25T08:20:00.000Z',
          'content_type': 'image/jpeg',
          'byte_size': 51200,
          'created_at': '2026-08-25T08:20:01.000Z',
          'content_url': '/evidence/e1/content',
          'idempotency_key': 'key-e1',
        },
        {
          'id': 'e2',
          'kind': 'NOTE',
          'text_body': 'Vazamento no teto.',
          'captured_at': '2026-08-25T08:21:00.000Z',
          'content_type': null,
          'byte_size': null,
          'created_at': '2026-08-25T08:21:01.000Z',
          'content_url': null,
          'idempotency_key': null,
        },
      ]);
    final api = DioEvidenceApi(dio);

    final items = await api.listEvidence('exec-1');

    expect(items, hasLength(2));
    expect(items[0].id, 'e1');
    expect(items[0].kind, 'PHOTO');
    expect(items[0].contentType, 'image/jpeg');
    expect(items[0].byteSize, 51200);
    expect(items[0].contentUrl, '/evidence/e1/content');
    // The upload's idempotency key travels with the item.
    expect(items[0].idempotencyKey, 'key-e1');
    expect(items[1].idempotencyKey, isNull);
    expect(items[1].kind, 'NOTE');
    expect(items[1].textBody, 'Vazamento no teto.');
    expect(items[1].contentUrl, isNull);
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.statusCode, required this.body, this.onRequest});
  final int statusCode;
  final Map<String, dynamic> body;
  final void Function(RequestOptions)? onRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    onRequest?.call(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _FakeListAdapter implements HttpClientAdapter {
  _FakeListAdapter(this.body);
  final List<Map<String, dynamic>> body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
