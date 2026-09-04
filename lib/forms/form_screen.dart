import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/forms/form_draft_store.dart';
import 'package:route_monitor/forms/form_providers.dart';
import 'package:route_monitor/forms/form_schema.dart' show QuestionType;

/// The dynamic form renderer (spec §6.5) — a stop's draft questions, one
/// widget per `QuestionType`, edited in place while the stop is
/// `IN_PROGRESS`. `executionId` is the only input; everything else comes
/// from [formDraftProvider].
class FormScreen extends ConsumerWidget {
  const FormScreen({required this.executionId, super.key});

  final String executionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(formDraftProvider(executionId));
    return Scaffold(
      appBar: AppBar(title: const Text('Formulário')),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('Não foi possível carregar o formulário.'),
        ),
        data: (items) {
          // `itemsFor` already orders by `orderIndex`; re-sorting here is
          // just defensive against a future store implementation that
          // doesn't bother.
          final sorted = [...items]
            ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final item in sorted)
                      _QuestionField(executionId: executionId, item: item),
                  ],
                ),
              ),
              _Footer(executionId: executionId),
            ],
          );
        },
      ),
    );
  }
}

/// One question's field, switched on [FormDraftItem.type]. A `needsReanswer`
/// item gets a warning banner above the field; touching the field clears the
/// flag through `setAnswer` (Task 11 guarantee).
class _QuestionField extends ConsumerWidget {
  const _QuestionField({required this.executionId, required this.item});

  final String executionId;
  final FormDraftItem item;

  Future<void> _answer(WidgetRef ref, Object? value) async {
    await ref
        .read(formDraftStoreProvider)
        .setAnswer(executionId, item.stableKey, value);
    ref
      ..invalidate(formDraftProvider(executionId))
      ..invalidate(formDraftCompleteProvider(executionId));
  }

  String get _promptLabel =>
      item.required ? '${item.prompt} (obrigatória)' : item.prompt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final field = switch (item.type) {
      QuestionType.text => TextFormField(
        initialValue: item.value as String? ?? '',
        decoration: InputDecoration(labelText: _promptLabel),
        onChanged: (value) => unawaited(_answer(ref, value)),
      ),
      QuestionType.number => TextFormField(
        keyboardType: TextInputType.number,
        initialValue: item.value?.toString() ?? '',
        decoration: InputDecoration(labelText: _promptLabel),
        onChanged: (value) {
          final parsed = num.tryParse(value);
          // Tolerate a partial, unparseable value while the user is still
          // typing (e.g. "-" or "") — don't write it as the answer.
          if (parsed != null) unawaited(_answer(ref, parsed));
        },
      ),
      QuestionType.boolean => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: item.value as bool? ?? false,
        onChanged: (value) => unawaited(_answer(ref, value)),
        title: Text(_promptLabel),
      ),
      QuestionType.singleChoice => RadioGroup<String>(
        groupValue: item.value as String?,
        onChanged: (value) => unawaited(_answer(ref, value)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _promptLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final option in item.options)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: option,
                title: Text(option),
              ),
          ],
        ),
      ),
      QuestionType.multiChoice => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _promptLabel,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          for (final option in item.options)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: (item.value as List<String>? ?? const []).contains(
                option,
              ),
              onChanged: (checked) {
                final current = List<String>.from(
                  item.value as List<String>? ?? const [],
                );
                if (checked ?? false) {
                  current.add(option);
                } else {
                  current.remove(option);
                }
                unawaited(_answer(ref, current));
              },
              title: Text(option),
            ),
        ],
      ),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: item.needsReanswer
          ? BoxDecoration(
              color: Colors.amber.shade50,
              border: Border.all(color: Colors.amber),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      // MaterialType.transparency: a ListTile inside (radio/checkbox/switch
      // rows) paints its background and ink splashes on the nearest
      // Material ancestor — without one here, that painting would land on
      // the DecoratedBox above and be invisible under the warning tint.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.needsReanswer)
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'Esta pergunta mudou — responda de novo.',
                  style: TextStyle(
                    color: Colors.brown,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            field,
          ],
        ),
      ),
    );
  }
}

/// "Formulário completo" (green) or "N pendências", plus a plain back
/// button — the check-out itself stays on the route screen, gated by
/// `formDraftCompleteProvider` (spec §6.2).
class _Footer extends ConsumerWidget {
  const _Footer({required this.executionId});

  final String executionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(formDraftProvider(executionId));
    final pending = itemsAsync.maybeWhen(
      data: (items) => items
          .where((i) => i.needsReanswer || (i.required && i.value == null))
          .length,
      orElse: () => null,
    );

    return SafeArea(
      minimum: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: pending == null
                ? const SizedBox.shrink()
                : Text(
                    pending == 0
                        ? 'Formulário completo'
                        : '$pending pendências',
                    style: TextStyle(
                      color: pending == 0 ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Voltar'),
          ),
        ],
      ),
    );
  }
}
