import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/location_execution_id.dart';

void main() {
  test('the same route stop always gets the same execution id', () {
    expect(locationExecutionId('stop-1'), locationExecutionId('stop-1'));
  });

  test('different route stops get different execution ids', () {
    expect(
      locationExecutionId('stop-1'),
      isNot(locationExecutionId('stop-2')),
    );
  });

  test('the id is a valid version 5 UUID', () {
    final id = locationExecutionId('stop-1');
    expect(id, hasLength(36));
    expect(
      id,
      matches(
        RegExp(
          '^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
          '[0-9a-f]{12}',
        ),
      ),
    );
  });
}
