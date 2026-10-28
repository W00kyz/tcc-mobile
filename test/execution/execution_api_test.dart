import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/execution_api.dart';

void main() {
  test(
    'checkIn posts the request body and parses a successful response',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      late RequestOptions captured;
      dio.httpClientAdapter = _FakeAdapter(
        statusCode: 201,
        body: {
          'execution_id': 'e1',
          'route_stop_id': 's1',
          'geo_validation': 'INSIDE',
          'validation_flags': ['MISSING_GPS'],
          'review_status': 'AUTO_APPROVED',
        },
        onRequest: (options) => captured = options,
      );
      final api = DioExecutionApi(dio);

      final response = await api.checkIn(
        executionId: 'exec-supplied-1',
        qrPayload: 'v1.floor.1.sig',
        latitude: -7.2,
        longitude: -35.9,
        scannedAt: DateTime.utc(2026, 8, 25, 8, 20),
        idempotencyKey: 'idem-1',
        routeStopId: 'stop-hint',
        clientClockOffsetSeconds: 12.5,
      );
      final result = response.result;

      final body = captured.data as Map;
      expect(body['execution_id'], 'exec-supplied-1');
      expect(body['qr_payload'], 'v1.floor.1.sig');
      expect(body['latitude'], -7.2);
      expect(body['longitude'], -35.9);
      expect(body['scanned_at'], '2026-08-25T08:20:00.000Z');
      expect(body['idempotency_key'], 'idem-1');
      expect(body['route_stop_id'], 'stop-hint');
      expect(body['client_clock_offset_seconds'], 12.5);
      expect(result.routeStopId, 's1');
      expect(result.executionId, 'e1');
      expect(result.geoValidation, 'INSIDE');
      expect(result.flags, ['MISSING_GPS']);
    },
  );

  test(
    'checkIn converts a 409 with nested detail.candidates into '
    'AmbiguousRoomException',
    () async {
      // The FastAPI HTTPException(409, detail={...}) envelope: the outer
      // "detail" is FastAPI's own wrapper, the inner "detail"+"candidates" is
      // this app's payload (backend/app/api/checkins.py).
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = _FakeAdapter(
          statusCode: 409,
          body: {
            'detail': {
              'detail':
                  'Multiple service points on this floor match; '
                  'choose one.',
              'candidates': [
                {
                  'route_stop_id': 's1',
                  'service_point_id': 'sp1',
                  'name': 'Sala 101',
                  'distance_m': 3.2,
                },
                {
                  'route_stop_id': 's2',
                  'service_point_id': 'sp2',
                  'name': 'Sala 102',
                  'distance_m': null,
                },
              ],
            },
          },
        );
      final api = DioExecutionApi(dio);

      await expectLater(
        api.checkIn(
          executionId: 'exec-1',
          qrPayload: 'v1.floor.1.sig',
          scannedAt: DateTime.utc(2026, 8, 25),
          idempotencyKey: 'idem-1',
        ),
        throwsA(
          isA<AmbiguousRoomException>().having(
            (e) => e.candidates,
            'candidates',
            [
              isA<RoomCandidate>()
                  .having((c) => c.routeStopId, 'routeStopId', 's1')
                  .having((c) => c.servicePointId, 'servicePointId', 'sp1')
                  .having((c) => c.name, 'name', 'Sala 101')
                  .having((c) => c.distanceM, 'distanceM', 3.2),
              isA<RoomCandidate>()
                  .having((c) => c.routeStopId, 'routeStopId', 's2')
                  .having((c) => c.distanceM, 'distanceM', isNull),
            ],
          ),
        ),
      );
    },
  );

  test(
    'checkIn leaves a plain-string-detail 409 (route not started/cancelled) '
    'as an unhandled DioException',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = _FakeAdapter(
          statusCode: 409,
          body: {'detail': 'Route is not IN_PROGRESS.'},
        );
      final api = DioExecutionApi(dio);

      await expectLater(
        api.checkIn(
          executionId: 'exec-1',
          qrPayload: 'v1.floor.1.sig',
          scannedAt: DateTime.utc(2026, 8, 25),
          idempotencyKey: 'idem-1',
        ),
        throwsA(isA<DioException>()),
      );
    },
  );

  test(
    'checkOut posts the request body and parses a successful response',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      late RequestOptions captured;
      dio.httpClientAdapter = _FakeAdapter(
        statusCode: 201,
        body: {
          'execution_id': 'e1',
          'route_stop_id': 's1',
          'checked_out_at': '2026-08-25T08:40:00.000Z',
          'validation_flags': ['ROOM_CHOSEN_MANUALLY'],
          'review_status': 'AUTO_APPROVED',
        },
        onRequest: (options) => captured = options,
      );
      final api = DioExecutionApi(dio);

      final result = (await api.checkOut(
        executionId: 'exec-out-supplied',
        qrPayload: 'v1.floor.1.sig',
        latitude: -7.2,
        longitude: -35.9,
        scannedAt: DateTime.utc(2026, 8, 25, 8, 40),
        checkoutIdempotencyKey: 'idem-out-1',
        routeStopId: 's1',
      )).result;

      final body = captured.data as Map;
      expect(body['execution_id'], 'exec-out-supplied');
      expect(body['qr_payload'], 'v1.floor.1.sig');
      expect(body['latitude'], -7.2);
      expect(body['longitude'], -35.9);
      expect(body['scanned_at'], '2026-08-25T08:40:00.000Z');
      expect(body['checkout_idempotency_key'], 'idem-out-1');
      expect(body['route_stop_id'], 's1');
      expect(result.routeStopId, 's1');
      expect(result.executionId, 'e1');
      expect(result.checkedOutAt, DateTime.utc(2026, 8, 25, 8, 40));
      expect(result.flags, ['ROOM_CHOSEN_MANUALLY']);
    },
  );

  test(
    'checkOut converts a 409 with nested detail.candidates into '
    'AmbiguousRoomException',
    () async {
      // Ruling 16: check-out is per-stop so this is rare in practice, but the
      // backend's envelope is byte-for-byte the same nesting as check-in's
      // (backend/app/api/checkouts.py's _ambiguous_conflict), so the parsing
      // must mirror checkIn's.
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = _FakeAdapter(
          statusCode: 409,
          body: {
            'detail': {
              'detail':
                  'Multiple open check-ins on this floor match; choose one.',
              'candidates': [
                {
                  'route_stop_id': 's1',
                  'service_point_id': 'sp1',
                  'name': 'Sala 101',
                  'distance_m': 3.2,
                },
              ],
            },
          },
        );
      final api = DioExecutionApi(dio);

      await expectLater(
        api.checkOut(
          executionId: 'exec-1',
          qrPayload: 'v1.floor.1.sig',
          scannedAt: DateTime.utc(2026, 8, 25),
          checkoutIdempotencyKey: 'idem-out-1',
          routeStopId: 's1',
        ),
        throwsA(
          isA<AmbiguousRoomException>().having(
            (e) => e.candidates,
            'candidates',
            [
              isA<RoomCandidate>()
                  .having((c) => c.routeStopId, 'routeStopId', 's1')
                  .having((c) => c.name, 'name', 'Sala 101'),
            ],
          ),
        ),
      );
    },
  );

  test(
    'checkOut leaves a 422 NO_OPEN_CHECKIN plain-string-detail response as '
    'an unhandled DioException, not AmbiguousRoomException',
    () async {
      // Explicitly required by the Task 18 brief: a 422 must never be
      // misparsed as ambiguous even though it also carries a "detail" key —
      // _ambiguousRoomCandidates only fires on statusCode == 409.
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = _FakeAdapter(
          statusCode: 422,
          body: {
            'detail': 'Route "r1" has no open check-in on floor "f1".',
          },
        );
      final api = DioExecutionApi(dio);

      await expectLater(
        api.checkOut(
          executionId: 'exec-1',
          qrPayload: 'v1.floor.1.sig',
          scannedAt: DateTime.utc(2026, 8, 25),
          checkoutIdempotencyKey: 'idem-out-1',
          routeStopId: 's1',
        ),
        throwsA(
          isA<DioException>().having(
            (e) => e,
            'is not AmbiguousRoomException',
            isNot(isA<AmbiguousRoomException>()),
          ),
        ),
      );
    },
  );

  test(
    'reportImpediment posts the body to /routes/{routeId}/impediments',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      late RequestOptions captured;
      dio.httpClientAdapter = _FakeAdapter(
        statusCode: 201,
        body: {'id': 'imp-1', 'status': 'OPEN'},
        onRequest: (options) => captured = options,
      );
      final api = DioExecutionApi(dio);

      await api.reportImpediment(
        routeId: 'route-1',
        routeStopId: 'stop-1',
        scope: 'STOP',
        reason: 'ROOM_LOCKED',
        note: 'Sala trancada.',
        reportedAt: DateTime.utc(2026, 8, 25, 8, 20),
      );

      expect(captured.path, '/routes/route-1/impediments');
      final body = captured.data as Map;
      expect(body['route_stop_id'], 'stop-1');
      expect(body['scope'], 'STOP');
      expect(body['reason'], 'ROOM_LOCKED');
      expect(body['note'], 'Sala trancada.');
      expect(body['reported_at'], '2026-08-25T08:20:00.000Z');
    },
  );

  test(
    'reportImpediment sends a null route_stop_id for a ROUTE_REMAINDER scope',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      late RequestOptions captured;
      dio.httpClientAdapter = _FakeAdapter(
        statusCode: 201,
        body: {'id': 'imp-1', 'status': 'OPEN'},
        onRequest: (options) => captured = options,
      );
      final api = DioExecutionApi(dio);

      await api.reportImpediment(
        routeId: 'route-1',
        routeStopId: null,
        scope: 'ROUTE_REMAINDER',
        reason: 'VEHICLE_BREAKDOWN',
        reportedAt: DateTime.utc(2026, 8, 25, 8, 20),
      );

      final body = captured.data as Map;
      expect(body.containsKey('route_stop_id'), isTrue);
      expect(body['route_stop_id'], isNull);
      expect(body['note'], isNull);
      expect(body['scope'], 'ROUTE_REMAINDER');
    },
  );
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
