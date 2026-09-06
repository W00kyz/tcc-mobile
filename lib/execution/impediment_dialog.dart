import 'package:flutter/material.dart';

/// The reason options offered by [ImpedimentDialog]. The first element of each
/// pair is the backend wire value (see
/// `backend/app/domain/impediments/models.py::ImpedimentReason`) — it is what
/// gets sent as `reason`; the second is the pt-BR label shown to the field
/// worker (no i18n mechanism exists in this app yet — tech debt M-1).
const _reasonOptions = <(String, String)>[
  ('ACCESS_BLOCKED', 'Acesso bloqueado'),
  ('SITE_REFUSAL', 'Recusa do local'),
  ('HEALTH_ISSUE', 'Problema de saúde'),
  ('OTHER', 'Outro'),
];

/// The outcome of [ImpedimentDialog]: the reason wire value, the derived
/// `scope`, and an optional free-text note. `null` from the dialog means the
/// field worker cancelled — nothing should be reported.
class ImpedimentChoice {
  const ImpedimentChoice({
    required this.scope,
    required this.reason,
    this.note,
  });

  /// `STOP` for just the current stop, `ROUTE_REMAINDER` when the field worker
  /// also flipped the "resto da rota" switch.
  final String scope;

  /// A wire value from [_reasonOptions] — `ACCESS_BLOCKED`, `SITE_REFUSAL`,
  /// `HEALTH_ISSUE` or `OTHER`.
  final String reason;

  /// The trimmed note, or `null` when the field left it blank.
  final String? note;
}

/// Collects a reason (+ optional note, + optional "resto da rota" scope) for a
/// "Sinalizar impossibilidade" report. Pure input collection — it holds only
/// local form state and returns an [ImpedimentChoice] via `Navigator.pop`; the
/// `ExecutionRepository.reportImpediment` call happens back in `route_screen`.
class ImpedimentDialog extends StatefulWidget {
  const ImpedimentDialog({required this.showRemainderSwitch, super.key});

  /// Whether to offer the "Sinalizar para o resto da rota também" switch —
  /// `route_screen` sets this only when more than one `PENDING` stop remains.
  final bool showRemainderSwitch;

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
    return AlertDialog(
      title: const Text('Sinalizar impossibilidade'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (value) => setState(() => _reason = value),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (value, label) in _reasonOptions)
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: value,
                      title: Text(label),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              maxLength: 2000,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Observação (opcional)',
              ),
            ),
            if (widget.showRemainderSwitch)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _forRemainder,
                onChanged: (value) => setState(() => _forRemainder = value),
                title: const Text('Sinalizar para o resto da rota também'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _reason == null ? null : _confirm,
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
