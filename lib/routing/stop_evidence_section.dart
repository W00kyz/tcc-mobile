import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/execution/evidence_list.dart';
import 'package:route_monitor/execution/evidence_photo_count.dart';
import 'package:route_monitor/execution/evidence_requirement.dart';
import 'package:route_monitor/execution/evidence_thumbnail.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart' show PendingOpState;
import 'package:route_monitor/local/stop_progress_store.dart'
    show StopLocalStatus;
import 'package:route_monitor/routing/evidence_requirement_hint.dart';
import 'package:route_monitor/ui/app_theme.dart';

// An IN_PROGRESS stop's evidence buttons and list, moved unchanged out of
// the old `route_screen.dart`. Tasks 8 and 9 replace it with the photo
// sequence and the in-progress block.

/// Resolves [routeStopId]'s open `execution_id` (Ruling 17) and, only when
/// found, shows the evidence buttons + list for it. A `null` result — no
/// `OpenExecutions` row, the accepted cold-start gap for a stop that turned
/// `IN_PROGRESS` before that table existed — hides the whole section rather
/// than showing a broken action.
///
///     StopEvidenceSection(routeId: r, routeStopId: s, requiresEvidence: e)
class StopEvidenceSection extends ConsumerWidget {
  const StopEvidenceSection({
    required this.routeId,
    required this.routeStopId,
    required this.requiresEvidence,
    super.key,
  });

  final String routeId;
  final String routeStopId;
  final bool requiresEvidence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressAsync = ref.watch(stopProgressForProvider(routeStopId));
    return progressAsync.when(
      // A `done` stop no longer offers evidence-add buttons (Etapa 5 §6.3):
      // only an `inProgress` entry opens the section.
      data: (entry) =>
          entry == null || entry.status != StopLocalStatus.inProgress
          ? const SizedBox.shrink()
          : _EvidenceSection(
              routeId: routeId,
              executionId: entry.executionId,
              requiresEvidence: requiresEvidence,
            ),
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

/// The "Adicionar foto"/"Adicionar observação" buttons and the evidence list
/// for one stop's open execution.
class _EvidenceSection extends ConsumerWidget {
  const _EvidenceSection({
    required this.routeId,
    required this.executionId,
    required this.requiresEvidence,
  });

  final String routeId;
  final String executionId;
  final bool requiresEvidence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (routeId, executionId);
    final itemsAsync = ref.watch(stopEvidenceProvider(query));
    final photoCount = ref.watch(stopPhotoCountProvider(query));

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buttons(context, ref, query, photoCount),
          if (requiresEvidence && photoCount != null)
            EvidenceRequirementHint(missing: missingEvidencePhotos(photoCount)),
          itemsAsync.when(
            data: (items) =>
                items.isEmpty ? const SizedBox.shrink() : _EvidenceList(items),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (_, _) => const Text(AppStrings.routeEvidenceLoadError),
          ),
        ],
      ),
    );
  }

  Widget _buttons(
    BuildContext context,
    WidgetRef ref,
    (String, String) query,
    int? photoCount,
  ) {
    return Wrap(
      spacing: 8,
      children: [
        TextButton.icon(
          // Capped only on a stop that requires evidence; an unknown
          // count (loading) does not lock the camera.
          onPressed:
              canAddEvidencePhoto(
                requiresEvidence: requiresEvidence,
                photoCount: photoCount ?? 0,
              )
              ? () => _addPhoto(context, ref, query)
              : null,
          icon: const Icon(Icons.add_a_photo),
          label: const Text(AppStrings.routeAddPhotoButton),
        ),
        TextButton.icon(
          onPressed: () => _addNote(context, ref, query),
          icon: const Icon(Icons.note_add),
          label: const Text(AppStrings.routeAddNoteButton),
        ),
      ],
    );
  }

  Future<void> _addPhoto(
    BuildContext context,
    WidgetRef ref,
    (String, String) query,
  ) async {
    try {
      final photo = await ref.read(evidenceCaptureProvider).takePhoto();
      if (photo == null) return; // The field worker cancelled the camera.
      await ref
          .read(executionRepositoryProvider)
          .addPhoto(routeId: query.$1, executionId: query.$2, photo: photo);
      ref
        ..invalidate(stopEvidenceProvider(query))
        ..invalidate(localPhotoCountProvider(query.$2));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(content: Text(AppStrings.routePhotoAdded)),
        );
      }
      // Deliberately broad: a compression failure (StateError), a network
      // failure (DioException) or any other capture/upload error all map to
      // the same generic message here, same discipline as check-in/out.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.routePhotoAddError)),
        );
      }
    }
  }

  Future<void> _addNote(
    BuildContext context,
    WidgetRef ref,
    (String, String) query,
  ) async {
    final text = await _showNoteDialog(context);
    if (text == null || text.isEmpty || !context.mounted) return;

    try {
      await ref
          .read(executionRepositoryProvider)
          .addNote(routeId: query.$1, executionId: query.$2, text: text);
      ref.invalidate(stopEvidenceProvider(query));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.routeNoteAdded)),
        );
      }
      // Deliberately broad: same rationale as _addPhoto above.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.routeNoteAddError)),
        );
      }
    }
  }
}

/// A `showDialog` + single `TextField` — simplest idiomatic Flutter shape
/// for a short free-text prompt, no need for the dashboard's React-modal
/// pattern here. Returns the trimmed text, or null if cancelled/dismissed.
Future<String?> _showNoteDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text(AppStrings.formAddNoteDialogTitle),
      content: TextField(
        controller: controller,
        maxLength: 2000,
        maxLines: 4,
        autofocus: true,
        decoration: const InputDecoration(hintText: AppStrings.routeNoteHint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text(AppStrings.commonCancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text(AppStrings.commonSave),
        ),
      ],
    ),
  );
}

class _EvidenceList extends StatelessWidget {
  const _EvidenceList(this.items);

  final List<EvidenceListEntry> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final item in items) _EvidenceTile(item)],
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile(this.item);

  final EvidenceListEntry item;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EvidenceThumbnail(item),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.kind == 'NOTE'
                  ? (item.textBody ?? '')
                  : AppStrings.routeEvidencePhotoLabel,
            ),
          ),
          const SizedBox(width: 8),
          _syncIcon(p),
        ],
      ),
    );
  }

  /// Each state by its own icon; colour (tokens only) just reinforces it.
  Widget _syncIcon(FieldPalette p) {
    switch (item.syncState) {
      case PendingOpState.synced:
        return Icon(Icons.cloud_done, size: 16, color: p.moss);
      case PendingOpState.pending:
        return Icon(Icons.cloud_upload, size: 16, color: p.muted);
      case PendingOpState.failed:
        return Icon(Icons.error, size: 16, color: p.brick);
      case PendingOpState.blocked:
        // Retry budget exhausted (Etapa 6 Ruling 6): needs manual action,
        // not just another automatic attempt.
        return Icon(Icons.block, size: 16, color: p.brick);
    }
  }
}
