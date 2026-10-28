import 'dart:async';
import 'dart:convert';

import 'package:route_monitor/execution/evidence_capture.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/day_log_store.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/sync/sync_worker.dart';
import 'package:uuid/uuid.dart';

/// Records every field action in [LocalWriteStore] and updates local state
/// (RNF06 / spec Ruling 2 — no pending write may exist only in memory), then
/// fires a non-blocking [SyncWorker] kick so the UI reflects the action at
/// once (spec Ruling 5, optimistic UI). The write methods never touch the
/// network: the [SyncWorker] is the only owner of write network I/O — it
/// drains the outbox, dispatches, classifies failures (spec Ruling 6) and
/// marks each row's state. Nothing here throws `AmbiguousRoomException` or
/// `DioException` any more.
class ExecutionRepository {
  /// [database] must be the one [_store], [_stopProgress] and [dayLog] write
  /// to: `checkOut` opens its transaction on it, and drift routes every
  /// statement those stores issue inside that zone through the transaction.
  ExecutionRepository(
    this._store,
    this._stopProgress,
    this._syncWorker, {
    required AppDatabase database,
    required DayLogStore dayLog,
  }) // Public named params can't be initializing formals for private fields
    // (same idiom as DioRouteRepository).
    // ignore: prefer_initializing_formals
    : _database = database,
       // Same reason as `_database` above.
       // ignore: prefer_initializing_formals
       _dayLog = dayLog;

  final LocalWriteStore _store;
  final StopProgressStore _stopProgress;
  final SyncWorker _syncWorker;
  final AppDatabase _database;
  final DayLogStore _dayLog;
  static const _uuid = Uuid();

  /// [idempotencyKey], when supplied, is reused instead of generating a
  /// fresh one — Ruling 16: a single field-worker tap on "Fazer check-in" is
  /// one logical attempt even when the room picker makes the caller retry
  /// with a resolved [routeStopId], so that retry must reuse the first call's
  /// key rather than open a second `PendingOperations` row / `Execution` for
  /// what the worker experienced as one action. The store's `insertOrIgnore`
  /// then makes the retry's enqueue a no-op. Omitted (the normal,
  /// first-attempt call) generates a fresh one.
  ///
  /// Returns the generated `executionId` (spec Ruling 4 — the app owns this
  /// id now; offline there is no 201 response to learn it from). The evidence
  /// endpoints need it and a caller may want to keep it. [routeStopId] may be
  /// null: `null` means "let the server resolve the room on sync" (spec
  /// Ruling 4).
  Future<String> checkIn({
    required String routeId,
    required String qrPayload,
    double? latitude,
    double? longitude,
    String? idempotencyKey,
    String? routeStopId,
  }) async {
    final key = idempotencyKey ?? _uuid.v4();
    final executionId = _uuid.v4();
    final scannedAt = DateTime.now().toUtc();
    await _store.enqueue(
      id: key,
      kind: PendingOpKind.checkIn,
      routeId: routeId,
      payload: {
        'execution_id': executionId,
        'qr_payload': qrPayload,
        'latitude': latitude,
        'longitude': longitude,
        // A String, never a DateTime — LocalWriteStore.enqueue jsonEncodes
        // this map, which throws on a raw DateTime value.
        'scanned_at': scannedAt.toIso8601String(),
        'idempotency_key': key,
        'route_stop_id': routeStopId,
      },
    );
    // Ruling 5: the stop turns IN_PROGRESS on device now, not after the 201.
    // A null routeStopId can't key a StopProgress row — the server resolves
    // the room on sync and the worker records it then (Ruling 4).
    if (routeStopId != null) {
      await _stopProgress.upsertInProgress(routeStopId, executionId);
    }
    unawaited(_syncWorker.syncRoute(routeId));
    return executionId;
  }

