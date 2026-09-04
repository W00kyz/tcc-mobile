import 'dart:async';
import 'dart:convert';

import 'package:route_monitor/execution/evidence_capture.dart';
import 'package:route_monitor/forms/form_draft_store.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
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
  ExecutionRepository(
    this._store,
    this._stopProgress,
    this._syncMeta,
    this._syncWorker,
    this._formDraftStore,
  );

  final LocalWriteStore _store;
  final StopProgressStore _stopProgress;
  final SyncMetaStore _syncMeta;
  final SyncWorker _syncWorker;
  final FormDraftStore _formDraftStore;
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

  /// Starts [routeId] through the outbox — same drift-first shape as
  /// [checkIn]: a `pending` [PendingOpKind.startRoute] row plus a local
  /// optimistic marker, then a non-blocking [SyncWorker] kick. Never touches
  /// the network. `started_at` is captured here, at tap time, so a late sync
  /// still records when the field worker actually started (spec Ruling 8).
  /// `start` gets no idempotency key — there is no picker retry — and the
  /// worker treats the backend's 409 "already started" as success.
  Future<void> startRoute({
    required String routeId,
    required double latitude,
    required double longitude,
  }) async {
    final startedAt = DateTime.now().toUtc();
    final key = _uuid.v4();
    await _store.enqueue(
      id: key,
      kind: PendingOpKind.startRoute,
      routeId: routeId,
      payload: {
        'route_id': routeId,
        'latitude': latitude,
        'longitude': longitude,
        // A String, never a DateTime — LocalWriteStore.enqueue jsonEncodes
        // this map, which throws on a raw DateTime value.
        'started_at': startedAt.toIso8601String(),
      },
    );
    // Ruling 5: the route reads as "iniciada" on device now, not after the
    // 200 — RouteScreen watches this marker alongside the server value.
    await _syncMeta.setRouteStartedAt(routeId, startedAt);
    unawaited(_syncWorker.syncRoute(routeId));
  }

  /// Check-out is always per-stop (Ruling 16 — the UI already knows which
  /// `IN_PROGRESS` stop it is concluding), so [routeStopId] is required and
  /// travels in the payload as the `route_stop_id` of `POST /check-outs`.
  ///
  /// [checkoutIdempotencyKey] follows the same reuse-on-retry rule as
  /// `checkIn`'s `idempotencyKey`: omitted generates a fresh one, supplied
  /// reuses the first attempt's key. `execution_id` is a generated UUID the
  /// worker forwards in the dispatch call (the backend accepts and ignores
  /// it for a check-out) — it is NOT the executionId the stop's form draft
  /// was snapshotted under (that one lives in `StopProgress`, looked up
  /// below), so it is never used to read or clear the draft.
  ///
  /// Task 14: when the stop has an open, non-empty form draft, its answers
  /// (and the form version they were answered against) ride along in the
  /// check-out payload — this is the only place the server ever sees them,
  /// the draft itself never syncs mid-fill (spec §6.1/§6.3).
  Future<void> checkOut({
    required String routeId,
    required String routeStopId,
    required String qrPayload,
    double? latitude,
    double? longitude,
    String? checkoutIdempotencyKey,
  }) async {
    final key = checkoutIdempotencyKey ?? _uuid.v4();
    final executionId = _uuid.v4();
    final scannedAt = DateTime.now().toUtc();

    // The real draft executionId — StopProgress, not the throwaway one just
    // generated above — is what the draft was snapshotted under at check-in.
    final progress = await _stopProgress.progressFor(routeStopId);
    final draftItems = progress == null
        ? const <FormDraftItem>[]
        : await _formDraftStore.itemsFor(progress.executionId);
    // `FormDraftStore.isComplete` deliberately lets an unanswered
    // non-required question through the completeness gate, so `draftItems`
    // can contain items with a null `value` here. The backend's
    // `build_answers` rejects a null value for every question type with a
    // 422 (which `SyncWorker` treats as a hard, permanently-blocking
    // failure), so only answered items may reach the wire — an unanswered
    // optional question is simply omitted, not sent as `null`.
    final answered = draftItems.where((i) => i.value != null).toList();

    await _store.enqueue(
      id: key,
      kind: PendingOpKind.checkOut,
      routeId: routeId,
      payload: {
        'execution_id': executionId,
        'qr_payload': qrPayload,
        'latitude': latitude,
        'longitude': longitude,
        'scanned_at': scannedAt.toIso8601String(),
        'checkout_idempotency_key': key,
        'route_stop_id': routeStopId,
        // Guarded on `draftItems`, not `answered`: a draft that exists but
        // is entirely unanswered-optional still has a `form_version_id` and
        // must still send `answers: []` — the backend's pair-completeness
        // check (Ruling 7) accepts an empty `answers` list as long as
        // `form_version_id` is present.
        if (draftItems.isNotEmpty)
          'form_version_id': draftItems.first.formVersionId,
        if (draftItems.isNotEmpty)
          'answers': answered
              .map((i) => {'stable_key': i.stableKey, 'value': i.value})
              .toList(),
      },
    );
    // Ruling 5 counterpart to checkIn's upsert above; Ruling 3: the row is
    // marked DONE, not deleted.
    await _stopProgress.markDone(routeStopId);
    // The draft's job ends here — the server now has (or will have, once
    // this row syncs) the final answers, so nothing is left on-device to
    // reconcile or resume.
    if (progress != null) await _formDraftStore.clear(progress.executionId);
    unawaited(_syncWorker.syncRoute(routeId));
  }

  /// Adds a photo to [executionId]'s evidence list — same drift-first
  /// discipline as `checkIn`/`checkOut`: enqueued as a `pending` row
  /// ([PendingOpKind.evidencePhoto]) that the [SyncWorker] uploads later.
  /// [photo]'s bytes are base64-encoded into the payload (never a raw
  /// `Uint8List` — `LocalWriteStore.enqueue` `jsonEncode`s the map) so a
  /// `pending`/`failed` row still has what it needs to render a local
  /// thumbnail before the backend has a copy.
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
        'idempotency_key': key,
      },
    );
    unawaited(_syncWorker.syncRoute(routeId));
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
        'idempotency_key': key,
      },
    );
    unawaited(_syncWorker.syncRoute(routeId));
  }
}
