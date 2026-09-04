import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:route_monitor/forms/form_schema.dart';
// `hide FormDraftItem`: Drift's generated row class for the `FormDraftItems`
// table is itself named `FormDraftItem`, colliding with this file's own
// decoded-item class of the same name (the brief's public shape). The
// generated type is never spelled directly in this file — row values flow
// through inference (`rows.map((row) => ...)`) instead.
import 'package:route_monitor/local/app_database.dart' hide FormDraftItem;

/// A decoded `FormDraftItems` row, free of any Drift type.
class FormDraftItem {
  const FormDraftItem({
    required this.stableKey,
    required this.orderIndex,
    required this.prompt,
    required this.type,
    required this.required,
    required this.options,
    required this.contentHash,
    required this.value,
    required this.needsReanswer,
  });

  final String stableKey;
  final int orderIndex;
  final String prompt;
  final QuestionType type;
  final bool required;
  final List<String> options;
  final String contentHash;

  /// The stored answer, JSON-primitive (bool/num/String/`List<String>`), or
  /// null when unanswered.
  final Object? value;
  final bool needsReanswer;
}

/// On-device draft of a stop's form answers, keyed by `(executionId,
/// stableKey)` (spec §6.1/§6.3). Written on check-in success
/// (`snapshotFrom`), read/edited while the stop is `IN_PROGRESS`
/// (`itemsFor`/`setAnswer`/`isComplete`), reconciled against a re-fetched
/// `FormSchema` on every sync trigger (`reconcile` — RF39/RF40, Ruling 10),
/// and dropped on check-out success (`clear`). The diff never leaves the
/// device: the server only ever sees the final answers at submit time.
abstract class FormDraftStore {
  Future<void> snapshotFrom(
    String executionId,
    String routeStopId,
    FormSchema schema,
  );

  Future<List<FormDraftItem>> itemsFor(String executionId);

  Future<void> setAnswer(String executionId, String stableKey, Object? value);

  Future<void> clear(String executionId);

  Future<bool> isComplete(String executionId);

  Future<void> reconcile(
    String executionId,
    String routeStopId,
    FormSchema newSchema,
  );
}

class DriftFormDraftStore implements FormDraftStore {
  DriftFormDraftStore(this._db);

  final AppDatabase _db;

  @override
  Future<void> snapshotFrom(
    String executionId,
    String routeStopId,
    FormSchema schema,
  ) {
    // insertOrIgnore, not insertOnConflictUpdate: a re-check-in on the same
    // executionId (a retried attempt after a flaky mark, mirroring
    // DriftStopProgressStore) must not clobber an answer already drafted —
    // only rows missing for this (executionId, stableKey) get created.
    return _db.batch((batch) {
      batch.insertAll(
        _db.formDraftItems,
        schema.questions
            .map((q) => _companionFor(executionId, routeStopId, schema, q))
            .toList(),
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  @override
  Future<List<FormDraftItem>> itemsFor(String executionId) async {
    final rows =
        await (_db.select(_db.formDraftItems)
              ..where((row) => row.executionId.equals(executionId))
              ..orderBy([(row) => OrderingTerm.asc(row.orderIndex)]))
            .get();
    return rows
        .map(
          (row) => FormDraftItem(
            stableKey: row.stableKey,
            orderIndex: row.orderIndex,
            prompt: row.prompt,
            type: QuestionType.fromWire(row.questionType),
            required: row.required,
            options: (jsonDecode(row.optionsJson) as List<dynamic>)
                .cast<String>(),
            contentHash: row.contentHash,
            value: row.valueJson == null ? null : jsonDecode(row.valueJson!),
            needsReanswer: row.needsReanswer,
          ),
        )
        .toList();
  }

  @override
  Future<void> setAnswer(
    String executionId,
    String stableKey,
    Object? value,
  ) {
    final update = _db.update(_db.formDraftItems)
      ..where(
        (row) =>
            row.executionId.equals(executionId) &
            row.stableKey.equals(stableKey),
      );
    return update.write(
      FormDraftItemsCompanion(
        valueJson: Value(value == null ? null : jsonEncode(value)),
        needsReanswer: const Value(false),
      ),
    );
  }

  @override
  Future<void> clear(String executionId) {
    return (_db.delete(
      _db.formDraftItems,
    )..where((row) => row.executionId.equals(executionId))).go();
  }

  @override
  Future<bool> isComplete(String executionId) async {
    final items = await itemsFor(executionId);
    return items.every((i) => !i.needsReanswer) &&
        items.where((i) => i.required).every((i) => i.value != null);
  }

  @override
  Future<void> reconcile(
    String executionId,
    String routeStopId,
    FormSchema newSchema,
  ) async {
    await _db.transaction(() async {
      final current = {
        for (final item in await itemsFor(executionId)) item.stableKey: item,
      };
      final newKeys = newSchema.questions.map((q) => q.stableKey).toSet();

      for (final q in newSchema.questions) {
        final existing = current[q.stableKey];
        // Same hash -> cosmetic-only refresh, answer and needsReanswer
        // untouched. Different hash (or brand-new key) -> the upsert below
        // already carries the right value/needsReanswer through
        // _companionFor's defaults (null/false) or the explicit override.
        final needsReanswer =
            existing != null && existing.contentHash != q.contentHash;
        await _db
            .into(_db.formDraftItems)
            .insertOnConflictUpdate(
              _companionFor(
                executionId,
                routeStopId,
                newSchema,
                q,
              ).copyWith(
                valueJson: Value(
                  existing == null ? null : _encode(existing.value),
                ),
                needsReanswer: Value(
                  existing != null && (existing.needsReanswer || needsReanswer),
                ),
              ),
            );
      }

      final droppedKeys = current.keys.where((k) => !newKeys.contains(k));
      for (final stableKey in droppedKeys) {
        await (_db.delete(_db.formDraftItems)..where(
              (row) =>
                  row.executionId.equals(executionId) &
                  row.stableKey.equals(stableKey),
            ))
            .go();
      }
    });
  }

  static String? _encode(Object? value) =>
      value == null ? null : jsonEncode(value);

  FormDraftItemsCompanion _companionFor(
    String executionId,
    String routeStopId,
    FormSchema schema,
    FormQuestion q,
  ) {
    return FormDraftItemsCompanion.insert(
      executionId: executionId,
      stableKey: q.stableKey,
      routeStopId: routeStopId,
      formVersionId: schema.formVersionId,
      orderIndex: q.orderIndex,
      prompt: q.prompt,
      questionType: q.type.wireName,
      required: q.required,
      optionsJson: jsonEncode(q.options),
      contentHash: q.contentHash,
    );
  }
}
