import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/appeals/appeal_api.dart';

Map<String, dynamic> _eligibleJson() => {
  'route_stop_id': 'rs-1',
  'service_point_id': 'sp-1',
  'service_point_name': 'Sala 101',
  'building_name': 'Bloco CAA',
  'floor_label': 'Térreo',
  'released_at': '2026-10-21T14:00:00Z',
  'release_reason': 'LOCATION_SILENCE',
  'deadline': '2026-10-23T14:00:00Z',
};

Map<String, dynamic> _appealJson({String status = 'PENDING'}) => {
  'id': 'ap-1',
  'route_stop_id': 'rs-1',
  'field_worker_id': 'fw-1',
  'field_worker_name': 'Ana',
  'service_point_id': 'sp-1',
  'service_point_name': 'Sala 101',
  'building_name': 'Bloco CAA',
  'released_at': '2026-10-21T14:00:00Z',
  'release_reason': 'LEFT_CAMPUS',
  'reason': 'NO_SIGNAL',
  'note': null,
  'claimed_executed_at': '2026-10-21T13:05:00Z',
  'status': status,
  'filed_at': '2026-10-21T15:00:00Z',
  'reviewed_at': status == 'PENDING' ? null : '2026-10-22T09:00:00Z',
  'reviewed_by_name': status == 'PENDING' ? null : 'Gestora',
  'review_note': status == 'REJECTED' ? 'Sem evidência.' : null,
};

void main() {
  test('eligible parses the stops the worker may contest', () async {
    final adapter = _FakeAdapter(statusCode: 200, body: [_eligibleJson()]);

    final stops = await _api(adapter).eligible();

    expect(adapter.lastPath, '/appeals/eligible');
    final stop = stops.single;
    expect(stop.routeStopId, 'rs-1');
    expect(stop.servicePointName, 'Sala 101');
    expect(stop.buildingName, 'Bloco CAA');
    expect(stop.floorLabel, 'Térreo');
    expect(stop.releaseReason, 'LOCATION_SILENCE');
    expect(stop.deadline, DateTime.utc(2026, 10, 23, 14));
  });

  test('mine parses status and the manager review', () async {
    final adapter = _FakeAdapter(
      statusCode: 200,
      body: [_appealJson(status: 'REJECTED')],
    );

    final appeals = await _api(adapter).mine();

    expect(adapter.lastPath, '/appeals/mine');
    final appeal = appeals.single;
    expect(appeal.status, 'REJECTED');
    expect(appeal.servicePointName, 'Sala 101');
    expect(appeal.reviewNote, 'Sem evidência.');
    expect(appeal.reviewedByName, 'Gestora');
    expect(appeal.buildingName, 'Bloco CAA');
    expect(appeal.filedAt, DateTime.utc(2026, 10, 21, 15));
  });

  test('file posts the declaration with its idempotency key', () async {
    final adapter = _FakeAdapter(statusCode: 201, body: _appealJson());

    await _api(adapter).file(
      routeStopId: 'rs-1',
      reason: 'NO_SIGNAL',
      note: 'Subsolo sem sinal.',
      claimedExecutedAt: DateTime.utc(2026, 10, 21, 13, 5),
      idempotencyKey: 'key-1',
    );

    expect(adapter.lastPath, '/appeals');
    expect(adapter.lastBody, {
      'route_stop_id': 'rs-1',
      'reason': 'NO_SIGNAL',
      'note': 'Subsolo sem sinal.',
      'claimed_executed_at': '2026-10-21T13:05:00.000Z',
      'idempotency_key': 'key-1',
    });
  });

  test(
    'a 409 NOT_APPEALABLE surfaces as NotAppealableException with its code',
    () async {
      final adapter = _FakeAdapter(
        statusCode: 409,
        body: {
          'detail': {
            'code': 'NOT_APPEALABLE',
            'detail': 'Route stop "rs-1" cannot be appealed (WINDOW_EXPIRED).',
            'reason_code': 'WINDOW_EXPIRED',
          },
        },
      );

      final filing = _api(adapter).file(
        routeStopId: 'rs-1',
        reason: 'OTHER',
        note: null,
        claimedExecutedAt: null,
        idempotencyKey: 'key-1',
      );

      await expectLater(
        filing,
        throwsA(
          isA<NotAppealableException>().having(
            (e) => e.reasonCode,
            'reasonCode',
            'WINDOW_EXPIRED',
          ),
        ),
      );
    },
  );

  test('any other failure is rethrown as is', () async {
    final adapter = _FakeAdapter(statusCode: 500, body: {'detail': 'boom'});

    final filing = _api(adapter).file(
      routeStopId: 'rs-1',
      reason: 'OTHER',
      note: null,
      claimedExecutedAt: null,
      idempotencyKey: 'key-1',
    );

    await expectLater(filing, throwsA(isA<DioException>()));
  });
}

DioAppealApi _api(_FakeAdapter adapter) => DioAppealApi(
  Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = adapter,
);

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final Object body;
  String? lastPath;
  Object? lastBody;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastPath = options.path;
    lastBody = options.data;
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
