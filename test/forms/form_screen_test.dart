import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:route_monitor/execution/evidence_list.dart';
import 'package:route_monitor/execution/evidence_thumbnail.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/forms/form_draft_store.dart';
import 'package:route_monitor/forms/form_providers.dart';
import 'package:route_monitor/forms/form_schema.dart';
import 'package:route_monitor/forms/form_screen.dart';
import 'package:route_monitor/forms/media_photo_taker.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart' show PendingOpState;

import '../support/in_memory_database.dart';

const _executionId = 'exec1';
const _routeStopId = 'stop1';
const _routeId = 'route1';

/// Hands out the keys a real capture would generate, one per "photo".
class _FakeMediaPhotoTaker implements MediaPhotoTaker {
  _FakeMediaPhotoTaker(this._keys);

  final List<String> _keys;
  int taken = 0;

  @override
  Future<String?> take({
    required String routeId,
    required String executionId,
  }) async => _keys[taken++];
}

/// The stop's evidence list as the route screen loads it: one local photo
/// per key, so the form can draw a thumbnail for each.
List<EvidenceListEntry> _photosFor(List<String> keys) => [
  for (final key in keys)
    EvidenceListEntry(
      kind: 'PHOTO',
      syncState: PendingOpState.pending,
      capturedAt: DateTime.utc(2026, 10, 19),
      photoBytes: _onePixelPng,
      idempotencyKey: key,
    ),
];

final _onePixelPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

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

Widget _app(
  DriftFormDraftStore store, {
  MediaPhotoTaker? taker,
  List<String> evidenceKeys = const [],
}) => ProviderScope(
  overrides: [
    formDraftStoreProvider.overrideWithValue(store),
    mediaPhotoTakerProvider.overrideWithValue(
      taker ?? _FakeMediaPhotoTaker(const []),
    ),
    stopEvidenceProvider.overrideWith(
      (ref, query) async => _photosFor(evidenceKeys),
    ),
  ],
  child: const MaterialApp(
    home: FormScreen(routeId: _routeId, executionId: _executionId),
  ),
);

/// Pumps [FormScreen] on a surface tall enough that the whole ListView (5
/// questions, 3 with option lists) builds without scrolling — ListView's
/// `children` only realizes elements within the viewport/cache extent, and
/// a stock test surface is too short for every question to exist in the
/// tree at once.
Future<void> _pumpForm(
  WidgetTester tester,
  DriftFormDraftStore store, {
  MediaPhotoTaker? taker,
  List<String> evidenceKeys = const [],
}) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  await tester.pumpWidget(
    _app(store, taker: taker, evidenceKeys: evidenceKeys),
  );
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
        find.text(AppStrings.formQuestionChanged),
        findsOneWidget,
      );

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      final items = await store.itemsFor(_executionId);
      expect(items.single.needsReanswer, isFalse);

      expect(
        find.text(AppStrings.formQuestionChanged),
        findsNothing,
      );
    },
  );

  group('MEDIA question', () {
    FormSchema mediaSchema({bool required = false}) => FormSchema(
      formVersionId: 'v1',
      questions: [
        _question(
          stableKey: 'q-photo',
          orderIndex: 0,
          type: QuestionType.media,
          prompt: 'Foto do piso',
          required: required,
        ),
      ],
    );

    Future<Object?> answer() async =>
        (await store.itemsFor(_executionId)).single.value;

    testWidgets('each photo taken is added to the answer by its key', (
      tester,
    ) async {
      await store.snapshotFrom(_executionId, _routeStopId, mediaSchema());
      final taker = _FakeMediaPhotoTaker(['k1', 'k2']);

      await _pumpForm(
        tester,
        store,
        taker: taker,
        evidenceKeys: ['k1', 'k2'],
      );
      await tester.tap(find.text(AppStrings.formMediaTakePhoto));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.formMediaTakePhoto));
      await tester.pumpAndSettle();

      expect(await answer(), ['k1', 'k2']);
      expect(find.byType(EvidenceThumbnail), findsNWidgets(2));
    });

    testWidgets('removing a photo drops only its key from the answer', (
      tester,
    ) async {
      await store.snapshotFrom(_executionId, _routeStopId, mediaSchema());
      await store.setAnswer(_executionId, 'q-photo', ['k1', 'k2']);

      await _pumpForm(tester, store, evidenceKeys: ['k1', 'k2']);
      await tester.tap(find.byTooltip(AppStrings.formMediaRemove).first);
      await tester.pumpAndSettle();

      // The photo itself stays queued as loose evidence: there is no delete.
      expect(await answer(), ['k2']);
    });

    testWidgets('a required photo question with every photo removed is '
        'still pending', (tester) async {
      await store.snapshotFrom(
        _executionId,
        _routeStopId,
        mediaSchema(required: true),
      );
      await store.setAnswer(_executionId, 'q-photo', ['k1']);

      await _pumpForm(tester, store, evidenceKeys: ['k1']);
      await tester.tap(find.byTooltip(AppStrings.formMediaRemove));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.formPending(1)), findsOneWidget);
      expect(await store.isComplete(_executionId), isFalse);
    });

    testWidgets('at the 10-photo limit the camera button is disabled', (
      tester,
    ) async {
      final keys = [for (var i = 0; i < 10; i++) 'k$i'];
      await store.snapshotFrom(_executionId, _routeStopId, mediaSchema());
      await store.setAnswer(_executionId, 'q-photo', keys);

      await _pumpForm(tester, store, evidenceKeys: keys);

      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text(AppStrings.formMediaTakePhoto),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(find.text(AppStrings.formMediaLimit), findsOneWidget);
    });
  });
}
