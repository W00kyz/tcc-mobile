import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/forms/form_schema.dart';

void main() {
  group('QuestionType.fromWire', () {
    test('maps every wire value to its enum', () {
      expect(QuestionType.fromWire('TEXT'), QuestionType.text);
      expect(QuestionType.fromWire('NUMBER'), QuestionType.number);
      expect(QuestionType.fromWire('BOOLEAN'), QuestionType.boolean);
      expect(
        QuestionType.fromWire('SINGLE_CHOICE'),
        QuestionType.singleChoice,
      );
      expect(QuestionType.fromWire('MULTI_CHOICE'), QuestionType.multiChoice);
    });

    test('round-trips through wireName', () {
      for (final type in QuestionType.values) {
        expect(QuestionType.fromWire(type.wireName), type);
      }
    });

    test('throws on an unknown wire value', () {
      expect(
        () => QuestionType.fromWire('DATE'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('FormSchema.fromJson', () {
    test('parses form_version_id and questions', () {
      final schema = FormSchema.fromJson({
        'form_version_id': 'v1',
        'questions': [
          {
            'stable_key': 'q1',
            'order_index': 0,
            'prompt': 'Portão fechado?',
            'question_type': 'BOOLEAN',
            'required': true,
            'options': <String>[],
            'content_hash': 'abc',
          },
        ],
      });

      expect(schema.formVersionId, 'v1');
      expect(schema.questions, hasLength(1));

      final q = schema.questions.single;
      expect(q.stableKey, 'q1');
      expect(q.orderIndex, 0);
      expect(q.prompt, 'Portão fechado?');
      expect(q.type, QuestionType.boolean);
      expect(q.required, isTrue);
      expect(q.options, isEmpty);
      expect(q.contentHash, 'abc');
    });

    test('parses options for a choice question', () {
      final schema = FormSchema.fromJson({
        'form_version_id': 'v2',
        'questions': [
          {
            'stable_key': 'q2',
            'order_index': 1,
            'prompt': 'Qual turno?',
            'question_type': 'SINGLE_CHOICE',
            'required': false,
            'options': ['Manhã', 'Tarde', 'Noite'],
            'content_hash': 'def',
          },
        ],
      });

      final q = schema.questions.single;
      expect(q.type, QuestionType.singleChoice);
      expect(q.options, ['Manhã', 'Tarde', 'Noite']);
      expect(q.required, isFalse);
    });

    test('parses an empty question list', () {
      final schema = FormSchema.fromJson({
        'form_version_id': 'v3',
        'questions': <Map<String, dynamic>>[],
      });

      expect(schema.formVersionId, 'v3');
      expect(schema.questions, isEmpty);
    });
  });
}
