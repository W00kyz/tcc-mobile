import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/execution_api.dart';
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

void main() {
  group('classifySyncError for a location completion', () {
    test('a typed refusal is rejected', () {
      const error = LocationRefusedException(
        code: 'OUT_OF_RADIUS',
        distanceM: 120.5,
        radiusM: 50,
      );

      expect(classifySyncError(error), SyncErrorClass.rejected);
    });

    test('a raw 422 OUT_OF_RADIUS is rejected', () {
      expect(
        classifySyncError(_dio(422, _detail('OUT_OF_RADIUS'))),
        SyncErrorClass.rejected,
      );
    });

    test('a raw 422 LOCATION_REQUIRED is rejected', () {
      expect(
        classifySyncError(_dio(422, _detail('LOCATION_REQUIRED'))),
        SyncErrorClass.rejected,
      );
    });

    test('a 422 with any other code stays hard', () {
      expect(
        classifySyncError(_dio(422, _detail('NOT_A_LOCATION_STOP'))),
        SyncErrorClass.hard,
      );
    });

    test('a 409 saying "already" is already applied', () {
      expect(
        classifySyncError(_dio(409, {'detail': 'Completion already applied'})),
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

      expect(classifySyncError(error), SyncErrorClass.hard);
    });
  });
}
