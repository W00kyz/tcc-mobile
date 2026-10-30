import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
import 'package:route_monitor/sync/location_refusal.dart';

/// The refusals of location completions the worker has not been told about
/// yet. The background drain rejects a completion on another isolate, where
/// no listener hears it: the `rejected` row in SQLite is the notice, and
/// the ids already shown are kept in the shared sync meta, so each refusal is
/// told once however many times the app resumes or restarts.
///
///     for (final refusal in await notices.unannounced()) { show(refusal); }
class RefusalNotices {
  RefusalNotices(this._store, this._syncMeta);

  final LocalWriteStore _store;
  final SyncMetaStore _syncMeta;

  /// The rejected completions not acknowledged yet, oldest first.
  Future<List<LocationRefusal>> unannounced() async {
    final acknowledged = await _syncMeta.getAcknowledgedRefusals();
    return [
      for (final row in await _store.rejectedCompletions())
        if (!acknowledged.contains(row.id))
          LocationRefusal.fromRejectedRow(row),
    ];
  }

  /// Marks [operationId] as told. Ids of rows no longer rejected (a discarded
  /// stop) are dropped, so the set cannot grow without bound.
  Future<void> acknowledge(String operationId) async {
    final acknowledged = await _syncMeta.getAcknowledgedRefusals();
    final live = {for (final row in await _store.rejectedCompletions()) row.id};
    await _syncMeta.setAcknowledgedRefusals(
      {
        ...acknowledged,
        operationId,
      }.intersection(live),
    );
  }
}
