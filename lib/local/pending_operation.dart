// The value types of the write-ahead log: what a buffered write is and
// how far its drain got. Re-exported by local_write_store.dart, which owns
// the store itself.

/// The kind of execution write buffered in `PendingOperations`.
///
/// The `.name` of each value is what lands in the `kind` column, so renaming a
/// value is a schema-visible change.
enum PendingOpKind {
  checkIn,
  checkOut,
  evidencePhoto,
  evidenceNote,
  impediment,
}

/// Drain state of a buffered write. `.name` is persisted in the `state` column.
///
/// `blocked` is a terminal-until-manual state (spec Ruling 6): the sync worker
/// gave up on this row after exhausting its retry budget, and it stays put
/// until the field worker acts on it.
///
/// `sending` is a claim: one sync worker took the row for one send, until
/// the lease in `nextAttemptAt`. The app and the background drain open the
/// file on two connections, and only the claim keeps them from both sending
/// it (redesign §6.9). A lease that expired (a worker killed mid-send) makes
/// the row due again; nothing resets `sending` on startup, since the other
/// isolate may still be mid-send.
///
/// `held` is an evidence photo taken but not yet cleared to leave the device:
/// it waits for its task to be stamped (`LocalWriteStore.releaseHeldPhotos`)
/// or abandoned (`LocalWriteStore.discardHeldPhotos`). It is owed to the
/// network eventually, so it counts as unsent, but it is never due.
enum PendingOpState { pending, synced, failed, blocked, sending, held }

/// A decoded `PendingOperations` row, free of any Drift type so callers
/// (Task 17's `ExecutionRepository` and up) never import drift.
class PendingOperationRow {
  const PendingOperationRow({
    required this.id,
    required this.kind,
    required this.routeId,
    required this.payload,
    required this.createdAt,
    required this.state,
    required this.lastError,
    required this.attempts,
    required this.nextAttemptAt,
    this.releasedStopId,
  });

  final String id;
  final PendingOpKind kind;
  final String routeId;
  final Map<String, dynamic> payload;
  final int createdAt;
  final PendingOpState state;
  final String? lastError;

  /// How many sync attempts this row has already burned (spec Ruling 6).
  final int attempts;

  /// Epoch milliseconds before which the worker must not retry this row, or
  /// null when it is due immediately.
  final int? nextAttemptAt;

  /// The released stop a `409 STOP_RELEASED` parked this row on, or null.
  /// A parked row is never retried: the appeal flow (or discarding the
  /// stop's local data) is what clears it.
  final String? releasedStopId;
}
