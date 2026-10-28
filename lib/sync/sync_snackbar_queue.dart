import 'package:route_monitor/sync/sync_status.dart';

/// What the worker should be told about the sync, once (spec §6.7).
sealed class SyncNotice {
  const SyncNotice();
}

/// A pass started with [n] records to send.
class Sending extends SyncNotice {
  const Sending(this.n);
  final int n;
}

/// Everything sent, after a [Sending].
class AllSent extends SyncNotice {
  const AllSent();
}

/// [n] records wait for the network.
class Waiting extends SyncNotice {
  const Waiting(this.n);
  final int n;
}

/// [n] records are blocked and need the worker.
class Blocked extends SyncNotice {
  const Blocked(this.n);
  final int n;
}

/// The next batch cannot be pulled without a connection.
class NeedsNetworkForBatch extends SyncNotice {
  const NeedsNetworkForBatch();
}

/// Turns the sync status stream into at most one notice per moment of change:
/// never one per record, and "Tudo enviado" only after a "Enviando".
///
///     final notice = queue.next(before, after, online: true);
class SyncSnackbarQueue {
  bool _sent = false;
  int? _waitingAnnounced;

  SyncNotice? next(
    RouteSyncStatus previous,
    RouteSyncStatus current, {
    required bool online,
  }) {
    if (online) _waitingAnnounced = null;
    if (_unchanged(previous, current)) return null;
    if (current.blocked > previous.blocked) return Blocked(current.blocked);
    if (_started(previous, current)) {
      _sent = true;
      return Sending(current.pending);
    }
    if (_finished(current)) return _closeSending();
    return _waiting(current, online);
  }

  bool _unchanged(RouteSyncStatus a, RouteSyncStatus b) =>
      a.state == b.state && a.pending == b.pending && a.blocked == b.blocked;

  bool _started(RouteSyncStatus previous, RouteSyncStatus current) =>
      current.state == RouteSyncState.syncing &&
      previous.state != RouteSyncState.syncing &&
      current.pending > 0;

  bool _finished(RouteSyncStatus current) =>
      current.state == RouteSyncState.idle && current.pending == 0;

  SyncNotice? _closeSending() {
    if (!_sent) return null;
    _sent = false;
    return const AllSent();
  }

  SyncNotice? _waiting(RouteSyncStatus current, bool online) {
    if (online || current.pending == 0) return null;
    if (_waitingAnnounced == current.pending) return null;
    _waitingAnnounced = current.pending;
    return Waiting(current.pending);
  }
}
