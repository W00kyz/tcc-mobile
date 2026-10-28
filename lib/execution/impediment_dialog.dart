import 'package:flutter/material.dart';

import 'package:route_monitor/execution/impossibility_reason_dialog.dart';
import 'package:route_monitor/l10n/strings.dart';

/// The outcome of [ImpedimentDialog]: the reason wire value, the derived
/// `scope`, and an optional free-text note. `null` from the dialog means the
/// field worker cancelled — nothing should be reported.
class ImpedimentChoice {
  const ImpedimentChoice({
    required this.scope,
    required this.reason,
    this.note,
  });

  /// `STOP` for just this stop ("Não consigo fazer este ponto"),
  /// `ROUTE_REMAINDER` when the field worker flipped "Não consigo continuar
  /// hoje" — every open stop of the batch goes back to the pool and the route
  /// pauses (spec 2026-10-20-alocacao-automatica §7.1).
  final String scope;

  /// A wire value from [impossibilityReasons] — `ACCESS_BLOCKED`,
  /// `SITE_REFUSAL`, `HEALTH_ISSUE` or `OTHER`.
  final String reason;

  /// The trimmed note, or `null` when the field left it blank.
  final String? note;
}

/// Opens [ImpedimentDialog] as a modal bottom sheet (redesign §6.12) and
/// returns the worker's choice, or null when it was dismissed.
///
///     final choice = await showImpedimentSheet(context);
Future<ImpedimentChoice?> showImpedimentSheet(BuildContext context) =>
    showModalBottomSheet<ImpedimentChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ImpedimentDialog(),
    );

/// Collects a reason (+ optional note, + the "Não consigo continuar hoje"
/// scope) for a "Sinalizar impossibilidade" report. Pure input collection —
/// it holds only local form state and returns an [ImpedimentChoice] via
/// `Navigator.pop`; the `ExecutionRepository.reportImpediment` call happens
/// back in `stop_actions.dart`, through the outbox. Shown as a modal sheet
/// by [showImpedimentSheet].
///
/// The switch is always offered, even on the last open stop: it is how the
/// worker ends the day ("Encerrar por hoje", spec §6.4) — a STOP impediment
/// there would close the batch and pull the next one.
class ImpedimentDialog extends StatefulWidget {
  const ImpedimentDialog({super.key});

  @override
  State<ImpedimentDialog> createState() => _ImpedimentDialogState();
}

class _ImpedimentDialogState extends State<ImpedimentDialog> {
  final _noteController = TextEditingController();
  String? _reason;
  bool _forRemainder = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _confirm() {
    final reason = _reason;
    if (reason == null) return;
    final note = _noteController.text.trim();
    Navigator.of(context).pop(
      ImpedimentChoice(
        scope: _forRemainder ? 'ROUTE_REMAINDER' : 'STOP',
        reason: reason,
        note: note.isEmpty ? null : note,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        // Lifts the sheet over the keyboard while the note is typed.
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.impedimentDialogTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              _reasons(),
              const SizedBox(height: 8),
              _noteField(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _forRemainder,
                onChanged: (value) => setState(() => _forRemainder = value),
                title: const Text(AppStrings.impedimentRemainderSwitch),
              ),
              const SizedBox(height: 8),
              _actions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reasons() {
    return RadioGroup<String>(
      groupValue: _reason,
      onChanged: (value) => setState(() => _reason = value),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (value, label) in impossibilityReasons)
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: value,
              title: Text(label),
            ),
        ],
      ),
    );
  }

  Widget _noteField() {
    return TextField(
      controller: _noteController,
      // Matches the backend `impediments.note` column, `String(500)`
      // (backend/app/domain/impediments/models.py) and spec §3 — a
      // longer note would 422 at the API and block the route's sync
      // queue with a visible chip.
      maxLength: 500,
      maxLines: 3,
      decoration: const InputDecoration(
        hintText: AppStrings.impedimentNoteHint,
      ),
    );
  }

  /// Expanded, because the theme's primary button asks for the full width.
  Widget _actions() {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(AppStrings.commonCancel),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: _reason == null ? null : _confirm,
            child: const Text(AppStrings.commonConfirm),
          ),
        ),
      ],
    );
  }
}
