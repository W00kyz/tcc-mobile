import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
import 'package:route_monitor/sync/refusal_notices.dart';

import '../support/in_memory_database.dart';
import '../support/location_sync_support.dart';

// A refusal applied by the background drain (another isolate, no listener) is
// only in SQLite: these are the notices the app finds there on resume.

void main() {
  late AppDatabase db;
  late LocationOutbox outbox;
  late LocationApi api;
  late List<String> log;

  setUp(() {
    db = inMemoryDatabase();
    addTearDown(db.close);
    outbox = LocationOutbox(db);
    log = [];
    api = LocationApi(log);
  });

  /// A fresh instance each time, as after an app restart.
  RefusalNotices notices() =>
      RefusalNotices(DriftLocalWriteStore(db), DriftSyncMetaStore(db));

  /// The background drain: the worker with no listener wired.
  Future<void> backgroundDrain() =>
      locationWorker(db, api, log).syncRoute('r1');

  const outOfRadius = LocationRefusedException(
    code: 'OUT_OF_RADIUS',
    distanceM: 137.4,
    radiusM: 50,
  );

  test('a refusal nobody was listening for is found with its place and '
      'distance', () async {
    await outbox.completion('sA', 'Praça central');
    api.refusals['sA'] = outOfRadius;
    await backgroundDrain();

    final found = await notices().unannounced();

    expect(found, hasLength(1));
    expect(found.single.routeStopId, 'sA');
    expect(found.single.operationId, 'done-sA');
    expect(
      found.single.message,
      'Conclusão recusada em Praça central: você estava a 137 m do local.',
    );
  });

  test(
    'a refusal without a position reads as the location being off',
    () async {
      await outbox.completion('sA', 'Praça central');
      api.refusals['sA'] = const LocationRefusedException(
        code: 'LOCATION_REQUIRED',
        distanceM: null,
        radiusM: null,
      );
      await backgroundDrain();

      final found = await notices().unannounced();

      expect(
        found.single.message,
        'Conclusão recusada em Praça central: sem localização ativa.',
      );
    },
  );

  test('a refusal read from a raw 422 keeps its distance', () async {
    await outbox.completion('sA', 'Praça central');
    final options = RequestOptions(path: '/location-completions');
    api.refusals['sA'] = DioException(
      requestOptions: options,
      response: Response<dynamic>(
        requestOptions: options,
        statusCode: 422,
        data: {
          'detail': {'code': 'OUT_OF_RADIUS', 'distance_m': 90.0},
        },
      ),
    );
    await backgroundDrain();

    final found = await notices().unannounced();

    expect(found.single.distanceM, 90.0);
  });

  test(
    'once acknowledged it is not found again, not even after a restart',
    () async {
      await outbox.completion('sA', 'Praça central');
      api.refusals['sA'] = outOfRadius;
      await backgroundDrain();
      await notices().acknowledge('done-sA');

      expect(await notices().unannounced(), isEmpty);
    },
  );

  test('a later refusal is found alone', () async {
    await outbox.completion('sA', 'Praça central');
    api.refusals['sA'] = outOfRadius;
    await backgroundDrain();
    await notices().acknowledge('done-sA');
    await outbox.completion('sB', 'Jardim');
    api.refusals['sB'] = outOfRadius;
    await backgroundDrain();

    final found = await notices().unannounced();

    expect(found.map((r) => r.routeStopId), ['sB']);
  });

  test('a delivered completion is no notice', () async {
    await outbox.completion('sA', 'Praça central');
    await backgroundDrain();

    expect(await notices().unannounced(), isEmpty);
  });

  test('acknowledgements of rows that are gone are forgotten', () async {
    await outbox.completion('sA', 'Praça central');
    await outbox.completion('sB', 'Jardim');
    api.refusals['sA'] = outOfRadius;
    api.refusals['sB'] = outOfRadius;
    await backgroundDrain();
    await notices().acknowledge('done-sA');
    await (db.delete(
      db.pendingOperations,
    )..where((t) => t.id.equals('done-sA'))).go();

    await notices().acknowledge('done-sB');

    expect(await DriftSyncMetaStore(db).getAcknowledgedRefusals(), {'done-sB'});
  });
}
