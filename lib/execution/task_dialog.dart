import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/execution/evidence_photo_count.dart';
import 'package:route_monitor/execution/evidence_requirement.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/impossibility_reason_dialog.dart';
import 'package:route_monitor/execution/observation_draft.dart';
import 'package:route_monitor/execution/task_photos.dart';
import 'package:route_monitor/l10n/floor_label.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/routing/floor_actions.dart';
import 'package:route_monitor/routing/home_notices.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/ui/app_theme.dart';

// One task, tapped on the floor card before it is stamped: its details, the
// observation, its photos, and the two ways out — "Concluir tarefa" (moss
// stamp) or "Sinalizar impossibilidade" (brick stamp).

/// What `impediments.note` takes (`String(500)`,
/// backend/app/domain/impediments/models.py). The observation allows 2000:
/// sent whole as a note it would 422 and block the route's sync queue.
const int _impedimentNoteLimit = 500;

/// The slot states that still hold an open task; any other tap is a no-op.
const Set<SlotState> _openSlotStates = {
  SlotState.pending,
  SlotState.next,
  SlotState.inProgress,
};

/// What the worker decided in the task dialog; null from it means "closed".
sealed class TaskDecision {
  const TaskDecision();
}

class TaskConcluded extends TaskDecision {
  const TaskConcluded(this.observation);

  final String? observation;
}

class TaskImpossible extends TaskDecision {
  const TaskImpossible({required this.reason, required this.note});

  final String reason;
  final String? note;
}

/// Opens [stop]'s task dialog when [slot] is still open, then carries out the
/// worker's decision. [context] and [ref] are the caller's (the map home),
/// not the dialog's: the write and its stamp outlive the closed dialog.
///
///     await showTaskDialog(context, ref,
///         route: route, stop: stop, slot: slot);
Future<void> showTaskDialog(
  BuildContext context,
  WidgetRef ref, {
  required RouteSummary route,
  required RouteStopSummary stop,
  required CardSlot slot,
}) async {
  if (!_openSlotStates.contains(slot.state)) return;
  final decision = await showDialog<TaskDecision>(
    context: context,
    builder: (_) => TaskDialog(route: route, stop: stop),
  );
  if (decision == null || !context.mounted) return;
  final notify = homeNotifier(ref, context);
  try {
    await _carryOut(context, ref, route, stop, decision);
  } on Exception {
    // After a landed write only the sync pass that follows can throw: the
    // outbox retries it, so it is not this task's failure.
    if (context.mounted && _writeLanded(ref, stop, decision)) return;
    // No stamp falls, and the draft (cleared only after a write) is still
    // there for the next try.
    notify(AppStrings.taskSaveFailed);
  }
}

/// Whether [decision]'s write reached SQLite: its stamp provider is set only
/// once it did (RNF06).
bool _writeLanded(WidgetRef ref, RouteStopSummary stop, TaskDecision decision) {
  final stamped = switch (decision) {
    TaskConcluded() => ref.read(lastStampedStopProvider),
    TaskImpossible() => ref.read(lastImpededStopProvider),
  };
  return stamped == stop.id;
}

/// [showTaskDialog] for a tapped floor-card [slot] of [route]. A slot whose
/// stop left the route (a reload between the build and the tap) opens
/// nothing.
///
///     onSlotTap: (slot, _) => showSlotTask(context, ref, route, slot)
Future<void> showSlotTask(
  BuildContext context,
  WidgetRef ref,
  RouteSummary route,
  CardSlot slot,
) async {
  final stop = route.stops.where((s) => s.id == slot.stopId).firstOrNull;
  if (stop == null) return;
  await showTaskDialog(context, ref, route: route, stop: stop, slot: slot);
}

Future<void> _carryOut(
  BuildContext context,
  WidgetRef ref,
  RouteSummary route,
  RouteStopSummary stop,
  TaskDecision decision,
) => switch (decision) {
  TaskConcluded(:final observation) => concludeTask(
    ref,
    route,
    stop,
    observation: observation,
  ),
  TaskImpossible(:final reason, :final note) => signalTaskImpossible(
    context,
    ref,
    route,
    stop,
    reason: reason,
    note: note,
  ),
};

/// The observation as an impediment note: trimmed, null when blank, and cut
/// to [_impedimentNoteLimit] code points (what the backend counts). The
/// reason dialog says so beforehand ([_noteWillBeTrimmed]).
String? _impedimentNoteOf(String draft) {
  final note = observationToSend(draft);
  if (note == null || !_noteWillBeTrimmed(draft)) return note;
  return String.fromCharCodes(note.runes.take(_impedimentNoteLimit)).trim();
}

bool _noteWillBeTrimmed(String draft) =>
    (observationToSend(draft)?.runes.length ?? 0) > _impedimentNoteLimit;

/// The task dialog's body. Pure input collection apart from the photos: it
/// never writes a stamp or an impediment, it pops a [TaskDecision] and
/// [showTaskDialog] writes it. The observation draft lives in memory only
/// ([observationDraftProvider]) until that write.
class TaskDialog extends ConsumerStatefulWidget {
  const TaskDialog({required this.route, required this.stop, super.key});

  final RouteSummary route;
  final RouteStopSummary stop;

