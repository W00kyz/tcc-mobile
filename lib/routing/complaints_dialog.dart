import 'package:flutter/material.dart';

import 'package:route_monitor/l10n/strings.dart';

/// Longest complaints/suggestions text the backend accepts.
const int _maxComplaintsLength = 2000;

/// What the worker confirmed in [showComplaintsDialog]. [text] is `null` when
/// the field was left blank: the check-out then carries no
/// `complaints_suggestions` at all.
class ComplaintsDialogResult {
  const ComplaintsDialogResult({this.text});

  final String? text;
}

/// Asks for optional complaints and suggestions before a check-out on a stop
/// that requires evidence. Resolves to `null` on "Cancelar" (the check-out is
/// abandoned) and to a [ComplaintsDialogResult] on "Continuar".
///
/// ```dart
/// final result = await showComplaintsDialog(context);
/// if (result == null) return; // cancelled
/// ```
Future<ComplaintsDialogResult?> showComplaintsDialog(BuildContext context) =>
    showDialog<ComplaintsDialogResult>(
      context: context,
      builder: (_) => const _ComplaintsDialog(),
    );

class _ComplaintsDialog extends StatefulWidget {
  const _ComplaintsDialog();

  @override
  State<_ComplaintsDialog> createState() => _ComplaintsDialogState();
}

class _ComplaintsDialogState extends State<_ComplaintsDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final text = _controller.text.trim();
    Navigator.of(
      context,
    ).pop(ComplaintsDialogResult(text: text.isEmpty ? null : text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.complaintsDialogTitle),
      content: TextField(
        controller: _controller,
        maxLength: _maxComplaintsLength,
        maxLines: 5,
        minLines: 3,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.commonCancel),
        ),
        FilledButton(
          onPressed: _confirm,
          child: const Text(AppStrings.complaintsContinue),
        ),
      ],
    );
  }
}
