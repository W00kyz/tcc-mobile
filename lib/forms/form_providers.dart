import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;

import 'package:route_monitor/execution/execution_providers.dart'
    show appDatabaseProvider;
import 'package:route_monitor/forms/form_draft_store.dart';

final formDraftStoreProvider = Provider<FormDraftStore>(
  (ref) => DriftFormDraftStore(ref.watch(appDatabaseProvider)),
);

/// The current stop's draft items, ordered as `DriftFormDraftStore.itemsFor`
/// returns them (by `orderIndex` — spec §6.5). Invalidated after every
/// `setAnswer` so `FormScreen` re-renders with the fresh value/needsReanswer
/// state.
final FutureProviderFamily<List<FormDraftItem>, String> formDraftProvider =
    FutureProvider.family<List<FormDraftItem>, String>(
      (ref, executionId) =>
          ref.watch(formDraftStoreProvider).itemsFor(executionId),
    );

/// Backs the "Concluir" gate on the route screen (spec §6.2) — kept as its
/// own provider (rather than derived from `formDraftProvider`) so a widget
/// that only cares about completion doesn't rebuild on every item edit.
final FutureProviderFamily<bool, String> formDraftCompleteProvider =
    FutureProvider.family<bool, String>(
      (ref, executionId) =>
          ref.watch(formDraftStoreProvider).isComplete(executionId),
    );
