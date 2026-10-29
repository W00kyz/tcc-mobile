import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show FutureProviderFamily, ProviderFamily;

import 'package:route_monitor/execution/evidence_requirement.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';

/// The device's own photo count for one execution (see
/// `LocalWriteStore.localPhotoCountFor`), keyed by `executionId`.
final FutureProviderFamily<int, String> localPhotoCountProvider =
    FutureProvider.family<int, String>(
      (ref, executionId) =>
          ref.watch(localWriteStoreProvider).localPhotoCountFor(executionId),
    );

/// The larger of the on-device photo count and the merged list's: the local
/// outbox is the truth and works offline, the merged list can only add
/// photos the device no longer holds. `null` while the local count is not
/// known: "Concluir" never opens before knowing.
int? combinePhotoCounts({required int? local, required int? merged}) {
  if (local == null) return null;
  if (merged == null || merged < local) return local;
  return merged;
}

/// One stop's photo count for the "Concluir" gate and the 10-photo cap, keyed
/// by `(routeId, executionId)`. A network error or a still-loading merged list
/// never nulls it once the local count is known.
final ProviderFamily<int?, (String, String)> stopPhotoCountProvider =
    Provider.family<int?, (String, String)>((ref, query) {
      final executionId = query.$2;
      final merged = ref
          .watch(stopEvidenceProvider(query))
          .asData
          ?.value
          .where((entry) => entry.kind == 'PHOTO')
          .length;
      return combinePhotoCounts(
        local: ref.watch(localPhotoCountProvider(executionId)).asData?.value,
        merged: merged,
      );
    });

/// Whether [stop] may conclude now: an evidence stop needs its photos, read
/// from the device outbox first ([stopPhotoCountProvider]); with no open
/// execution there is no photo to count, so only a stop without the flag
/// passes. [watch] false reads once (a flow), true rebuilds on change (a
/// widget).
///
///     if (!stopMayConclude(ref, routeId, stop, executionId)) return;
bool stopMayConclude(
  WidgetRef ref,
  String routeId,
  RouteStopSummary stop,
  String? executionId, {
  bool watch = false,
}) {
  final provider = executionId == null
      ? null
      : stopPhotoCountProvider((routeId, executionId));
  final photoCount = provider == null
      ? null
      : (watch ? ref.watch(provider) : ref.read(provider));
  return canConcludeWithEvidence(
    requiresEvidence: stop.requiresEvidence,
    photoCount: photoCount,
  );
}
