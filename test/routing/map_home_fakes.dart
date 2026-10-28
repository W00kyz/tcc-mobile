import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/released_stop_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
import 'package:route_monitor/monitoring/location_mode.dart';
import 'package:route_monitor/monitoring/monitoring_api.dart';
import 'package:route_monitor/monitoring/silence_watchdog.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/sync_progress.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/sync/sync_worker.dart';

import '../support/fake_route_repository.dart';

// The outer seams of the map-home widget tests, faked (moved from the
// deleted route_screen_test.dart, which held them inline).

/// A [SyncWorker] that records every `syncRoute` kick and never drains — the
/// repository fires this fire-and-forget after each enqueue (spec Ruling 2);
/// the home tests only care that the enqueue happened, not the network.
class RecordingSyncWorker implements SyncWorker {
  RecordingSyncWorker({this.statusStream, this.drains});

  final Stream<RouteSyncStatus>? statusStream;

  /// When set, each `syncRoute` (and `syncAll`, for route `r1`) also
  /// delivers every unsynced row of that store — the server accepted them
  /// all. Null = the server never gets them.
  LocalWriteStore? drains;
  final List<String> syncedRoutes = [];
  int syncAllCount = 0;

  @override
  Future<void> syncRoute(String routeId) async {
    syncedRoutes.add(routeId);
    await _deliver(routeId);
  }

  @override
  Future<void> syncAll() async {
    syncAllCount++;
    await _deliver('r1');
  }

  Future<void> _deliver(String routeId) async {
    final store = drains;
    if (store == null) return;
    for (final row in await store.unsyncedForRoute(routeId)) {
      await store.markSynced(row.id);
    }
  }

  @override
  Stream<RouteSyncStatus> statusFor(String routeId) =>
      statusStream ?? const Stream.empty();

  @override
  Future<void> unblock(String operationId) async {}

  @override
  Stream<SyncProgress> get progress => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

/// A real, decodable 1x1 transparent PNG — used wherever a test needs
/// `Image.memory` to actually succeed instead of throwing mid-decode.
final Uint8List onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
  '42YAAAAASUVORK5CYII=',
);

/// A [FakeRouteRepository] whose `GET /routes/me` holds [route] (none yet
/// when null).
FakeRouteRepository repositoryWith(RouteSummary? route) =>
    FakeRouteRepository(myDayWith(route));

/// In-memory [SyncMetaStore], so no test reaches the real Drift-backed
/// store.
class InMemorySyncMetaStore implements SyncMetaStore {
  double? offset;

  @override
  Future<double?> getClockOffsetSeconds() async => offset;

  @override
  Future<void> setClockOffsetSeconds(double seconds) async => offset = seconds;

  bool appInForeground = false;

  @override
  Future<bool> getAppInForeground() async => appInForeground;

  @override
  Future<void> setAppInForeground({required bool inForeground}) async =>
      appInForeground = inForeground;
}

class FakeLocationService implements LocationService {
  @override
  Future<Coordinates> getCurrentPosition({
    required LocationPurpose purpose,
  }) async => const Coordinates(latitude: -7.23, longitude: -35.88);
}

/// GPS is unavailable (e.g. a basement, RF29/RNF13) — every failure shape
/// GeolocatorLocationService can produce maps to the same "proceed without
/// GPS" behavior, so a single StateError stands in for all.
class FailingLocationService implements LocationService {
  @override
  Future<Coordinates> getCurrentPosition({
    required LocationPurpose purpose,
  }) async {
    throw StateError('no GPS signal');
  }
}

/// A stub [MonitoringApi] — the bell watches `unreadCountProvider`, and
/// navigating to `NotificationsScreen` watches `notificationsProvider`; both
/// must stay off the real Dio client under flutter_test.
class FakeMonitoringApi implements MonitoringApi {
  FakeMonitoringApi({this.unread = 0});

  final int unread;

  @override
  Future<List<AppNotification>> fetchNotifications({int limit = 30}) async =>
      const [];

  @override
  Future<int> unreadCount() async => unread;

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> reportPosition({
    required String routeId,
    required double latitude,
    required double longitude,
    required DateTime reportedAt,
    double? accuracyM,
  }) async => throw UnimplementedError();
}

/// An in-memory stand-in for the local write-ahead log — the evidence list
/// reads `localWriteStoreProvider` directly, so a photo added through
/// `ExecutionRepository` in one test must be visible to it through the same
/// store instance.
class InMemoryLocalWriteStore implements LocalWriteStore {
  /// Takes the row for a send, as a sync worker would (no lease kept).
  @override
  Future<bool> claim(
    String id, {
    required int now,
    required int leaseUntil,
  }) async {
    _setState(id, PendingOpState.sending);
    return true;
  }

