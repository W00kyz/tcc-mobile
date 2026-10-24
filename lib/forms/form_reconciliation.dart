import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/execution/execution_providers.dart'
    show stopProgressStoreProvider;
import 'package:route_monitor/forms/form_draft_store.dart';
import 'package:route_monitor/forms/form_providers.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';

/// RF39/RF40 reconciliation on re-fetch (spec §6.3, Task 11's
/// `FormDraftStore.reconcile`): every time `myDayProvider` resolves a
/// fresh day, diff each `IN_PROGRESS` stop's local form draft against
/// the stop's currently-published `FormSchema` and reconcile it when the
/// versions differ. A stale draft otherwise only gets reconciled on its next
/// check-in/out, which may be hours away — this closes that gap the moment
/// new data arrives (on app resume, reconnect, or a manual route refresh).
///
/// A plain `Provider<void>` rather than a `ref.listen`: nothing needs its
/// value, but Riverpod only re-evaluates a provider body — re-running this
/// loop — while something keeps it watched. `FormReconciliationTrigger`
/// below is that "something", mounted once alongside `SyncTriggers` in
/// `main.dart`'s `builder:` so it stays alive for the app's whole lifetime.
/// The loop itself is fire-and-forget: it must never block the route list
/// from rendering, and a failure here (a transient store error) has no user
/// waiting on it — the next re-fetch tries again.
final formReconciliationProvider = Provider<void>((ref) {
  final route = ref.watch(myDayProvider).value?.route;
  if (route == null) return;
  final stopProgress = ref.watch(stopProgressStoreProvider);
  final formDraftStore = ref.watch(formDraftStoreProvider);
  unawaited(_reconcileRoute(ref, route, stopProgress, formDraftStore));
});

Future<void> _reconcileRoute(
  Ref ref,
  RouteSummary route,
  StopProgressStore stopProgress,
  FormDraftStore formDraftStore,
) async {
  for (final stop in route.stops) {
    await _reconcileStopIfStale(ref, stop, stopProgress, formDraftStore);
  }
}

Future<void> _reconcileStopIfStale(
  Ref ref,
  RouteStopSummary stop,
  StopProgressStore stopProgress,
  FormDraftStore formDraftStore,
) async {
  final form = stop.form;
  if (form == null) return;

  final progress = await stopProgress.progressFor(stop.id);
  if (progress == null || progress.status != StopLocalStatus.inProgress) {
    return;
  }

  final items = await formDraftStore.itemsFor(progress.executionId);
  if (items.isEmpty) return;
  // Same formVersionId on every item (they're all snapshotted/reconciled
  // together) — any one item's value tells whether the fresh fetch changed
  // anything worth reconciling.
  if (items.first.formVersionId == form.formVersionId) return;

  await formDraftStore.reconcile(progress.executionId, stop.id, form);
  // The reconcile above just rewrote this stop's draft on disk; without this,
  // `formDraftProvider`/`formDraftCompleteProvider` (both plain, non-
  // autoDispose `FutureProvider.family`s — see form_providers.dart) would
  // keep serving their last-cached AsyncValue forever, so a re-opened
  // FormScreen and RouteScreen's "Concluir" gate would silently show
  // pre-reconcile state until the field worker happened to answer a question
  // (form_screen.dart's own invalidate on `setAnswer`). Scoped to only the
  // stop(s) actually reconciled this pass — invalidating on every tick for
  // every stop would defeat the caching for no reason.
  ref
    ..invalidate(formDraftProvider(progress.executionId))
    ..invalidate(formDraftCompleteProvider(progress.executionId));
}

/// Mounts [formReconciliationProvider] for the app's whole lifetime by
/// watching it on every build — see the provider's doc comment for why a
/// watcher is what keeps the reconcile loop running at all. Wraps
/// `SyncTriggers`' child in `main.dart`, the same "wrap, don't grow"
/// discipline `RouteMonitorApp` already follows for that widget.
class FormReconciliationTrigger extends ConsumerWidget {
  const FormReconciliationTrigger({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(formReconciliationProvider);
    return child;
  }
}
