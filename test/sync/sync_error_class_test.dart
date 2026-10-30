import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/local/pending_operation.dart';
import 'package:route_monitor/sync/sync_error_class.dart';

DioException _dio(int status, Object? body) {
  final options = RequestOptions(path: '/location-completions');
  return DioException(
    requestOptions: options,
    response: Response<dynamic>(
      requestOptions: options,
      statusCode: status,
      data: body,
    ),
  );
}

Map<String, dynamic> _detail(String code) => {
  'detail': {'code': code, 'detail': 'x'},
};

const PendingOpKind _completion = PendingOpKind.locationCompletion;

void main() {
  group('classifySyncError for a location completion', () {
    test('a typed refusal is rejected', () {
      const error = LocationRefusedException(
        code: 'OUT_OF_RADIUS',
        distanceM: 120.5,
        radiusM: 50,
      );

      expect(
        classifySyncError(error, kind: _completion),
        SyncErrorClass.rejected,
      );
    });

    test('a raw 422 OUT_OF_RADIUS is rejected', () {
      expect(
        classifySyncError(
          _dio(422, _detail('OUT_OF_RADIUS')),
          kind: _completion,
        ),
        SyncErrorClass.rejected,
      );
    });

    test('a raw 422 LOCATION_REQUIRED is rejected', () {
      expect(
        classifySyncError(
          _dio(422, _detail('LOCATION_REQUIRED')),
          kind: _completion,
        ),
        SyncErrorClass.rejected,
      );
    });

    test('a 422 with any other code stays hard', () {
      expect(
        classifySyncError(
          _dio(422, _detail('NOT_A_LOCATION_STOP')),
          kind: _completion,
        ),
        SyncErrorClass.hard,
      );
    });

    test('a 409 saying "already" is already applied', () {
      expect(
        classifySyncError(
          _dio(409, {'detail': 'Completion already applied'}),
          kind: _completion,
        ),
        SyncErrorClass.alreadyApplied,
      );
    });

    test('a 409 STOP_RELEASED is not rejected (the worker parks it)', () {
      final error = _dio(409, {
        'detail': {
          'code': 'STOP_RELEASED',
          'route_stop_id': 's1',
          'release_reason': 'IMPEDIMENT',
          'appealable': true,
        },
      });

      expect(classifySyncError(error, kind: _completion), SyncErrorClass.hard);
    });
  });

  group('only a location completion can be rejected', () {
    final raw = _dio(422, _detail('OUT_OF_RADIUS'));
    const typed = LocationRefusedException(
      code: 'OUT_OF_RADIUS',
      distanceM: 120.5,
      radiusM: 50,
    );

    for (final kind in PendingOpKind.values) {
      if (kind == _completion) continue;
      test('a raw 422 OUT_OF_RADIUS on a ${kind.name} row stays hard', () {
        expect(classifySyncError(raw, kind: kind), SyncErrorClass.hard);
      });

      test('a typed refusal on a ${kind.name} row stays hard', () {
        expect(classifySyncError(typed, kind: kind), SyncErrorClass.hard);
      });
    }
  });
}
