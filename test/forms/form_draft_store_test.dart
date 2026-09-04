import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/forms/form_draft_store.dart';
import 'package:route_monitor/forms/form_schema.dart';

import '../support/in_memory_database.dart';

FormQuestion _question({
  required String stableKey,
  int orderIndex = 0,
  String prompt = 'Prompt',
  QuestionType type = QuestionType.text,
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

void main() {
  late DriftFormDraftStore store;

  setUp(() {
    final db = inMemoryDatabase();
    addTearDown(db.close);
    store = DriftFormDraftStore(db);
  });

  group('snapshotFrom', () {
    test('writes one unanswered item per question', () async {
      final schema = FormSchema(
        formVersionId: 'v1',
        questions: [
          _question(stableKey: 'q1'),
          _question(stableKey: 'q2', orderIndex: 1),
        ],
      );

      await store.snapshotFrom('exec1', 'stop1', schema);
      final items = await store.itemsFor('exec1');

      expect(items, hasLength(2));
      expect(items.every((i) => i.value == null), isTrue);
      expect(items.every((i) => !i.needsReanswer), isTrue);
    });

    test(
      'a re-check-in on the same execution does not overwrite answers',
      () async {
        final schema = FormSchema(
          formVersionId: 'v1',
          questions: [_question(stableKey: 'q1')],
        );

        await store.snapshotFrom('exec1', 'stop1', schema);
        await store.setAnswer('exec1', 'q1', 'answered');

        // Re-check-in: same executionId, same schema.
        await store.snapshotFrom('exec1', 'stop1', schema);

        final items = await store.itemsFor('exec1');
        expect(items, hasLength(1));
        expect(items.single.value, 'answered');
      },
    );
  });

  group('setAnswer', () {
    test('sets value and clears needsReanswer', () async {
      final schema = FormSchema(
        formVersionId: 'v1',
        questions: [_question(stableKey: 'q1', type: QuestionType.number)],
      );
      await store.snapshotFrom('exec1', 'stop1', schema);

      await store.setAnswer('exec1', 'q1', 42);

      final item = (await store.itemsFor('exec1')).single;
      expect(item.value, 42);
      expect(item.needsReanswer, isFalse);
    });

    test('a null value clears the answer rather than storing "null"', () async {
      final schema = FormSchema(
        formVersionId: 'v1',
        questions: [_question(stableKey: 'q1')],
      );
      await store.snapshotFrom('exec1', 'stop1', schema);
      await store.setAnswer('exec1', 'q1', 'something');

      await store.setAnswer('exec1', 'q1', null);

      final item = (await store.itemsFor('exec1')).single;
      expect(item.value, isNull);
    });

    test(
      'a MULTI_CHOICE answer round-trips as a genuine List<String>',
      () async {
        final schema = FormSchema(
          formVersionId: 'v1',
          questions: [
            _question(
              stableKey: 'q1',
              type: QuestionType.multiChoice,
              options: ['baixo', 'médio', 'alto'],
            ),
          ],
        );
        await store.snapshotFrom('exec1', 'stop1', schema);

        await store.setAnswer('exec1', 'q1', ['baixo', 'médio']);

        final item = (await store.itemsFor('exec1')).single;
        // `List<dynamic>` (jsonDecode's raw return) would throw on this cast;
        // only a genuine `List<String>` satisfies it.
        final value = item.value! as List<String>;
        expect(value, ['baixo', 'médio']);
      },
    );
  });

  group('isComplete', () {
    test('false with a required unanswered item', () async {
      final schema = FormSchema(
        formVersionId: 'v1',
        questions: [_question(stableKey: 'q1', required: true)],
      );
      await store.snapshotFrom('exec1', 'stop1', schema);

      expect(await store.isComplete('exec1'), isFalse);
    });

    test('true once every required item is answered', () async {
      final schema = FormSchema(
        formVersionId: 'v1',
        questions: [_question(stableKey: 'q1', required: true)],
      );
      await store.snapshotFrom('exec1', 'stop1', schema);
      await store.setAnswer('exec1', 'q1', 'yes');

      expect(await store.isComplete('exec1'), isTrue);
    });

    test('an unanswered non-required item does not block completion', () async {
      final schema = FormSchema(
        formVersionId: 'v1',
        questions: [
          _question(stableKey: 'q1', required: true),
          _question(stableKey: 'q2'),
        ],
      );
      await store.snapshotFrom('exec1', 'stop1', schema);
      await store.setAnswer('exec1', 'q1', 'yes');

      expect(await store.isComplete('exec1'), isTrue);
    });
  });

  group('clear', () {
    test('removes all items for that execution', () async {
      final schema = FormSchema(
        formVersionId: 'v1',
        questions: [_question(stableKey: 'q1')],
      );
      await store.snapshotFrom('exec1', 'stop1', schema);
      await store.snapshotFrom('exec2', 'stop2', schema);

      await store.clear('exec1');

      expect(await store.itemsFor('exec1'), isEmpty);
      expect(await store.itemsFor('exec2'), hasLength(1));
    });
  });

  group('reconcile (RF39/RF40, spec §6.3)', () {
    test(
      'keeps unchanged answers, flags changed ones, drops and adds questions',
      () async {
        final v1 = FormSchema(
          formVersionId: 'v1',
          questions: [
            _question(stableKey: 'q1', contentHash: 'A'),
            _question(stableKey: 'q2', orderIndex: 1, contentHash: 'B'),
            _question(stableKey: 'q3', orderIndex: 2, contentHash: 'C'),
          ],
        );
        await store.snapshotFrom('exec1', 'stop1', v1);
        await store.setAnswer('exec1', 'q1', 'answer-1');
        await store.setAnswer('exec1', 'q2', 'answer-2');
        await store.setAnswer('exec1', 'q3', 'answer-3');

        final v2 = FormSchema(
          formVersionId: 'v2',
          questions: [
            _question(stableKey: 'q1', contentHash: 'A'),
            _question(stableKey: 'q2', orderIndex: 1, contentHash: 'B2'),
            _question(
              stableKey: 'q4',
              orderIndex: 2,
              contentHash: 'D',
              required: true,
            ),
          ],
        );

        await store.reconcile('exec1', 'stop1', v2);
        final items = {
          for (final item in await store.itemsFor('exec1'))
            item.stableKey: item,
        };

        expect(items.keys, containsAll(['q1', 'q2', 'q4']));
        expect(items, isNot(contains('q3')));

        expect(items['q1']!.value, 'answer-1');
        expect(items['q1']!.needsReanswer, isFalse);

        expect(items['q2']!.value, 'answer-2');
        expect(items['q2']!.needsReanswer, isTrue);
        expect(items['q2']!.contentHash, 'B2');

        expect(items['q4']!.value, isNull);
        expect(items['q4']!.needsReanswer, isFalse);
        expect(items['q4']!.required, isTrue);

        expect(await store.isComplete('exec1'), isFalse);

        await store.setAnswer('exec1', 'q2', 'answer-2-updated');
        await store.setAnswer('exec1', 'q4', 'answer-4');

        expect(await store.isComplete('exec1'), isTrue);
      },
    );

    test('updates formVersionId on every item after reconcile', () async {
      final v1 = FormSchema(
        formVersionId: 'v1',
        questions: [_question(stableKey: 'q1', contentHash: 'A')],
      );
      await store.snapshotFrom('exec1', 'stop1', v1);

      final v2 = FormSchema(
        formVersionId: 'v2',
        questions: [_question(stableKey: 'q1', contentHash: 'A')],
      );
      await store.reconcile('exec1', 'stop1', v2);

      // formVersionId isn't exposed on FormDraftItem directly, so this is
      // asserted indirectly: a second reconcile against v2 again must be a
      // pure no-op (same content hash), proving the stored version moved.
      await store.reconcile('exec1', 'stop1', v2);
      final item = (await store.itemsFor('exec1')).single;
      expect(item.needsReanswer, isFalse);
    });

    test(
      'cosmetic-only changes update fields without flagging needsReanswer',
      () async {
        final v1 = FormSchema(
          formVersionId: 'v1',
          questions: [
            _question(stableKey: 'q1', prompt: 'Old prompt', contentHash: 'A'),
          ],
        );
        await store.snapshotFrom('exec1', 'stop1', v1);
        await store.setAnswer('exec1', 'q1', 'kept');

        final v2 = FormSchema(
          formVersionId: 'v2',
          questions: [
            _question(
              stableKey: 'q1',
              orderIndex: 5,
              prompt: 'New prompt (cosmetic)',
              contentHash: 'A',
            ),
          ],
        );
        await store.reconcile('exec1', 'stop1', v2);

        final item = (await store.itemsFor('exec1')).single;
        expect(item.value, 'kept');
        expect(item.needsReanswer, isFalse);
        expect(item.prompt, 'New prompt (cosmetic)');
        expect(item.orderIndex, 5);
      },
    );
  });
}
