import 'package:flutter/material.dart';

import 'package:route_monitor/execution/room_resolution.dart';
import 'package:route_monitor/l10n/strings.dart';

/// Shows the room-disambiguation bottom sheet when the offline resolution
/// (spec §4.4 Ruling 4 / §6.5 Ruling 16) finds more than one plausible
/// PENDING stop. [candidates] are shown nearest-first, with the nearest one
/// pre-selected. `resolveRoomLocally` already sorts nearest-first, but that
/// ordering is not a documented contract here — sort defensively.
///
/// Returns the candidate the field worker confirmed, or `null` if the sheet
/// was dismissed (back gesture, tap outside, or "Cancelar") without one — a
/// `null` means the check-in is cancelled and nothing is enqueued.
Future<RoomCandidateLocal?> showRoomPicker(
  BuildContext context,
  List<RoomCandidateLocal> candidates,
) {
  final sorted = [...candidates]..sort(_byDistanceNullsLast);
  return showModalBottomSheet<RoomCandidateLocal>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _RoomPickerSheet(candidates: sorted),
  );
}

int _byDistanceNullsLast(RoomCandidateLocal a, RoomCandidateLocal b) {
  if (a.distanceM == null) return b.distanceM == null ? 0 : 1;
  if (b.distanceM == null) return -1;
  return a.distanceM!.compareTo(b.distanceM!);
}

class _RoomPickerSheet extends StatefulWidget {
  const _RoomPickerSheet({required this.candidates});

  /// Already sorted nearest-first by [showRoomPicker].
  final List<RoomCandidateLocal> candidates;

  @override
  State<_RoomPickerSheet> createState() => _RoomPickerSheetState();
}

class _RoomPickerSheetState extends State<_RoomPickerSheet> {
  // The nearest candidate (index 0, post-sort) is pre-selected — Ruling 4:
  // "mais próximo pré-selecionado".
  late RoomCandidateLocal _selected = widget.candidates.first;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              AppStrings.roomPickerPrompt,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final candidate in widget.candidates)
              _candidateTile(candidate),
            const SizedBox(height: 8),
            _actions(context),
          ],
        ),
      ),
    );
  }

  // A plain ListTile + selection icon, not RadioListTile: RadioListTile's
  // groupValue/onChanged pair is deprecated as of Flutter 3.32 in favor of a
  // RadioGroup ancestor, which is more machinery than a 2-choice list needs
  // here — a manual selected/unselected icon with onTap is simpler and
  // equally testable (tap the row to select it).
  Widget _candidateTile(RoomCandidateLocal candidate) {
    final isSelected = candidate == _selected;
    return ListTile(
      leading: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
      ),
      title: Text(candidate.servicePointName),
      subtitle: candidate.distanceM == null
          ? null
          : Text(AppStrings.meters(candidate.distanceM!.round())),
      onTap: () => setState(() => _selected = candidate),
    );
  }

  /// Expanded, because the theme's primary button asks for the full width.
  Widget _actions(BuildContext context) {
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
            onPressed: () => Navigator.of(context).pop(_selected),
            child: const Text(AppStrings.commonConfirm),
          ),
        ),
      ],
    );
  }
}
