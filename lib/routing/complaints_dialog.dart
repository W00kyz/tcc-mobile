import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:route_monitor/l10n/strings.dart';

/// Longest complaints/suggestions text the backend accepts.
const int _maxComplaintsLength = 2000;

/// Truncates the text to [maxCodePoints] Unicode code points.
///
/// The field's own `maxLength` counts grapheme clusters, but the backend
/// (pydantic) counts code points: a family emoji is one cluster and seven code
/// points, so emoji-heavy text could pass the field and be refused with a 422
/// that blocks the queued check-out.
class _CodePointLimiter extends TextInputFormatter {
  const _CodePointLimiter(this.maxCodePoints);

  final int maxCodePoints;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.runes.length <= maxCodePoints) return newValue;
    final kept = String.fromCharCodes(newValue.text.runes.take(maxCodePoints));
    return TextEditingValue(
      text: kept,
      selection: TextSelection.collapsed(offset: kept.length),
    );
  }
}

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
        inputFormatters: const [_CodePointLimiter(_maxComplaintsLength)],
        // Counts code points too, so the counter matches what is enforced.
        buildCounter:
            (
              context, {
              required currentLength,
              required isFocused,
              required maxLength,
            }) => Text('${_controller.text.runes.length}/$maxLength'),
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
