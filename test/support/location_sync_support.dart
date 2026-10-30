import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/execution/location_execution_id.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/day_log_store.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/released_stop_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
import 'package:route_monitor/sync/location_refusal.dart';
import 'package:route_monitor/sync/sync_worker.dart';

import 'fake_connectivity.dart';

/// Answers each location completion from [refusals] (by stop id) or accepts
/// it; every call lands in [log].
class LocationApi implements ExecutionApi {
  LocationApi(this.log);

  final List<String> log;
  final Map<String, Exception> refusals = {};

  @override
  Future<DateTime?> completeByLocation({
    required String executionId,
    required String routeStopId,
    required String idempotencyKey,
    required double latitude,
    required double longitude,
    required DateTime completedAt,
    double? accuracyM,
    double? clientClockOffsetSeconds,
    String? complaintsSuggestions,
  }) async {
    log.add('completion:$routeStopId');
    final refusal = refusals[routeStopId];
    if (refusal != null) throw refusal;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PhotoApi implements EvidenceApi {
  PhotoApi(this.log);

  final List<String> log;

  @override
  Future<DateTime?> uploadPhoto({
    required String executionId,
    required Uint8List bytes,
    required String sha256,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async {
    log.add('photo:$idempotencyKey');
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class NoReleasedStops implements ReleasedStopStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A drain over [db] with the stores of the real app and fake APIs: the
/// foreground worker (callback wired) or the background isolate's (none).
SyncWorker locationWorker(
  AppDatabase db,
  LocationApi api,
  List<String> log, {
  LocalWriteStore? store,
  EvidenceApi? photos,
  void Function(LocationRefusal refusal)? onLocationRefused,
  DayLogStore? dayLog,
}) => SyncWorker(
  store ?? DriftLocalWriteStore(db),
  DriftStopProgressStore(db),
  DriftSyncMetaStore(db),
  FakeConnectivity(isOnline: true),
  api,
  photos ?? PhotoApi(log),
  NoReleasedStops(),
  onLocationRefused: onLocationRefused,
  dayLog: dayLog,
  atomically: (writes) => db.transaction(writes),
);

/// Seeds outbox rows of route `r1` at increasing `createdAt`, so the FIFO
/// order is the test's, together with the stop's optimistic `done` mark.
class LocationOutbox {
  LocationOutbox(this.db);

  final AppDatabase db;
  int _clock = 0;

  Future<void> seed(
    String id,
    PendingOpKind kind,
    Map<String, dynamic> payload, {
    PendingOpState state = PendingOpState.pending,
  }) => db
      .into(db.pendingOperations)
      .insert(
        PendingOperationsCompanion.insert(
          id: id,
          kind: kind.name,
          routeId: 'r1',
          payloadJson: jsonEncode(payload),
          createdAt: _clock++,
          state: Value(state.name),
        ),
      );

  /// The completion row `done-<stopId>` and the stop written `done`, as
  /// `concludeByLocation` leaves them.
  Future<void> completion(String stopId, String place) async {
    await seed('done-$stopId', PendingOpKind.locationCompletion, {
      'execution_id': locationExecutionId(stopId),
      'route_stop_id': stopId,
      'idempotency_key': 'done-$stopId',
      'latitude': -7.2,
      'longitude': -35.9,
      'accuracy_m': null,
      'completed_at': '2026-10-31T12:00:00.000Z',
      'complaints_suggestions': null,
      'place_name': place,
    });
    await DriftStopProgressStore(
      db,
    ).upsertDone(stopId, locationExecutionId(stopId));
  }

  Future<void> photo(String id, String executionId) =>
      seed(id, PendingOpKind.evidencePhoto, {
        'execution_id': executionId,
        'bytes_b64': 'AAAA',
        'sha256': 'h',
        'captured_at': '2026-10-31T11:59:00.000Z',
        'idempotency_key': id,
      });
}
