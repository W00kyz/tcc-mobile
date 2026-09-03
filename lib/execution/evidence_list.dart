import 'dart:convert';
import 'dart:typed_data';

import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/local/local_write_store.dart';

/// One row in a stop's evidence list — a merge of the backend's
/// already-synced items (`EvidenceApi.listEvidence`) and this device's own
/// `pending`/`failed` [LocalWriteStore] rows for the same execution. A
/// [LocalWriteStore] row that reaches `synced` is never surfaced twice: once
/// synced it drops out of `unsyncedForRoute`, and from then on the backend's
/// copy (fetched via `listEvidence`) is what's shown.
class EvidenceListEntry {
  const EvidenceListEntry({
    required this.kind,
    required this.syncState,
    required this.capturedAt,
    this.photoBytes,
    this.textBody,
    this.contentUrl,
  });

  /// 'PHOTO' | 'NOTE' — `EvidenceKind`
  /// (backend/app/domain/execution/models.py).
  final String kind;
  final PendingOpState syncState;
  final DateTime capturedAt;

  /// The compressed photo bytes, held locally only while [syncState] is
  /// `pending`/`failed` — a synced item's bytes live on the backend, fetched
  /// through [contentUrl] instead.
  final Uint8List? photoBytes;
  final String? textBody;

  /// Set only for a synced item — the relative path the UI resolves against
  /// `apiBaseUrlFromEnvironment()` to render `Image.network`.
  final String? contentUrl;
}

EvidenceListEntry _fromPendingRow(PendingOperationRow row) {
  final encodedBytes = row.payload['bytes_b64'] as String?;
  return EvidenceListEntry(
    kind: row.kind == PendingOpKind.evidencePhoto ? 'PHOTO' : 'NOTE',
    syncState: row.state,
    capturedAt: DateTime.parse(row.payload['captured_at'] as String),
    photoBytes: encodedBytes == null ? null : base64Decode(encodedBytes),
    textBody: row.payload['text_body'] as String?,
  );
}

EvidenceListEntry _fromApiItem(EvidenceItem item) => EvidenceListEntry(
  kind: item.kind,
  syncState: PendingOpState.synced,
  capturedAt: item.capturedAt,
  textBody: item.textBody,
  contentUrl: item.contentUrl,
);

/// Loads one stop's evidence list for its [executionId]: the backend's
/// synced items plus [store]'s still-unsynced rows for the same execution,
/// oldest first.
Future<List<EvidenceListEntry>> loadStopEvidence({
  required LocalWriteStore store,
  required EvidenceApi api,
  required String routeId,
  required String executionId,
}) async {
  final synced = await api.listEvidence(executionId);
  final unsynced = await store.unsyncedForRoute(routeId);
  final localEntries = unsynced.where(
    (row) =>
        (row.kind == PendingOpKind.evidencePhoto ||
            row.kind == PendingOpKind.evidenceNote) &&
        row.payload['execution_id'] == executionId,
  );

  return [...synced.map(_fromApiItem), ...localEntries.map(_fromPendingRow)]
    ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
}
