/// The wire shape of `RouteStopOut.form` from `GET /routes/me` (backend
/// `app/schemas/route.py`) — one form version and its ordered questions.
///
/// A `stop.form` is only ever the stop's PUBLISHED `active_form_version`
/// (Task 4 restricts `active_form_version` to PUBLISHED), so every question
/// here always carries a non-null `content_hash` — a DRAFT question can have
/// a null hash on the wire, but that shape never reaches this parser.
enum QuestionType {
  text,
  number,
  boolean,
  singleChoice,
  multiChoice;

  static QuestionType fromWire(String value) => switch (value) {
    'TEXT' => QuestionType.text,
    'NUMBER' => QuestionType.number,
    'BOOLEAN' => QuestionType.boolean,
    'SINGLE_CHOICE' => QuestionType.singleChoice,
    'MULTI_CHOICE' => QuestionType.multiChoice,
    _ => throw ArgumentError(
      'Unknown question_type "$value"; expected TEXT, NUMBER, BOOLEAN, '
      'SINGLE_CHOICE or MULTI_CHOICE.',
    ),
  };

  String get wireName => switch (this) {
    QuestionType.text => 'TEXT',
    QuestionType.number => 'NUMBER',
    QuestionType.boolean => 'BOOLEAN',
    QuestionType.singleChoice => 'SINGLE_CHOICE',
    QuestionType.multiChoice => 'MULTI_CHOICE',
  };
}

/// One question of a published form version, keyed by `stableKey` — the
/// identity the RF39/RF40 reconcile diff (spec §6.3) matches across versions,
/// independent of `orderIndex` or wording.
class FormQuestion {
  const FormQuestion({
    required this.stableKey,
    required this.orderIndex,
    required this.prompt,
    required this.type,
    required this.required,
    required this.options,
    required this.contentHash,
  });

  factory FormQuestion.fromJson(Map<String, dynamic> json) => FormQuestion(
    stableKey: json['stable_key'] as String,
    orderIndex: json['order_index'] as int,
    prompt: json['prompt'] as String,
    type: QuestionType.fromWire(json['question_type'] as String),
    required: json['required'] as bool,
    options: (json['options'] as List<dynamic>).cast<String>(),
    contentHash: json['content_hash'] as String,
  );

  final String stableKey;
  final int orderIndex;
  final String prompt;
  final QuestionType type;
  final bool required;
  final List<String> options;

  /// Hash of the question's content (prompt/type/required/options). A change
  /// here is what the diff treats as "this question actually changed" and
  /// flags for re-answer, as opposed to a cosmetic-only reorder.
  final String contentHash;
}

/// A published form version and its ordered questions, as embedded in a
/// `GET /routes/me` stop.
class FormSchema {
  const FormSchema({required this.formVersionId, required this.questions});

  factory FormSchema.fromJson(Map<String, dynamic> json) => FormSchema(
    formVersionId: json['form_version_id'] as String,
    questions: (json['questions'] as List<dynamic>)
        .map((q) => FormQuestion.fromJson(q as Map<String, dynamic>))
        .toList(),
  );

  final String formVersionId;
  final List<FormQuestion> questions;
}
