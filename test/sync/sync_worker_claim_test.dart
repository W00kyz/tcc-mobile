import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/released_stop_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
import 'package:route_monitor/sync/sync_worker.dart';

import '../support/fake_connectivity.dart';

/// Counts impediment sends; the first one waits on [gate], so a second
/// worker can run its whole pass while the first is mid-send.
class _GatedImpedimentApi implements ExecutionApi {
  int impedimentCalls = 0;
  final Completer<void> gate = Completer<void>();
  final Completer<void> firstSendStarted = Completer<void>();

  @override
  Future<void> reportImpediment({
    required String routeId,
    required String? routeStopId,
    required String scope,
    required String reason,
    required DateTime reportedAt,
    String? note,
  }) async {
    impedimentCalls++;
    if (!firstSendStarted.isCompleted) {
      firstSendStarted.complete();
      await gate.future;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not exercised');
}

class _UnusedEvidenceApi implements EvidenceApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not exercised');
}

/// One side of the race: its own connection to the shared file, as the app
/// and the background task each open their own.
SyncWorker _workerOn(AppDatabase db, ExecutionApi api) => SyncWorker(
  DriftLocalWriteStore(db),
  DriftStopProgressStore(db),
  DriftSyncMetaStore(db),
  FakeConnectivity(isOnline: true),
  api,
  _UnusedEvidenceApi(),
  DriftReleasedStopStore(db),
);

AppDatabase _connectionTo(File file) => AppDatabase(
  NativeDatabase(
    file,
    setup: (raw) => appDatabaseConnectionPragmas.forEach(raw.execute),
  ),
);

void main() {
  test(
    'two workers on two connections send a queued impediment once '
    '(Review Focus 4: the app resumes while the background task drains)',
    () async {
      final dir = await Directory.systemTemp.createTemp('claim_test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/route_monitor.sqlite');
      final appDb = _connectionTo(file);
      final taskDb = _connectionTo(file);
      addTearDown(appDb.close);
      addTearDown(taskDb.close);
      await DriftLocalWriteStore(appDb).enqueue(
        id: 'imp-1',
        kind: PendingOpKind.impediment,
        payload: {
          'route_id': 'route-R',
          'route_stop_id': 'stop-1',
          'scope': 'STOP',
          'reason': 'LOCKED',
          'reported_at': DateTime.utc(2026).toIso8601String(),
        },
        routeId: 'route-R',
      );
      final api = _GatedImpedimentApi();

      final background = _workerOn(taskDb, api).syncAll();
      await api.firstSendStarted.future;
      await _workerOn(appDb, api).syncAll();
      api.gate.complete();
      await background;

      expect(api.impedimentCalls, 1);
      final rows = await DriftLocalWriteStore(
        appDb,
      ).unsyncedForRoute('route-R');
      expect(rows, isEmpty);
    },
  );
}