  @override
  ConsumerState<TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends ConsumerState<TaskDialog> {
  late final TextEditingController _observation = TextEditingController(
    text: ref.read(observationDraftProvider(widget.stop.id)),
  );

  @override
  void dispose() {
    _observation.dispose();
    super.dispose();
  }

  /// The open execution of the task: set from the floor check-in until the
  /// stamp; null before the check-in and while the progress row loads.
  String? _openExecutionId() {
    final entry = ref.watch(stopProgressForProvider(widget.stop.id)).value;
    if (entry == null || entry.status != StopLocalStatus.inProgress) {
      return null;
    }
    return entry.executionId;
  }

  /// Whether the progress row was read: until then no hint says "faça o
  /// check-in", which would flash on a task already checked in.
  bool get _progressKnown =>
      ref.watch(stopProgressForProvider(widget.stop.id)).hasValue;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    final executionId = _openExecutionId();
    return Dialog(
      backgroundColor: p.paper,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _content(p, executionId),
            ),
            Positioned(top: 4, right: 4, child: _closeButton()),
          ],
        ),
      ),
    );
  }

  Widget _closeButton() => IconButton(
    tooltip: AppStrings.photoSequenceClose,
    onPressed: () => Navigator.of(context).pop(),
    icon: const Icon(Icons.close),
  );

  Widget _content(FieldPalette p, String? executionId) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(p),
        const SizedBox(height: 16),
        ..._details(p),
        const SizedBox(height: 16),
        _observationField(),
        const SizedBox(height: 8),
        TaskPhotos(
          route: widget.route,
          stop: widget.stop,
          executionId: executionId,
        ),
        const SizedBox(height: 24),
        ..._actions(p, executionId),
      ],
    );
  }

  /// Name and place; the right inset keeps the title clear of the close
  /// button over the corner.
  Widget _header(FieldPalette p) {
    final text = Theme.of(context).textTheme;
    final stop = widget.stop;
    return Padding(
      padding: const EdgeInsets.only(right: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(stop.servicePointName, style: text.titleLarge),
          const SizedBox(height: 4),
          Text(
            AppStrings.buildingFloor(
              stop.buildingName,
              floorDisplayLabel(stop.floorLabel),
            ),
            style: text.bodyMedium?.copyWith(color: p.muted),
          ),
        ],
      ),
    );
  }

  List<Widget> _details(FieldPalette p) {
    final serviceType = widget.stop.serviceTypeName;
    return [
      if (serviceType != null)
        _detailRow(Icons.cleaning_services_outlined, serviceType, p),
      if (widget.stop.requiresEvidence)
        _detailRow(
          Icons.photo_camera_outlined,
          AppStrings.taskRequiresPhotos,
          p,
        ),
    ];
  }

  Widget _detailRow(IconData icon, String label, FieldPalette p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: p.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Widget _observationField() {
    return TextField(
      controller: _observation,
      minLines: 3,
      maxLines: 6,
      maxLength: maxObservationLength,
      inputFormatters: const [CodePointLimiter(maxObservationLength)],
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        labelText: AppStrings.taskObservationLabel,
        alignLabelWithHint: true,
      ),
      onChanged: ref
          .read(observationDraftProvider(widget.stop.id).notifier)
          .write,
    );
  }

  List<Widget> _actions(FieldPalette p, String? executionId) {
    final mayConclude =
        executionId != null &&
        stopMayConclude(
          ref,
          widget.route.id,
          widget.stop,
          executionId,
          watch: true,
        );
    final hint = _concludeHint(executionId);
    return [
      FilledButton(
        onPressed: mayConclude ? _conclude : null,
        child: const Text(AppStrings.taskConclude),
      ),
      if (hint != null) _hintLine(hint, p),
      const SizedBox(height: 8),
      _impossibleButton(p),
    ];
  }

  /// Brick: reporting a task impossible is the alarm path (DESIGN.md).
  Widget _impossibleButton(FieldPalette p) => TextButton(
    style: TextButton.styleFrom(
      foregroundColor: p.brick,
      minimumSize: const Size.fromHeight(48),
    ),
    onPressed: _signalImpossible,
    child: const Text(AppStrings.routeSignalImpossibilityButton),
  );

  /// Why "Concluir tarefa" is closed, or null when it is open.
  String? _concludeHint(String? executionId) {
    if (!_progressKnown) return null;
    if (executionId == null) return AppStrings.taskNeedsFloorCheckIn;
    if (!widget.stop.requiresEvidence) return null;
    final count = ref.watch(
      stopPhotoCountProvider((widget.route.id, executionId)),
    );
    final missing = missingEvidencePhotos(count ?? 0);
    return missing == 0 ? null : AppStrings.missingPhotos(missing);
  }

  Widget _hintLine(String hint, FieldPalette p) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        hint,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.muted),
      ),
    );
  }

  void _conclude() => Navigator.of(context).pop(
    TaskConcluded(observationToSend(_observation.text)),
  );

  /// The reason dialog over this one; a cancel there leaves the task open.
  Future<void> _signalImpossible() async {
    final reason = await showImpossibilityReasonDialog(
      context,
      noteTrimmed: _noteWillBeTrimmed(_observation.text),
    );
    if (reason == null || !mounted) return;
    Navigator.of(context).pop(
      TaskImpossible(
        reason: reason,
        note: _impedimentNoteOf(_observation.text),
      ),
    );
  }
}
