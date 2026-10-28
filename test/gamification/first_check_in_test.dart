import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/gamification/gamification_providers.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';

import '../support/in_memory_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = inMemoryDatabase();
    addTearDown(db.close);
  });

  Future<void> row(String id, PendingOpKind kind, String stop, int at) => db
      .into(db.pendingOperations)
      .insert(
        PendingOperationsCompanion.insert(
          id: id,
          kind: kind.name,
          routeId: 'r1',
          payloadJson: '{"route_stop_id":"$stop"}',
          createdAt: at,
        ),
      );

  test('the earliest check-in among the batch stops', () async {
    await row('a', PendingOpKind.checkIn, 's1', 5000);
    await row('b', PendingOpKind.checkIn, 's2', 3000);
    // Not in the batch, and not a check-in: both ignored.
    await row('c', PendingOpKind.checkIn, 'other', 1000);
    await row('d', PendingOpKind.checkOut, 's1', 2000);

    expect(
      await firstCheckInAt(db, ['s1', 's2']),
      DateTime.fromMillisecondsSinceEpoch(3000),
    );
  });

  test('null with no check-in on this device', () async {
    expect(await firstCheckInAt(db, ['s1']), isNull);
    expect(await firstCheckInAt(db, const []), isNull);
  });
}