  /// Check-out is always per-stop (Ruling 16 — the UI already knows which
  /// `IN_PROGRESS` stop it is concluding), so [routeStopId] is required and
  /// travels in the payload as the `route_stop_id` of `POST /check-outs`.
  ///
  /// [checkoutIdempotencyKey] follows the same reuse-on-retry rule as
  /// `checkIn`'s `idempotencyKey`: omitted generates a fresh one, supplied
  /// reuses the first attempt's key. `execution_id` is a generated UUID the
  /// worker forwards in the dispatch call (the backend accepts and ignores
  /// it for a check-out).
  Future<void> checkOut({
    required String routeId,
    required String routeStopId,
    required String qrPayload,
    double? latitude,
    double? longitude,
    String? checkoutIdempotencyKey,
    String? complaintsSuggestions,
  }) async {
    final key = checkoutIdempotencyKey ?? _uuid.v4();
    final scannedAt = DateTime.now();
    final payload = _checkOutPayload(
      key: key,
      routeStopId: routeStopId,
      qrPayload: qrPayload,
      scannedAt: scannedAt,
      latitude: latitude,
      longitude: longitude,
      complaintsSuggestions: complaintsSuggestions,
    );
    // IMPORTANT: one transaction (redesign §6.8): the outbox row, the DONE
    // mark and the day log's point land together or not at all — a point
    // counted for a check-out that was never queued would be a lie, and a
    // queued check-out with no DONE mark would re-open the stop. Kept short:
    // the payload is built above, and the sync kick waits for the commit.
    await _database.transaction(() async {
      final queued = await _store.enqueue(
        id: key,
        kind: PendingOpKind.checkOut,
        routeId: routeId,
        payload: payload,
      );
      // Ruling 5 counterpart to checkIn's upsert above; Ruling 3: the row is
      // marked DONE, not deleted.
      await _stopProgress.markDone(routeStopId);
      // A retry with the same key queued nothing new: no second point.
      if (queued) await _dayLog.recordStopDone(scannedAt);
    });
    unawaited(_syncWorker.syncRoute(routeId));
  }

  /// The `POST /check-outs` body as queued. `execution_id` is a fresh UUID
  /// the backend accepts and ignores for a check-out.
  Map<String, dynamic> _checkOutPayload({
    required String key,
    required String routeStopId,
    required String qrPayload,
    required DateTime scannedAt,
    required double? latitude,
    required double? longitude,
    required String? complaintsSuggestions,
  }) => {
    'execution_id': _uuid.v4(),
    'qr_payload': qrPayload,
    'latitude': latitude,
    'longitude': longitude,
    'scanned_at': scannedAt.toUtc().toIso8601String(),
    'checkout_idempotency_key': key,
    'route_stop_id': routeStopId,
    'complaints_suggestions': ?complaintsSuggestions,
  };

  /// Signals an impossibility to execute through the outbox — same drift-first
  /// shape as [checkIn]: a `pending` [PendingOpKind.impediment] row plus a
  /// non-blocking [SyncWorker] kick, never touching the network. `reported_at`
  /// is captured here, at tap time, so a late sync still records when the
  /// field worker actually raised it (spec RF16-RF17).
  ///
  /// Unlike [checkIn], this makes NO optimistic local state change: signalling
  /// does not change the stop's status on device. The server releases the
  /// stop back to the pool once the row reaches it (spec
  /// 2026-10-20-alocacao-automatica §7.1), and the app shows it released on
  /// the day reload that follows the sync.
  ///
  /// [routeStopId] is null when [scope] is `ROUTE_REMAINDER` (the whole
  /// remainder of the route), populated when [scope] is `STOP`.
  Future<void> reportImpediment({
    required String routeId,
    required String? routeStopId,
    required String scope,
    required String reason,
    String? note,
  }) async {
    final reportedAt = DateTime.now().toUtc();
    final key = _uuid.v4();
    await _store.enqueue(
      id: key,
      kind: PendingOpKind.impediment,
      routeId: routeId,
      payload: {
        'route_id': routeId,
        'route_stop_id': routeStopId,
        'scope': scope,
        'reason': reason,
        'note': note,
        // A String, never a DateTime — LocalWriteStore.enqueue jsonEncodes
        // this map, which throws on a raw DateTime value.
        'reported_at': reportedAt.toIso8601String(),
      },
    );
    unawaited(_syncWorker.syncRoute(routeId));
  }

  /// Adds a photo to [executionId]'s evidence list — same drift-first
  /// discipline as `checkIn`/`checkOut`: enqueued as a `pending` row
  /// ([PendingOpKind.evidencePhoto]) that the [SyncWorker] uploads later.
  /// [photo]'s bytes are base64-encoded into the payload (never a raw
  /// `Uint8List` — `LocalWriteStore.enqueue` `jsonEncode`s the map) so a
  /// `pending`/`failed` row still has what it needs to render a local
  /// thumbnail before the backend has a copy. Returns the photo's
  /// idempotency key, which identifies the upload on the server.
  Future<String> addPhoto({
    required String routeId,
    required String executionId,
    required CapturedPhoto photo,
  }) async {
    final key = _uuid.v4();
    final capturedAt = DateTime.now().toUtc();
    await _store.enqueue(
      id: key,
      kind: PendingOpKind.evidencePhoto,
      routeId: routeId,
      payload: {
        'execution_id': executionId,
        'bytes_b64': base64Encode(photo.bytes),
        'sha256': photo.sha256,
        'captured_at': capturedAt.toIso8601String(),
        'idempotency_key': key,
      },
    );
    unawaited(_syncWorker.syncRoute(routeId));
    return key;
  }
}
