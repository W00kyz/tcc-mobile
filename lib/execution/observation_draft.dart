import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show NotifierProviderFamily;

// One task's observation while the worker types it: the draft, the trimmed
// value a write sends, and the field's code-point limit. Moved out of the
// old conclusion sheet; the task dialog reuses all three.

/// What the backend takes in `complaints_suggestions` (and what the old
/// note dialog allowed).
const int maxObservationLength = 2000;

/// Truncates the text to [maxCodePoints] Unicode code points.
///
/// The field's own `maxLength` counts grapheme clusters, but the backend
/// (pydantic) counts code points: a family emoji is one cluster and seven code
/// points, so emoji-heavy text could pass the field and be refused with a 422
/// that blocks the queued check-out.
///
///     inputFormatters: const [CodePointLimiter(maxObservationLength)]
class CodePointLimiter extends TextInputFormatter {
  const CodePointLimiter(this.maxCodePoints);

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

/// The observation typed for one stop, kept outside the dialog so closing
/// and reopening it shows it again (Review Focus 3). Memory only, on
/// purpose: nothing about it is a user action until the stamp, which is what
/// writes it to SQLite (RNF06).
///
///     ref.read(observationDraftProvider(stopId).notifier).write('pia');
final NotifierProviderFamily<ObservationDraft, String, String>
observationDraftProvider =
    NotifierProvider.family<ObservationDraft, String, String>(
      ObservationDraft.new,
    );

class ObservationDraft extends Notifier<String> {
  ObservationDraft(this.routeStopId);

  final String routeStopId;

  @override
  String build() => '';

  // A method, not a setter: reads as the action it is at the call site.
  // ignore: use_setters_to_change_properties
  void write(String text) => state = text;

  void clear() => state = '';
}

/// The draft as a write sends it: trimmed, or null when blank so the
/// payload carries no `complaints_suggestions` key at all.
///
///     observationToSend('  pia  '); // 'pia'
String? observationToSend(String draft) {
  final trimmed = draft.trim();
  return trimmed.isEmpty ? null : trimmed;
}
