import 'package:flutter/material.dart';

import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/ui/app_theme.dart';

/// The reasons a task can be reported impossible. The first element of each
/// pair is the backend wire value (see
/// `backend/app/domain/impediments/models.py::ImpedimentReason`) — it is what
/// gets sent as `reason`; the second is the pt-BR label shown to the field
/// worker (from [AppStrings], RNF02).
const impossibilityReasons = <(String, String)>[
  ('ACCESS_BLOCKED', AppStrings.impedimentReasonAccessBlocked),
  ('SITE_REFUSAL', AppStrings.impedimentReasonSiteRefusal),
  ('HEALTH_ISSUE', AppStrings.impedimentReasonHealthIssue),
  ('OTHER', AppStrings.impedimentReasonOther),
];

/// Asks why a task cannot be done and returns the picked reason's wire value,
/// or null when the worker cancelled — nothing should be reported then. A
/// dialog, not a sheet: it sits over the task dialog that opened it.
/// [noteTrimmed] warns that the observation goes out cut to the note limit.
///
///     final reason = await showImpossibilityReasonDialog(context);
Future<String?> showImpossibilityReasonDialog(
  BuildContext context, {
  bool noteTrimmed = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => ImpossibilityReasonDialog(noteTrimmed: noteTrimmed),
);

class ImpossibilityReasonDialog extends StatefulWidget {
  const ImpossibilityReasonDialog({this.noteTrimmed = false, super.key});

  final bool noteTrimmed;

  @override
  State<ImpossibilityReasonDialog> createState() =>
      _ImpossibilityReasonDialogState();
}

class _ImpossibilityReasonDialogState extends State<ImpossibilityReasonDialog> {
  String? _reason;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    return AlertDialog(
      backgroundColor: p.paper,
      title: const Text(AppStrings.impossibilityReasonTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_reasons(), if (widget.noteTrimmed) _trimmedLine(p)],
        ),
      ),
      actions: _actions(),
    );
  }

  List<Widget> _actions() => [
    TextButton(
      style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
      onPressed: () => Navigator.of(context).pop(),
      child: const Text(AppStrings.commonCancel),
    ),
    FilledButton(
      // The theme's primary button is full width; in the actions bar it
      // keeps its 56 dp pill but sizes to its label.
      style: FilledButton.styleFrom(minimumSize: const Size(96, 56)),
      onPressed: _reason == null
          ? null
          : () => Navigator.of(context).pop(_reason),
      child: const Text(AppStrings.commonConfirm),
    ),
  ];

  Widget _trimmedLine(FieldPalette p) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      AppStrings.impossibilityNoteTrimmed,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.muted),
    ),
  );

  Widget _reasons() {
    return RadioGroup<String>(
      groupValue: _reason,
      onChanged: (value) => setState(() => _reason = value),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
}