  @override
  Future<void> releaseClaim(PendingOperationRow row) async =>
      _setState(row.id, PendingOpState.pending);

  final Map<String, PendingOperationRow> _rows = {};

  @override
  Future<bool> deletePendingPhoto(String operationId) async {
    final row = _rows[operationId];
    final deletable =
        row != null &&
        row.kind == PendingOpKind.evidencePhoto &&
        (row.state == PendingOpState.pending ||
            row.state == PendingOpState.failed ||
            row.state == PendingOpState.blocked);
    if (deletable) _rows.remove(operationId);
    return deletable;
  }

  @override
  Future<bool> enqueue({
    required String id,
    required PendingOpKind kind,
    required Map<String, dynamic> payload,
    required String routeId,
    PendingOpState initialState = PendingOpState.pending,
  }) async {
    // insertOrIgnore, like the real store.
    if (_rows.containsKey(id)) return false;
    _rows[id] = PendingOperationRow(
      id: id,
      kind: kind,
      routeId: routeId,
      payload: payload,
      createdAt: _rows.length,
      state: initialState,
      lastError: null,
      attempts: 0,
      nextAttemptAt: null,
    );
    return true;
  }

  @override
  Future<void> markSynced(String id) async =>
      _setState(id, PendingOpState.synced);

  @override
  Future<void> markFailed(String id, String error) async =>
      _setState(id, PendingOpState.failed, error: error);

  void _setState(String id, PendingOpState state, {String? error}) {
    final row = _rows[id]!;
    _rows[id] = PendingOperationRow(
      id: row.id,
      kind: row.kind,
      routeId: row.routeId,
      payload: row.payload,
      createdAt: row.createdAt,
      state: state,
      lastError: error,
      attempts: row.attempts,
      nextAttemptAt: row.nextAttemptAt,
    );
  }

  @override
  Future<List<PendingOperationRow>> unsyncedForRoute(String routeId) async =>
      _rows.values
          // Like the real store's `_unsentStates`: a blocked row is not
          // "owed to the network", it waits for the worker.
          .where(
            (r) =>
                r.routeId == routeId &&
                r.state != PendingOpState.synced &&
                r.state != PendingOpState.blocked,
          )
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<int> releaseHeldPhotos(String executionId) async =>
      _moveHeldPhotos(executionId, release: true);

  @override
  Future<int> discardHeldPhotos(String executionId) async =>
      _moveHeldPhotos(executionId, release: false);

  int _moveHeldPhotos(String executionId, {required bool release}) {
    final held = _rows.values
        .where(
          (row) =>
              row.kind == PendingOpKind.evidencePhoto &&
              row.state == PendingOpState.held &&
              row.payload['execution_id'] == executionId,
        )
        .toList();
    for (final row in held) {
      if (release) {
        _setState(row.id, PendingOpState.pending);
      } else {
        _rows.remove(row.id);
      }
    }
    return held.length;
  }

  @override
  Future<int> localPhotoCountFor(String executionId) async => _rows.values
      .where(
        (r) =>
            r.kind == PendingOpKind.evidencePhoto &&
            r.payload['execution_id'] == executionId,
      )
      .length;

  @override
  Future<void> markStopReleased(
    String id, {
    required String routeStopId,
    required String error,
  }) => throw UnimplementedError();

  @override
  Future<void> markBlocked(String id, String error) async =>
      _setState(id, PendingOpState.blocked, error: error);

  @override
  Future<void> markRetryScheduled(
    String id, {
    required int attempts,
    required int nextAttemptAt,
  }) => throw UnimplementedError();

  @override
  Future<List<PendingOperationRow>> blockedForRoute(String routeId) async =>
      _rows.values
          .where(
            (r) => r.routeId == routeId && r.state == PendingOpState.blocked,
          )
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<List<PendingOperationRow>> dueForRoute(
    String routeId, {
    required int now,
  }) => throw UnimplementedError();

  @override
  Future<List<String>> routeIdsWithWork() => throw UnimplementedError();

  @override
  Future<void> resetToPending(String id) async =>
      _setState(id, PendingOpState.pending);
}

