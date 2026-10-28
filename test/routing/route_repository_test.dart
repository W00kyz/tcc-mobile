import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/route_snapshot_cache.dart';

Map<String, dynamic> _stopPayload({
  required String id,
  required int orderIndex,
  int batchNumber = 2,
  String status = 'PENDING',
  String? releaseReason,
}) => {
  'id': id,
  'order_index': orderIndex,
  'batch_number': batchNumber,
  'status': status,
  'release_reason': releaseReason,
  'service_point_id': 'sp-$id',
  'service_point_name': 'Sala $id',
  'floor_label': 'Térreo',
  'building_id': 'b-caa',
  'building_name': 'CAA',
  'done_at': null,
  'latitude': -7.21,
  'longitude': -35.91,
  'distance_from_prev_m': null,
  'duration_from_prev_s': null,
  'leg_geometry': null,
  'service_type_id': null,
  'service_type_name': null,
  'form': null,
};

/// A `RouteOut` in its second batch: batch 1 had one DONE stop and one stop
/// released by an impediment; batch 2 is open.
Map<String, dynamic> _routePayload() => {
  'id': 'r1',
  'field_worker_id': 'fw1',
  'field_worker_name': 'João',
  'route_date': '2026-10-20',
  'status': 'IN_PROGRESS',
  'started_at': '2026-10-20T11:15:00Z',
  'routing_degraded': false,
  'current_batch': 2,
  'stops': [
    _stopPayload(id: 'a', orderIndex: 1, batchNumber: 1, status: 'DONE'),
    _stopPayload(
      id: 'b',
      orderIndex: 2,
      batchNumber: 1,
      status: 'RELEASED',
      releaseReason: 'IMPEDIMENT',
    ),
    {
      ..._stopPayload(id: 'c', orderIndex: 3),
      'distance_from_prev_m': 1234.5,
      'duration_from_prev_s': 180.0,
      'leg_geometry': [
        [-35.91, -7.21],
        [-35.92, -7.22],
      ],
    },
    _stopPayload(id: 'd', orderIndex: 4, status: 'IN_PROGRESS'),
  ],
};

Map<String, dynamic> _myDayPayload({Map<String, dynamic>? route}) => {
  'service_day': true,
  'route': route,
  'position_report_interval_seconds': 60,
  'location_silence_warning_minutes': 30,
  'location_silence_release_minutes': 45,
};

Dio _dioAnswering(
  int statusCode,
  Object body, {
  void Function(RequestOptions)? onRequest,
}) =>
    Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(
        statusCode: statusCode,
        body: body,
        onRequest: onRequest,
      );

Dio _offlineDio() =>
    Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _OfflineAdapter();

Map<String, Object> _refusal(String code) => {
  'detail': {'code': code, 'detail': 'refused'},
};

final _capturedAt = DateTime.utc(2026, 10, 20, 11, 15);

