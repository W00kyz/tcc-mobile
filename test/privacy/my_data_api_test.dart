import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/privacy/my_data_api.dart';

Map<String, dynamic> _aggregate({Object? fieldWorker = _sentinel}) => {
  'profile': {
    'id': 'u-1',
    'email': 'ana@example.com',
    'name': 'Ana Field',
    'role': 'FIELD_WORKER',
    'is_active': true,
    'created_at': '2026-01-02T10:00:00Z',
  },
  'field_worker': fieldWorker == _sentinel
      ? {
          'id': 'fw-1',
          'full_name': 'Ana da Silva',
          'contractor_company_id': 'co-9',
          'service_type_ids': ['st-1', 'st-2'],
        }
      : fieldWorker,
  'consent_history': [
    {'notice_version': 2, 'accepted_at': '2026-02-01T08:00:00Z'},
    {'notice_version': 3, 'accepted_at': '2026-03-01T08:00:00Z'},
  ],
  'auth_events': [
    {
      'event': 'LOGIN',
      'ip_address': '10.0.0.1',
      'created_at': '2026-03-02T09:00:00Z',
    },
    {
      'event': 'LOGIN_FAILED',
      'ip_address': null,
      'created_at': '2026-03-03T09:00:00Z',
    },
  ],
  'executions_summary': {
    'total': 12,
    'first_at': '2026-01-05T07:00:00Z',
    'last_at': '2026-03-01T17:00:00Z',
  },
  'evidence_summary': {'total_items': 40, 'total_bytes': 2048},
  'positions_summary': {
    'total': 900,
    'first_at': '2026-01-05T07:00:00Z',
    'last_at': '2026-03-01T17:00:00Z',
  },
  'notifications_summary': {'total': 7, 'unread': 2},
};

const _sentinel = Object();

DioMyDataApi _apiReturning(Map<String, dynamic> body) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = _FakeAdapter(statusCode: 200, body: body);
  return DioMyDataApi(dio);
}

void main() {
  test('fetch parses every section of the aggregate', () async {
    final data = await _apiReturning(_aggregate()).fetch();

    expect(data.profile.email, 'ana@example.com');
    expect(data.profile.role, 'FIELD_WORKER');
    expect(data.profile.isActive, isTrue);
    expect(data.profile.createdAt, DateTime.utc(2026, 1, 2, 10));

    expect(data.fieldWorker, isNotNull);
    expect(data.fieldWorker!.fullName, 'Ana da Silva');
    expect(data.fieldWorker!.serviceTypeIds, ['st-1', 'st-2']);

    expect(data.consentHistory, hasLength(2));
    expect(data.consentHistory.first.noticeVersion, 2);
    expect(
      data.consentHistory.last.acceptedAt,
      DateTime.utc(2026, 3, 1, 8),
    );

    expect(data.authEvents, hasLength(2));
    expect(data.authEvents.first.event, 'LOGIN');
    expect(data.authEvents.first.ipAddress, '10.0.0.1');
    expect(data.authEvents.last.ipAddress, isNull);

    expect(data.executionsSummary.total, 12);
    expect(data.executionsSummary.firstAt, DateTime.utc(2026, 1, 5, 7));
    expect(data.evidenceSummary.totalItems, 40);
    expect(data.evidenceSummary.totalBytes, 2048);
    expect(data.positionsSummary.total, 900);
    expect(data.notificationsSummary.total, 7);
    expect(data.notificationsSummary.unread, 2);
  });

  test('fetch tolerates a null field_worker', () async {
    final data = await _apiReturning(_aggregate(fieldWorker: null)).fetch();

    expect(data.fieldWorker, isNull);
    expect(data.profile.email, 'ana@example.com');
  });

  test('fetch keeps null first_at/last_at as null', () async {
    final body = _aggregate();
    body['positions_summary'] = {
      'total': 0,
      'first_at': null,
      'last_at': null,
    };
    final data = await _apiReturning(body).fetch();

    expect(data.positionsSummary.total, 0);
    expect(data.positionsSummary.firstAt, isNull);
    expect(data.positionsSummary.lastAt, isNull);
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final dynamic body;

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
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
