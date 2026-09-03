/// What the sync worker is doing for one route, as surfaced to the route
/// screen's header indicator (spec Etapa 6 §UI — "N ações aguardando
/// sincronização" / "Tudo sincronizado" / "Sincronização bloqueada").
enum RouteSyncState {
  /// Nothing queued, or everything queued is already synced.
  idle,

  /// A FIFO drain pass is running for this route right now.
  syncing,

  /// At least one row for this route is `blocked` (spec Ruling 6) — the
  /// queue is halted until the field worker retries it.
  blocked,
}

/// An immutable snapshot of one route's outbox drain, emitted on
/// `SyncWorker.statusFor`'s stream after every pass and every state change.
class RouteSyncStatus {
  const RouteSyncStatus({
    required this.routeId,
    required this.state,
    required this.pending,
    required this.blocked,
  });

  final String routeId;
  final RouteSyncState state;

  /// Count of `pending`/`failed` rows still owed to the network.
  final int pending;

  /// Count of `blocked` rows awaiting a manual retry.
  final int blocked;
}