void main() {
  group('fetchMyDay', () {
    test('parses the day and its limits before any route exists', () async {
      final repository = DioRouteRepository(
        _dioAnswering(200, _myDayPayload()),
      );

      final day = await repository.fetchMyDay();

      expect(day.serviceDay, isTrue);
      expect(day.route, isNull);
      expect(day.positionIntervalSeconds, 60);
      expect(day.silenceWarningMinutes, 30);
      expect(day.silenceReleaseMinutes, 45);
    });

    test('parses the route, its batch and every stop', () async {
      final repository = DioRouteRepository(
        _dioAnswering(200, _myDayPayload(route: _routePayload())),
      );

      final route = (await repository.fetchMyDay()).route!;

      expect(route.id, 'r1');
      expect(route.status, 'IN_PROGRESS');
      expect(route.routeDate, DateTime.parse('2026-10-20'));
      expect(route.currentBatch, 2);
      expect(route.stops.map((s) => s.id), ['a', 'b', 'c', 'd']);
      expect(route.stops[1].batchNumber, 1);
      expect(route.stops[1].status, 'RELEASED');
      expect(route.stops[1].releaseReason, 'IMPEDIMENT');
      expect(route.stops[2].releaseReason, isNull);
      expect(route.stops[2].distanceFromPrevM, 1234.5);
      expect(route.stops[2].durationFromPrevS, 180.0);
      expect(route.stops[2].legGeometry, [
        [-35.91, -7.21],
        [-35.92, -7.22],
      ]);
    });

    test('parses the building, floor and done_at of a stop', () async {
      final payload = _routePayload();
      final stops = payload['stops'] as List<dynamic>;
      (stops[0] as Map<String, dynamic>)['done_at'] =
          '2026-10-20T10:20:00+00:00';
      final repository = DioRouteRepository(
        _dioAnswering(200, _myDayPayload(route: payload)),
      );

      final route = (await repository.fetchMyDay()).route!;

      expect(route.stops[0].buildingId, 'b-caa');
      expect(route.stops[0].buildingName, 'CAA');
      expect(route.stops[0].floorLabel, 'Térreo');
      expect(route.stops[0].doneAt, DateTime.parse('2026-10-20T10:20:00Z'));
      expect(route.stops[1].doneAt, isNull);
    });

    test('derives the done count over every batch of the day', () async {
      final repository = DioRouteRepository(
        _dioAnswering(200, _myDayPayload(route: _routePayload())),
      );

      final route = (await repository.fetchMyDay()).route!;

      expect(route.doneToday, 1);
    });

    test("parses a stop's service type when present", () async {
      final route = _routePayload();
      final stops = (route['stops'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      stops[2]['service_type_id'] = 'st1';
      stops[2]['service_type_name'] = 'Limpeza';
      final repository = DioRouteRepository(
        _dioAnswering(200, _myDayPayload(route: route)),
      );

      final stop = (await repository.fetchMyDay()).route!.stops[2];

      expect(stop.serviceTypeId, 'st1');
      expect(stop.serviceTypeName, 'Limpeza');
    });
    test(
      'requires_evidence is read from the stop, false when absent',
      () async {
        final route = _routePayload();
        final stops = (route['stops'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        stops[2]['requires_evidence'] = true;
        final repository = DioRouteRepository(
          _dioAnswering(200, _myDayPayload(route: route)),
        );

        final parsed = (await repository.fetchMyDay()).route!.stops;

        expect(parsed[2].requiresEvidence, isTrue);
        expect(parsed[0].requiresEvidence, isFalse);
      },
    );
  });

  group('current batch', () {
    RouteSummary route() => RouteSummary.fromJson(_routePayload());

    test('lists only the current batch, without released stops', () {
      final payload = _routePayload();
      (payload['stops'] as List<dynamic>).add(
        _stopPayload(
          id: 'e',
          orderIndex: 5,
          status: 'RELEASED',
          releaseReason: 'LEFT_CAMPUS',
        ),
      );

      final stops = RouteSummary.fromJson(payload).currentBatchStops;

      expect(stops.map((s) => s.id), ['c', 'd']);
    });

    test('is open while a stop is neither done nor released', () {
      expect(route().currentBatchClosed(doneLocally: const {'c'}), isFalse);
    });

    test('closes once every stop is done here or on the server', () {
      expect(route().currentBatchClosed(doneLocally: const {'c', 'd'}), isTrue);
    });

    test('a stop released by the server counts as closed', () {
      final payload = _routePayload();
      final stops = (payload['stops'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      stops[2]['status'] = 'RELEASED';
      stops[3]['status'] = 'DONE';

      expect(RouteSummary.fromJson(payload).currentBatchClosed(), isTrue);
    });

    test('the latest release reason explains a paused route', () {
      final payload = _routePayload();
      final stops = (payload['stops'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      stops[3]['status'] = 'RELEASED';
      stops[3]['release_reason'] = 'LOCATION_SILENCE';

      expect(
        RouteSummary.fromJson(payload).latestReleaseReason,
        'LOCATION_SILENCE',
      );
    });
  });

  group('offline snapshot (RF35, RNF21)', () {
    test('a successful fetch is saved and served back offline', () async {
      final cache = InMemoryRouteSnapshotCache();
      await DioRouteRepository(
        _dioAnswering(200, _myDayPayload(route: _routePayload())),
        cache: cache,
        userId: 'u1',
      ).fetchMyDay();

      final day = await DioRouteRepository(
        _offlineDio(),
        cache: cache,
        userId: 'u1',
      ).fetchMyDay();

      expect(day.route!.id, 'r1');
      expect(day.route!.stops, hasLength(4));
    });

    test("another user's snapshot is never served", () async {
      final cache = InMemoryRouteSnapshotCache()
        ..snapshots['u1'] = jsonEncode(_myDayPayload(route: _routePayload()));

      await expectLater(
        DioRouteRepository(
          _offlineDio(),
          cache: cache,
          userId: 'u2',
        ).fetchMyDay(),
        throwsA(isA<OfflineException>()),
      );
    });

    test('an HTTP error is a real answer, not a reason to use the cache', () {
      final cache = InMemoryRouteSnapshotCache()
        ..snapshots['u1'] = jsonEncode(_myDayPayload(route: _routePayload()));

      expect(
        DioRouteRepository(
          _dioAnswering(500, <String, Object>{}),
          cache: cache,
          userId: 'u1',
        ).fetchMyDay(),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('startOrResume', () {
    test('posts the position and parses the allocation', () async {
      late RequestOptions request;
      final repository = DioRouteRepository(
        _dioAnswering(
          200,
          {'route': _routePayload(), 'pool_empty': false},
          onRequest: (options) => request = options,
        ),
      );

      final result = await repository.startOrResume(
        lat: -7.215,
        lng: -35.91,
        capturedAt: _capturedAt,
      );

      expect(request.path, '/routes/start');
      expect(request.data, {
        'latitude': -7.215,
        'longitude': -35.91,
        'captured_at': '2026-10-20T11:15:00.000Z',
      });
      expect(result.poolEmpty, isFalse);
      expect(result.route.currentBatch, 2);
    });

    test('maps each 409 code to its typed refusal', () async {
      final cases = <String, TypeMatcher<Object>>{
        'NOT_A_SERVICE_DAY': isA<NotAServiceDayException>(),
        'WORKDAY_OVER': isA<WorkdayOverException>(),
        'OUTSIDE_CAMPUS': isA<OutsideCampusException>(),
        'ROUTE_DONE': isA<RouteDoneException>(),
      };
      for (final MapEntry(key: code, value: matcher) in cases.entries) {
        final repository = DioRouteRepository(
          _dioAnswering(409, _refusal(code)),
        );
        await expectLater(
          repository.startOrResume(lat: 0, lng: 0, capturedAt: _capturedAt),
          throwsA(matcher),
          reason: code,
        );
      }
    });

    test('no HTTP response at all is an OfflineException', () {
      expect(
        DioRouteRepository(
          _offlineDio(),
        ).startOrResume(lat: 0, lng: 0, capturedAt: _capturedAt),
        throwsA(isA<OfflineException>()),
      );
    });

    test('a 403 without a machine code reaches the caller unchanged', () {
      expect(
        DioRouteRepository(
          _dioAnswering(403, {'detail': 'Accept the privacy notice first.'}),
        ).startOrResume(lat: 0, lng: 0, capturedAt: _capturedAt),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            403,
          ),
        ),
      );
    });
  });

  group('nextBatch', () {
    test('posts to the route and reads an empty pool', () async {
      late RequestOptions request;
      final payload = {..._routePayload(), 'status': 'DONE'};
      final repository = DioRouteRepository(
        _dioAnswering(
          200,
          {'route': payload, 'pool_empty': true},
          onRequest: (options) => request = options,
        ),
      );

      final result = await repository.nextBatch(
        'r1',
        lat: -7.215,
        lng: -35.91,
        capturedAt: _capturedAt,
      );

      expect(request.path, '/routes/r1/next-batch');
      expect((request.data as Map)['captured_at'], '2026-10-20T11:15:00.000Z');
      expect(result.poolEmpty, isTrue);
      expect(result.route.status, 'DONE');
    });

    test('a retry after a lost empty-pool answer is a RouteDoneException', () {
      expect(
        DioRouteRepository(
          _dioAnswering(409, _refusal('ROUTE_DONE')),
        ).nextBatch('r1', lat: 0, lng: 0, capturedAt: _capturedAt),
        throwsA(isA<RouteDoneException>()),
      );
    });

    test('no HTTP response at all is an OfflineException', () {
      expect(
        DioRouteRepository(
          _offlineDio(),
        ).nextBatch('r1', lat: 0, lng: 0, capturedAt: _capturedAt),
        throwsA(isA<OfflineException>()),
      );
    });
  });
}

/// Every request fails before any HTTP response — the device is offline.
class _OfflineAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'offline',
    );
  }
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.statusCode, required this.body, this.onRequest});

  final int statusCode;
  final Object body;
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
