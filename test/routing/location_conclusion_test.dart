import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/evidence_capture.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/execution_repository.dart';
import 'package:route_monitor/execution/location_execution_id.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/routing/floor_actions.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/sync_providers.dart';

import '../support/fake_day_log_store.dart';
import '../support/in_memory_database.dart';
import 'map_home_fakes.dart';
import 'place_fixtures.dart';

// "Concluir tarefa" on a location stop writes a location completion, never
// a QR stamp.

/// Counts the QR stamps: a location stop must never get one.
class _StampCountingProgress extends DriftStopProgressStore {
  // The super parameter is private (`_db`): it cannot share its name.
  // ignore: matching_super_parameters
  _StampCountingProgress(super.db);

  int stamps = 0;

  @override
  Future<void> markStamped(String routeStopId, {String? observation}) {
    stamps++;
    return super.markStamped(routeStopId, observation: observation);
  }
}

void main() {
  late AppDatabase db;
  late _StampCountingProgress progress;
  late InMemoryLocalWriteStore store;
  late RecordingSyncWorker worker;
  late ExecutionRepository repository;

  setUp(() {
    db = inMemoryDatabase();
    addTearDown(db.close);
    progress = _StampCountingProgress(db);
    store = InMemoryLocalWriteStore();
    worker = RecordingSyncWorker();
    repository = ExecutionRepository(
      store,
      progress,
      worker,
      database: db,
      dayLog: RecordingDayLogStore(),
    );
  });

  final stop = placeStopIn(id: 'p1s1');
  final route = RouteSummary(
    id: 'r1',
    fieldWorkerName: 'João',
    routeDate: DateTime(2026, 10, 30),
    status: 'IN_PROGRESS',
    startedAt: null,
    currentBatch: 1,
    stops: [stop],
  );
  const fix = Coordinates(latitude: -7.2151, longitude: -35.9152);

  Future<({WidgetRef ref, ProviderContainer container})> pump(
    WidgetTester tester,
  ) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localWriteStoreProvider.overrideWithValue(store),
          stopProgressStoreProvider.overrideWithValue(progress),
          syncWorkerProvider.overrideWithValue(worker),
          executionRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return (
      ref: captured,
      container: ProviderScope.containerOf(
        tester.element(find.byType(Consumer)),
      ),
    );
  }

  testWidgets('concludeTask on a location stop queues the completion with the '
      'fix, then the photos, and never stamps', (tester) async {
    final executionId = locationExecutionId('p1s1');
    final photoKey = await repository.addPhoto(
      routeId: 'r1',
      executionId: executionId,
      photo: CapturedPhoto(bytes: Uint8List.fromList([1]), sha256: 'h'),
    );
    final host = await pump(tester);

    await concludeTask(host.ref, route, stop, observation: 'ok', fix: fix);

    final rows = await store.unsyncedForRoute('r1');
    expect(rows.map((r) => r.kind), [
      PendingOpKind.locationCompletion,
      PendingOpKind.evidencePhoto,
    ]);
    expect(rows.last.id, photoKey);
    expect(rows.last.state, PendingOpState.pending);
    final payload = rows.first.payload;
    expect(payload['latitude'], fix.latitude);
    expect(payload['longitude'], fix.longitude);
    expect(payload['complaints_suggestions'], 'ok');
    expect(payload['execution_id'], executionId);
    expect(payload['place_name'], 'Praça central');
    expect(progress.stamps, 0);
    expect((await progress.progressFor('p1s1'))!.status, StopLocalStatus.done);
    expect(host.container.read(lastStampedStopProvider), 'p1s1');
  });

  testWidgets('a location stop without a fix writes nothing and stamps '
      'nothing', (tester) async {
    final host = await pump(tester);

    await expectLater(
      concludeTask(host.ref, route, stop),
      throwsA(isA<Exception>()),
    );

    expect(await store.unsyncedForRoute('r1'), isEmpty);
    expect(await progress.progressFor('p1s1'), isNull);
    expect(host.container.read(lastStampedStopProvider), isNull);
    expect(progress.stamps, 0);
  });
}
