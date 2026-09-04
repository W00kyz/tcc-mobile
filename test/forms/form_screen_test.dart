import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:route_monitor/forms/form_draft_store.dart';
import 'package:route_monitor/forms/form_providers.dart';
import 'package:route_monitor/forms/form_schema.dart';
import 'package:route_monitor/forms/form_screen.dart';

import '../support/in_memory_database.dart';

const _executionId = 'exec1';
const _routeStopId = 'stop1';

FormQuestion _question({
  required String stableKey,
  required int orderIndex,
  required QuestionType type,
  String prompt = 'Prompt',
  bool required = false,
  List<String> options = const [],
  String contentHash = 'hash',
}) => FormQuestion(
  stableKey: stableKey,
  orderIndex: orderIndex,
  prompt: prompt,
  type: type,
  required: required,
  options: options,
  contentHash: contentHash,
);

/// One question of each [QuestionType], in `orderIndex` order.
FormSchema _oneOfEachType() => FormSchema(
  formVersionId: 'v1',
  questions: [
    _question(stableKey: 'q-text', orderIndex: 0, type: QuestionType.text),
    _question(
      stableKey: 'q-number',
      orderIndex: 1,
      type: QuestionType.number,
    ),
    _question(
      stableKey: 'q-bool',
      orderIndex: 2,
      type: QuestionType.boolean,
      prompt: 'Área limpa?',
    ),
    _question(
      stableKey: 'q-single',
      orderIndex: 3,
      type: QuestionType.singleChoice,
      options: ['baixo', 'médio', 'alto'],
    ),
    _question(
      stableKey: 'q-multi',
      orderIndex: 4,
      type: QuestionType.multiChoice,
      options: ['a', 'b', 'c'],
    ),
  ],
);

Widget _app(DriftFormDraftStore store) => ProviderScope(
  overrides: [formDraftStoreProvider.overrideWithValue(store)],
  child: const MaterialApp(home: FormScreen(executionId: _executionId)),
);

/// Pumps [FormScreen] on a surface tall enough that the whole ListView (5
/// questions, 3 with option lists) builds without scrolling — ListView's
/// `children` only realizes elements within the viewport/cache extent, and
/// a stock test surface is too short for every question to exist in the
/// tree at once.
Future<void> _pumpForm(WidgetTester tester, DriftFormDraftStore store) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  await tester.pumpWidget(_app(store));
  await tester.pumpAndSettle();
}

void main() {
  late DriftFormDraftStore store;

  setUp(() {
    final db = inMemoryDatabase();
    addTearDown(db.close);
    store = DriftFormDraftStore(db);
  });

  testWidgets('renders one field per question type', (tester) async {
    await store.snapshotFrom(_executionId, _routeStopId, _oneOfEachType());

    await _pumpForm(tester, store);

    expect(find.byType(TextFormField), findsNWidgets(2)); // text + number
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.byType(RadioListTile<String>), findsNWidgets(3));
    expect(find.byType(CheckboxListTile), findsNWidgets(3));
  });

  testWidgets('toggling the boolean switch writes true to the store', (
    tester,
  ) async {
    await store.snapshotFrom(_executionId, _routeStopId, _oneOfEachType());

    await _pumpForm(tester, store);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    final items = await store.itemsFor(_executionId);
    final boolItem = items.singleWhere((i) => i.stableKey == 'q-bool');
    expect(boolItem.value, isTrue);
  });

  testWidgets(
    'each question field carries a ValueKey(stableKey), so Flutter '
    'reconciles by question identity rather than position during a live '
    'reconcile (Important-2 — a positional-only reconcile risked an '
    "in-flight TextFormField's uncommitted text ending up rendered under "
    "the wrong question's prompt)",
    (tester) async {
      await store.snapshotFrom(_executionId, _routeStopId, _oneOfEachType());

      await _pumpForm(tester, store);

      for (final stableKey in [
        'q-text',
        'q-number',
        'q-bool',
        'q-single',
        'q-multi',
      ]) {
        expect(
          find.byKey(ValueKey(stableKey)),
          findsOneWidget,
          reason: '$stableKey should have its own ValueKey',
        );
      }
    },
  );

  testWidgets(
    'a needsReanswer item shows the warning and clears on interaction',
    (tester) async {
      final v1 = FormSchema(
        formVersionId: 'v1',
        questions: [
          _question(
            stableKey: 'q-bool',
            orderIndex: 0,
            type: QuestionType.boolean,
            contentHash: 'A',
          ),
        ],
      );
      await store.snapshotFrom(_executionId, _routeStopId, v1);
      await store.setAnswer(_executionId, 'q-bool', true);

      // Reconcile with a changed content hash for the same key, mirroring
      // Task 11's own reconcile test — this is the store's only path to a
      // `needsReanswer == true` item.
      final v2 = FormSchema(
        formVersionId: 'v2',
        questions: [
          _question(
            stableKey: 'q-bool',
            orderIndex: 0,
            type: QuestionType.boolean,
            contentHash: 'B',
          ),
        ],
      );
      await store.reconcile(_executionId, _routeStopId, v2);

      final reconciled = await store.itemsFor(_executionId);
      expect(reconciled.single.needsReanswer, isTrue);
      expect(reconciled.single.value, isTrue); // answer survives the flag

      await _pumpForm(tester, store);

      expect(
        find.text('Esta pergunta mudou — responda de novo.'),
        findsOneWidget,
      );

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      final items = await store.itemsFor(_executionId);
      expect(items.single.needsReanswer, isFalse);

      expect(
        find.text('Esta pergunta mudou — responda de novo.'),
        findsNothing,
      );
    },
  );
}
