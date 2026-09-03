import 'dart:convert';

import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/evidence_capture.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/open_execution_store.dart';
import 'package:uuid/uuid.dart';

/// Enqueues every check-in in [LocalWriteStore] before touching the network
/// (Ruling 1, Etapa 5 design §4.1/§6.1 — RNF06: no pending write may exist
/// only in memory), then marks the row synced or failed from the outcome.
class ExecutionRepository {
  ExecutionRepository(
    this._api,
    this._store,
    this._evidenceApi,
    this._openExecutions,
  );

  final ExecutionApi _api;
  final LocalWriteStore _store;
  final EvidenceApi _evidenceApi;
  final OpenExecutionStore _openExecutions;
  static const _uuid = Uuid();

  /// [idempotencyKey], when supplied, is reused instead of generating a
  /// fresh one — Ruling 16: a single field-worker tap on "Fazer check-in" is
  /// one logical attempt even when it needs a second network call to
  /// resolve (the room-picker retry after a `409 AMBIGUOUS_ROOM`, with
  /// [routeStopId] now set to the chosen candidate), so that retry must
  /// reuse the first call's key rather than open a second
  /// `PendingOperations` row / `Execution` for what the worker experienced
  /// as one action. Omitted (the normal, first-attempt call) generates a
  /// fresh one.
  Future<CheckInResult> checkIn({
    required String routeId,
    required String qrPayload,
    double? latitude,
    double? longitude,
    String? idempotencyKey,
    String? routeStopId,
  }) async {
    final key = idempotencyKey ?? _uuid.v4();
    final scannedAt = DateTime.now().toUtc();
    await _store.enqueue(
      id: key,
      kind: PendingOpKind.checkIn,
      routeId: routeId,
      payload: {
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

    try {
      final result = await _api.checkIn(
        qrPayload: qrPayload,
        latitude: latitude,
        longitude: longitude,
        scannedAt: scannedAt,
        idempotencyKey: key,
        routeStopId: routeStopId,
      );
      await _store.markSynced(key);
      // Ruling 17: the evidence endpoints need this execution_id and have no
      // other way to learn it — record it now while the response is at hand.
      await _openExecutions.recordOpenExecution(
        result.routeStopId,
        result.executionId,
      );
      return result;
      // Deliberately broad: any failure here — DioException (network/HTTP)
      // or AmbiguousRoomException (the floor cross-reference found more than
      // one candidate room, Task 18's picker) — must mark the row failed so
      // a later retryFailed replays it; AmbiguousRoomException itself must
      // still propagate unchanged so the caller can pattern-match on it.
    } catch (e) {
      await _store.markFailed(key, e.toString());
      rethrow;
    }
  }

  /// Check-out is always per-stop (Ruling 16 — unlike check-in, the UI
  /// already knows which `IN_PROGRESS` stop it is concluding), so
  /// [routeStopId] is required and sent from the first attempt as the
  /// `route_stop_id` of `POST /check-outs`. This makes the `409
  /// AMBIGUOUS_ROOM` response rare in practice (only two open check-ins on
  /// the same floor could still trigger it) but not impossible, so the
  /// caller still handles [AmbiguousRoomException] the same way as
  /// `checkIn`'s.
  ///
  /// [checkoutIdempotencyKey] follows the same reuse-on-retry rule as
  /// `checkIn`'s `idempotencyKey`: omitted generates a fresh one, supplied
  /// reuses the first attempt's key for a same-tap resolution retry.
  Future<CheckOutResult> checkOut({
    required String routeId,
    required String routeStopId,
    required String qrPayload,
    double? latitude,
    double? longitude,
    String? checkoutIdempotencyKey,
  }) async {
    final key = checkoutIdempotencyKey ?? _uuid.v4();
    final scannedAt = DateTime.now().toUtc();
    await _store.enqueue(
      id: key,
      kind: PendingOpKind.checkOut,
      routeId: routeId,
      payload: {
        'qr_payload': qrPayload,
        'latitude': latitude,
        'longitude': longitude,
        'scanned_at': scannedAt.toIso8601String(),
        'checkout_idempotency_key': key,
        'route_stop_id': routeStopId,
      },
    );

    try {
      final result = await _api.checkOut(
        qrPayload: qrPayload,
        latitude: latitude,
        longitude: longitude,
        scannedAt: scannedAt,
        checkoutIdempotencyKey: key,
        routeStopId: routeStopId,
      );
      await _store.markSynced(key);
      // Ruling 17 counterpart to checkIn's record above: the stop's open
      // execution is closed, so the evidence buttons must stop being offered.
      await _openExecutions.clearOpenExecution(result.routeStopId);
      return result;
      // Deliberately broad: same rationale as checkIn above — any failure
      // marks the row failed, and AmbiguousRoomException must still
      // propagate unchanged.
    } catch (e) {
      await _store.markFailed(key, e.toString());
      rethrow;
    }
  }

  /// Adds a photo to [executionId]'s evidence list — same drift-first
  /// discipline as `checkIn`/`checkOut`: enqueued as a `pending` row
  /// ([PendingOpKind.evidencePhoto]) before the upload, marked
  /// synced/failed from the outcome. [photo]'s bytes are base64-encoded into
  /// the payload (never a raw `Uint8List` — `LocalWriteStore.enqueue`
  /// `jsonEncode`s the map) so a `pending`/`failed` row still has what it
  /// needs to render a local thumbnail before the backend has a copy.
  Future<void> addPhoto({
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
      },
    );

    try {
      await _evidenceApi.uploadPhoto(
        executionId: executionId,
        bytes: photo.bytes,
        sha256: photo.sha256,
        capturedAt: capturedAt,
      );
      await _store.markSynced(key);
      // Deliberately broad: any upload failure marks the row failed so a
      // later retry can replay it.
    } catch (e) {
      await _store.markFailed(key, e.toString());
      rethrow;
    }
  }

  /// Adds a text note to [executionId]'s evidence list — same lifecycle as
  /// [addPhoto].
  Future<void> addNote({
    required String routeId,
    required String executionId,
    required String text,
  }) async {
    final key = _uuid.v4();
    final capturedAt = DateTime.now().toUtc();
    await _store.enqueue(
      id: key,
      kind: PendingOpKind.evidenceNote,
      routeId: routeId,
      payload: {
        'execution_id': executionId,
        'text_body': text,
        'captured_at': capturedAt.toIso8601String(),
      },
    );

    try {
      await _evidenceApi.uploadNote(
        executionId: executionId,
        textBody: text,
        capturedAt: capturedAt,
      );
      await _store.markSynced(key);
      // Deliberately broad: same rationale as addPhoto above.
    } catch (e) {
      await _store.markFailed(key, e.toString());
      rethrow;
    }
  }

  /// Replays every `pending`/`failed` check-in row for [routeId], oldest
  /// first (per [LocalWriteStore.unsyncedForRoute]'s contract), marking each
  /// synced on success. One row failing again must not abort the batch.
  Future<void> retryFailed(String routeId) async {
    final rows = await _store.unsyncedForRoute(routeId);
    for (final row in rows) {
      // checkOut/evidence retry (PendingOpKind.checkOut/evidencePhoto/
      // evidenceNote) is still deferred to a future task; this drain only
      // knows check-in rows for now.
      if (row.kind != PendingOpKind.checkIn) continue;
      try {
        await _api.checkIn(
          qrPayload: row.payload['qr_payload'] as String,
          latitude: (row.payload['latitude'] as num?)?.toDouble(),
          longitude: (row.payload['longitude'] as num?)?.toDouble(),
          scannedAt: DateTime.parse(row.payload['scanned_at'] as String),
          idempotencyKey: row.payload['idempotency_key'] as String,
          routeStopId: row.payload['route_stop_id'] as String?,
        );
        await _store.markSynced(row.id);
        // Deliberately broad: keep retrying the rest of the batch no matter
        // why this one row failed again (still offline, still ambiguous...).
        // ignore: avoid_catches_without_on_clauses
      } catch (e) {
        await _store.markFailed(row.id, e.toString());
      }
    }
  }
}
