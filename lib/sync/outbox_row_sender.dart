import 'dart:convert';

import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';

/// Sends one outbox row to its endpoint and returns the server's `Date`
/// (for the clock offset, spec Ruling 7), or null when the reply has none.
/// Split from `SyncWorker`, which decides when and whether to send; this
/// only knows how each [PendingOpKind] goes over the wire.
///
///     final serverDate = await sender.send(row);
class OutboxRowSender {
  OutboxRowSender({
    required this._executionApi,
    required this._evidenceApi,
    required this._stopProgress,
    required this._syncMeta,
  });

  final ExecutionApi _executionApi;
  final EvidenceApi _evidenceApi;
  final StopProgressStore _stopProgress;
  final SyncMetaStore _syncMeta;

  Future<DateTime?> send(PendingOperationRow row) {
    final payload = row.payload;
    return switch (row.kind) {
      PendingOpKind.checkIn => _performCheckIn(payload),
      PendingOpKind.checkOut => _performCheckOut(payload),
      PendingOpKind.impediment => _performImpediment(payload),
      PendingOpKind.evidencePhoto => _evidenceApi.uploadPhoto(
        executionId: payload['execution_id'] as String,
        bytes: base64Decode(payload['bytes_b64'] as String),
        sha256: payload['sha256'] as String,
        capturedAt: DateTime.parse(payload['captured_at'] as String),
        idempotencyKey: payload['idempotency_key'] as String,
      ),
      PendingOpKind.evidenceNote => _evidenceApi.uploadNote(
        executionId: payload['execution_id'] as String,
        textBody: payload['text_body'] as String,
        capturedAt: DateTime.parse(payload['captured_at'] as String),
        idempotencyKey: payload['idempotency_key'] as String,
      ),
    };
  }

  Future<DateTime?> _performCheckIn(Map<String, dynamic> payload) async {
    final response = await _executionApi.checkIn(
      executionId: payload['execution_id'] as String,
      qrPayload: payload['qr_payload'] as String,
      scannedAt: DateTime.parse(payload['scanned_at'] as String),
      idempotencyKey: payload['idempotency_key'] as String,
      latitude: (payload['latitude'] as num?)?.toDouble(),
      longitude: (payload['longitude'] as num?)?.toDouble(),
      routeStopId: payload['route_stop_id'] as String?,
      clientClockOffsetSeconds: await _syncMeta.getClockOffsetSeconds(),
    );
    await _stopProgress.upsertInProgress(
      response.result.routeStopId,
      response.result.executionId,
    );
    return response.serverDate;
  }

  Future<DateTime?> _performCheckOut(Map<String, dynamic> payload) async {
    final response = await _executionApi.checkOut(
      executionId: payload['execution_id'] as String,
      qrPayload: payload['qr_payload'] as String,
      scannedAt: DateTime.parse(payload['scanned_at'] as String),
      checkoutIdempotencyKey: payload['checkout_idempotency_key'] as String,
      latitude: (payload['latitude'] as num?)?.toDouble(),
      longitude: (payload['longitude'] as num?)?.toDouble(),
      routeStopId: payload['route_stop_id'] as String?,
      clientClockOffsetSeconds: await _syncMeta.getClockOffsetSeconds(),
      complaintsSuggestions: payload['complaints_suggestions'] as String?,
      // LEGACY: a row queued by an old build may still carry form fields in
      // its payload; they are deliberately not read, so the server never
      // receives them (forms were removed).
    );
    await _stopProgress.markDone(response.result.routeStopId);
    return response.serverDate;
  }

  Future<DateTime?> _performImpediment(Map<String, dynamic> payload) async {
    await _executionApi.reportImpediment(
      routeId: payload['route_id'] as String,
      routeStopId: payload['route_stop_id'] as String?,
      scope: payload['scope'] as String,
      reason: payload['reason'] as String,
      note: payload['note'] as String?,
      reportedAt: DateTime.parse(payload['reported_at'] as String),
    );
    // No serverDate to return: the impediment response is just the created
    // row, and check-in/out already measure the clock offset (Ruling 7). A
    // 409 (`RouteNotInProgress`/`StopNotReassignable`) falls through `classifySyncError`
    // to `SyncErrorClass.hard`, blocking this route's queue.
    return null;
  }
}
