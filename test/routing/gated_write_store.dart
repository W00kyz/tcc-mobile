import 'dart:async';

import 'package:route_monitor/local/local_write_store.dart';

import 'map_home_fakes.dart';

/// An [InMemoryLocalWriteStore] whose check-out enqueue waits on [gate], so a
/// test can look at the screen while the row is not written yet (RNF06).
class GatedLocalWriteStore extends InMemoryLocalWriteStore {
  final Completer<void> gate = Completer<void>();

  /// Flips once the check-out row is actually in the store.
  bool checkOutWritten = false;

  @override
  Future<bool> enqueue({
    required String id,
    required PendingOpKind kind,
    required Map<String, dynamic> payload,
    required String routeId,
    PendingOpState initialState = PendingOpState.pending,
  }) async {
    if (kind == PendingOpKind.checkOut) await gate.future;
    final inserted = await super.enqueue(
      id: id,
      kind: kind,
      payload: payload,
      routeId: routeId,
      initialState: initialState,
    );
    if (kind == PendingOpKind.checkOut) checkOutWritten = true;
    return inserted;
  }
}
