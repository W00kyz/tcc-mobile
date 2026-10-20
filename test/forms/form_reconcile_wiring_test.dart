import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/forms/form_draft_store.dart';
import 'package:route_monitor/forms/form_providers.dart';
import 'package:route_monitor/forms/form_reconciliation.dart';
import 'package:route_monitor/forms/form_schema.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';

import '../support/in_memory_database.dart';

FormQuestion _question({
  required String stableKey,
  String contentHash = 'hash',
}) => FormQuestion(
  stableKey: stableKey,
  orderIndex: 0,
  prompt: 'Prompt',
  type: QuestionType.text,
  required: false,
  options: const [],
  contentHash: contentHash,
);

class _FakeRouteRepository implements RouteRepository {
  _FakeRouteRepository(this.routes);
  final List<RouteSummary> routes;

  @override
  Future<List<RouteSummary>> fetchMyRoutes({DateTime? date}) async => routes;

  @override
  Future<RouteSummary> startRoute({
    required String routeId,
    required double latitude,
    required double longitude,
    required DateTime startedAt,
  }) async => throw UnimplementedError('not exercised in this test');
}

RouteSummary _routeWithForm(FormSchema form) => RouteSummary(
  id: 'route-A',
  fieldWorkerName: 'João',
  routeDate: DateTime.utc(2026, 9),
  routeType: 'REGULAR',
  status: 'IN_PROGRESS',
  startedAt: DateTime.utc(2026, 9, 1, 8),
  stops: [
    RouteStopSummary(
      id: 'stop-1',
      orderIndex: 0,
      status: 'IN_PROGRESS',
      servicePointName: 'Sala 101',
      latitude: -7.2,
      longitude: -35.9,
      form: form,
    ),
  ],
);

void main() {
  test(
    'formReconciliationProvider reconciles a stale v1 draft to the '
    'freshly-fetched v2 schema once myRoutesProvider resolves',
    () async {
      final db = inMemoryDatabase();
      addTearDown(db.close);
      final stopProgress = DriftStopProgressStore(db);
      final formDraftStore = DriftFormDraftStore(db);

      final v1 = FormSchema(
        formVersionId: 'v1',
        questions: [_question(stableKey: 'q1', contentHash: 'h1')],
      );
      final v2 = FormSchema(
        formVersionId: 'v2',
        questions: [_question(stableKey: 'q1', contentHash: 'h2-changed')],
      );

      await stopProgress.upsertInProgress('stop-1', 'exec-1');
      await formDraftStore.snapshotFrom('exec-1', 'stop-1', v1);
      await formDraftStore.setAnswer('exec-1', 'q1', 'old answer');

      final container = ProviderContainer(
        overrides: [
          routeRepositoryProvider.overrideWithValue(
            _FakeRouteRepository([_routeWithForm(v2)]),
          ),
          stopProgressStoreProvider.overrideWithValue(stopProgress),
          formDraftStoreProvider.overrideWithValue(formDraftStore),
        ],
      );
      addTearDown(container.dispose);

      // Resolve myRoutesProvider first, then watch the reconcile provider —
      // it fires its fire-and-forget loop off an already-resolved AsyncData
      // rather than the initial AsyncLoading.
      await container.read(myRoutesProvider.future);
      container.read(formReconciliationProvider);
      await pumpEventQueue();

      final items = await formDraftStore.itemsFor('exec-1');
      expect(items.single.formVersionId, 'v2');
      expect(items.single.contentHash, 'h2-changed');
      // The question's content actually changed (h1 -> h2-changed), so the
      // reconciled item is flagged for re-answer (spec §6.3) even though the
      // prior answer value is preserved rather than discarded outright.
      expect(items.single.needsReanswer, isTrue);
    },
  );

  test(
    'formReconciliationProvider leaves a draft untouched when the fetched '
    'form_version_id has not changed',
    () async {
      final db = inMemoryDatabase();
      addTearDown(db.close);
      final stopProgress = DriftStopProgressStore(db);
      final formDraftStore = DriftFormDraftStore(db);

      final v1 = FormSchema(
        formVersionId: 'v1',
        questions: [_question(stableKey: 'q1')],
      );

      await stopProgress.upsertInProgress('stop-1', 'exec-1');
      await formDraftStore.snapshotFrom('exec-1', 'stop-1', v1);
      await formDraftStore.setAnswer('exec-1', 'q1', 'kept');

      final container = ProviderContainer(
        overrides: [
          routeRepositoryProvider.overrideWithValue(
            _FakeRouteRepository([_routeWithForm(v1)]),
          ),
          stopProgressStoreProvider.overrideWithValue(stopProgress),
          formDraftStoreProvider.overrideWithValue(formDraftStore),
        ],
      );
      addTearDown(container.dispose);

      await container.read(myRoutesProvider.future);
      container.read(formReconciliationProvider);
      await pumpEventQueue();

      final items = await formDraftStore.itemsFor('exec-1');
      expect(items.single.value, 'kept');
      expect(items.single.needsReanswer, isFalse);
    },
  );

  test(
    'formReconciliationProvider invalidates formDraftProvider and '
    'formDraftCompleteProvider for a stop it actually reconciled — '
    "regression for the stale-cache bug found writing Task 15's "
    'integration test: reconcile() correctly rewrote the on-disk draft, but '
    'nothing told these two cached FutureProviders to recompute, so '
    'RouteScreen\'s "Concluir" gate and a re-opened FormScreen kept serving '
    'pre-reconcile state indefinitely',
    () async {
      final db = inMemoryDatabase();
      addTearDown(db.close);
      final stopProgress = DriftStopProgressStore(db);
      final formDraftStore = DriftFormDraftStore(db);

      final v1 = FormSchema(
        formVersionId: 'v1',
        questions: [_question(stableKey: 'q1', contentHash: 'h1')],
      );
      final v2 = FormSchema(
        formVersionId: 'v2',
        questions: [_question(stableKey: 'q1', contentHash: 'h2-changed')],
      );

      await stopProgress.upsertInProgress('stop-1', 'exec-1');
      await formDraftStore.snapshotFrom('exec-1', 'stop-1', v1);
      await formDraftStore.setAnswer('exec-1', 'q1', 'old answer');

      final container = ProviderContainer(
        overrides: [
          routeRepositoryProvider.overrideWithValue(
            _FakeRouteRepository([_routeWithForm(v2)]),
          ),
          stopProgressStoreProvider.overrideWithValue(stopProgress),
          formDraftStoreProvider.overrideWithValue(formDraftStore),
        ],
      );
      addTearDown(container.dispose);

      // Seed both providers' caches with the PRE-reconcile (v1) state, the
      // same way RouteScreen/FormScreen would have from being open before
      // the new form version landed — this is what must NOT stay stale.
      final beforeItems = await container.read(
        formDraftProvider('exec-1').future,
      );
      expect(beforeItems.single.needsReanswer, isFalse);
      final beforeComplete = await container.read(
        formDraftCompleteProvider('exec-1').future,
      );
      expect(beforeComplete, isTrue);

      await container.read(myRoutesProvider.future);
      container.read(formReconciliationProvider);
      await pumpEventQueue();

      // Both cached providers must have been invalidated and recomputed to
      // the post-reconcile (v2) state — not the stale AsyncData read above.
      final afterItems = await container.read(
        formDraftProvider('exec-1').future,
      );
      expect(afterItems.single.needsReanswer, isTrue);
      final afterComplete = await container.read(
        formDraftCompleteProvider('exec-1').future,
      );
      expect(afterComplete, isFalse);
    },
  );
}