/// An in-memory StopProgressStore — pre-seed with `seed` (routeStopId ->
/// executionId); every seeded stop starts `inProgress`. Empty, it reports no
/// progress, so a plain check-in test never opens the evidence section.
class FakeStopProgressStore implements StopProgressStore {
  /// [checkedInAt] is the check-in time every seeded stop reports.
  FakeStopProgressStore([
    Map<String, String> seed = const {},
    DateTime? checkedInAt,
  ]) : _checkedInAt = checkedInAt ?? DateTime(2026) {
    seed.forEach(upsertInProgressNow);
  }

  final Map<String, StopProgressEntry> _rows = {};
  final DateTime _checkedInAt;

  void upsertInProgressNow(String routeStopId, String executionId) {
    _rows[routeStopId] = StopProgressEntry(
      updatedAt: _checkedInAt,
      routeStopId: routeStopId,
      executionId: executionId,
      status: StopLocalStatus.inProgress,
    );
  }

  @override
  Future<void> upsertInProgress(String routeStopId, String executionId) async =>
      upsertInProgressNow(routeStopId, executionId);

  @override
  Future<void> markDone(String routeStopId) async {
    final existing = _rows[routeStopId];
    if (existing == null) return;
    _rows[routeStopId] = StopProgressEntry(
      updatedAt: DateTime(2026),
      routeStopId: existing.routeStopId,
      executionId: existing.executionId,
      status: StopLocalStatus.done,
    );
  }

  @override
  Future<void> markStamped(String routeStopId, {String? observation}) =>
      throw UnimplementedError();

  @override
  Future<StopProgressEntry?> progressFor(String routeStopId) async =>
      _rows[routeStopId];

  @override
  Future<List<StopProgressEntry>> allForRoute(
    Iterable<String> routeStopIds,
  ) async => [for (final id in routeStopIds) ?_rows[id]];
}

/// Returns [syncedItems] from `listEvidence` and records upload calls.
class FakeEvidenceApi implements EvidenceApi {
  FakeEvidenceApi({this.syncedItems = const []});

  final List<EvidenceItem> syncedItems;
  final List<String> uploadedPhotoExecutionIds = [];
  final List<String> uploadedNoteTexts = [];

  @override
  Future<DateTime?> uploadPhoto({
    required String executionId,
    required Uint8List bytes,
    required String sha256,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async {
    uploadedPhotoExecutionIds.add(executionId);
    return null;
  }

  @override
  Future<DateTime?> uploadNote({
    required String executionId,
    required String textBody,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async {
    uploadedNoteTexts.add(textBody);
    return null;
  }

  @override
  Future<List<EvidenceItem>> listEvidence(String executionId) async =>
      syncedItems;
}

/// Location permissions as the device would answer them: "while in use"
/// granted, "always" as the test says.
class FakePermissions implements PermissionPort {
  FakePermissions({this.grantsAlways = false});

  @override
  bool get supportsBackground => true;

  final bool grantsAlways;
  bool _always = false;
  int alwaysRequests = 0;

  @override
  Future<bool> requestWhileInUse() async => true;

  @override
  Future<bool> isAlwaysGranted() async => _always;

  @override
  Future<bool> requestAlways() async {
    alwaysRequests++;
    return _always = grantsAlways;
  }

  @override
  Future<void> requestNotifications() async {}
}

/// permission_handler failing on the platform side (e.g. a request already
/// running).
class ThrowingPermissions implements PermissionPort {
  @override
  bool get supportsBackground => true;

  @override
  Future<bool> requestWhileInUse() =>
      throw PlatformException(code: 'ERROR_ALREADY_REQUESTING_PERMISSIONS');

  @override
  Future<bool> isAlwaysGranted() async => false;

  @override
  Future<bool> requestAlways() async => false;

  @override
  Future<void> requestNotifications() async {}
}

/// A device that never saw a stop released.
class NoReleasedStops implements ReleasedStopStore {
  @override
  Future<bool> record({
    required String routeStopId,
    required String releaseReason,
    required bool appealable,
  }) async => false;

  @override
  Future<ReleasedStopNotice?> noticeFor(String routeStopId) async => null;

  @override
  Future<List<ReleasedStopNotice>> allNotices() async => const [];

  @override
  Future<void> discardStop(String routeStopId) async {}
}

class InMemoryAskStore implements BackgroundAskStore {
  InMemoryAskStore({this.asked = false});

  bool asked;

  @override
  Future<bool> wasAsked() async => asked;

  @override
  Future<void> markAsked() async => asked = true;
}

class NoopScheduler implements LocalScheduler {
  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancel(int id) async {}
}

/// Overrides `sessionProvider` with a fixed, non-null `Session`.
class FixedSession extends SessionNotifier {
  FixedSession(this._session);
  final Session _session;

  @override
  Session? build() => _session;
}
