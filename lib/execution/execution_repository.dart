import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:uuid/uuid.dart';

/// Enqueues every check-in in [LocalWriteStore] before touching the network
/// (Ruling 1, Etapa 5 design §4.1/§6.1 — RNF06: no pending write may exist
/// only in memory), then marks the row synced or failed from the outcome.
class ExecutionRepository {
  ExecutionRepository(this._api, this._store);

  final ExecutionApi _api;
  final LocalWriteStore _store;
  static const _uuid = Uuid();

  Future<CheckInResult> checkIn({
    required String routeId,
    required String qrPayload,
    double? latitude,
    double? longitude,
  }) async {
    final idempotencyKey = _uuid.v4();
    final scannedAt = DateTime.now().toUtc();
    await _store.enqueue(
      id: idempotencyKey,
      kind: PendingOpKind.checkIn,
      routeId: routeId,
      payload: {
        'qr_payload': qrPayload,
        'latitude': latitude,
        'longitude': longitude,
        // A String, never a DateTime — LocalWriteStore.enqueue jsonEncodes
        // this map, which throws on a raw DateTime value.
        'scanned_at': scannedAt.toIso8601String(),
        'idempotency_key': idempotencyKey,
      },
    );

    try {
      final result = await _api.checkIn(
        qrPayload: qrPayload,
        latitude: latitude,
        longitude: longitude,
        scannedAt: scannedAt,
        idempotencyKey: idempotencyKey,
      );
      await _store.markSynced(idempotencyKey);
      return result;
      // Deliberately broad: any failure here — DioException (network/HTTP)
      // or AmbiguousRoomException (the floor cross-reference found more than
      // one candidate room, Task 18's picker) — must mark the row failed so
      // a later retryFailed replays it; AmbiguousRoomException itself must
      // still propagate unchanged so the caller can pattern-match on it.
    } catch (e) {
      await _store.markFailed(idempotencyKey, e.toString());
      rethrow;
    }
  }

  /// Replays every `pending`/`failed` check-in row for [routeId], oldest
  /// first (per [LocalWriteStore.unsyncedForRoute]'s contract), marking each
  /// synced on success. One row failing again must not abort the batch.
  Future<void> retryFailed(String routeId) async {
    final rows = await _store.unsyncedForRoute(routeId);
    for (final row in rows) {
      // Task 18/19 add checkOut/evidence retry; this drain only knows
      // check-in rows for now.
      if (row.kind != PendingOpKind.checkIn) continue;
      try {
        await _api.checkIn(
          qrPayload: row.payload['qr_payload'] as String,
          latitude: (row.payload['latitude'] as num?)?.toDouble(),
          longitude: (row.payload['longitude'] as num?)?.toDouble(),
          scannedAt: DateTime.parse(row.payload['scanned_at'] as String),
          idempotencyKey: row.payload['idempotency_key'] as String,
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
