import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/execution/conclude_sheet.dart';
import 'package:route_monitor/execution/evidence_photo_count.dart';
import 'package:route_monitor/execution/evidence_requirement.dart';
import 'package:route_monitor/execution/evidence_thumbnail.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/photo_sequence_screen.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/stop_actions.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/stamp_painters.dart';
import 'package:route_monitor/ui/stamp_slot.dart';

/// The thumbnails the block shows at most.
const int _blockThumbnails = 4;

/// The stop in progress, in place of "Próxima parada" (redesign §6.2): when
/// it started, its photos, "Tirar fotos" and "Concluir" — closed, with what
/// is missing under it, until an evidence stop has its photos.
///
///     InProgressBlock(route: route, stop: stop)
class InProgressBlock extends ConsumerWidget {
  const InProgressBlock({required this.route, required this.stop, super.key});

  final RouteSummary route;
  final RouteStopSummary stop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(stopProgressForProvider(stop.id)).asData?.value;
    // A `done` row means the check-out is written: the block is on its way
    // out and offers nothing more for that execution.
    final open = progress?.status == StopLocalStatus.inProgress
        ? progress
        : null;
    final executionId = open?.executionId;
    final photoCount = executionId == null
        ? null
        : ref.watch(stopPhotoCountProvider((route.id, executionId)));
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BlockHeader(stop: stop, since: open?.updatedAt),
          if (executionId != null)
            _BlockPhotos(
              routeId: route.id,
              executionId: executionId,
              requiresEvidence: stop.requiresEvidence,
              photoCount: photoCount,
            ),
          const SizedBox(height: 12),
          _actions(context, ref, executionId, photoCount),
        ],
      ),
    );
  }

  Widget _actions(
    BuildContext context,
    WidgetRef ref,
    String? executionId,
    int? photoCount,
  ) {
    final missing = stop.requiresEvidence && photoCount != null
        ? missingEvidencePhotos(photoCount)
        : 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _takePhotos(context, executionId, photoCount)),
        const SizedBox(width: 8),
        Expanded(child: _conclude(context, ref, photoCount, missing)),
      ],
    );
  }

  Widget _takePhotos(
    BuildContext context,
    String? executionId,
    int? photoCount,
  ) {
    // Capped only on a stop that requires evidence; an unknown count
    // (loading) does not lock the camera. No open execution (Ruling 17
    // cold-start gap) has nowhere to attach a photo.
    final enabled =
        executionId != null &&
        canAddEvidencePhoto(
          requiresEvidence: stop.requiresEvidence,
          photoCount: photoCount ?? 0,
        );
    return FilledButton.tonalIcon(
      key: const ValueKey('in-progress-take-photos'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      onPressed: enabled ? () => _openPhotos(context, executionId) : null,
      icon: const Icon(Icons.photo_camera_outlined),
      label: const Text(AppStrings.takePhotosButton),
    );
  }

  Widget _conclude(
    BuildContext context,
    WidgetRef ref,
    int? photoCount,
    int missing,
  ) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    final canConclude = canConcludeWithEvidence(
      requiresEvidence: stop.requiresEvidence,
      photoCount: photoCount,
    );
    return Column(
      children: [
        FilledButton(
          key: const ValueKey('in-progress-conclude'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: canConclude
              ? () => concludeStop(context, ref, route, stop)
              : null,
          child: const Text(AppStrings.routeConcludeButton),
        ),
        if (missing > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              AppStrings.missingPhotos(missing),
              style: TextStyle(fontSize: 12, color: p.muted),
            ),
          ),
      ],
    );
  }

  Future<void> _openPhotos(BuildContext context, String executionId) =>
      openPhotoSequence(
        context,
        routeId: route.id,
        executionId: executionId,
        buildingName: stop.buildingName,
        floorLabel: stop.floorLabel,
        minimum: stop.requiresEvidence ? minEvidencePhotos : null,
      );
}

/// The in-progress ring, "Em andamento · desde HH:mm" and the stop's
/// building and floor.
class _BlockHeader extends StatelessWidget {
  const _BlockHeader({required this.stop, required this.since});

  final RouteStopSummary stop;

  /// The local check-in time; null when the device holds no progress row.
  final DateTime? since;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    return Row(
      children: [
        CustomPaint(
          size: const Size.square(40),
          painter: RingPainter(kind: RingKind.inProgress, palette: p),
        ),
        const SizedBox(width: 12),
        Expanded(child: _lines(p)),
      ],
    );
  }

  Widget _lines(FieldPalette p) {
    final at = since;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          at == null
              ? AppStrings.slotInProgress
              : AppStrings.inProgressSince(stampHour(at)),
          style: TextStyle(fontSize: 12, color: p.muted),
        ),
        Text(
          AppStrings.buildingFloor(stop.buildingName, stop.floorLabel),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: p.ink,
          ),
        ),
      ],
    );
  }
}

/// The execution's photo thumbnails and its count: "n de 2 fotos
/// obrigatórias" on an evidence stop, "n fotos" otherwise.
class _BlockPhotos extends ConsumerWidget {
  const _BlockPhotos({
    required this.routeId,
    required this.executionId,
    required this.requiresEvidence,
    required this.photoCount,
  });

  final String routeId;
  final String executionId;
  final bool requiresEvidence;
  final int? photoCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    final items = ref.watch(stopEvidenceProvider((routeId, executionId))).value;
    final count = photoCount ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 52),
      child: Row(
        children: [
          for (final item in photosOf(items).take(_blockThumbnails))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: EvidenceThumbnail(item, size: 48),
              ),
            ),
          Expanded(
            child: Text(
              requiresEvidence
                  ? AppStrings.requiredPhotosProgress(count)
                  : AppStrings.photoSequenceCounter(count),
              style: TextStyle(fontSize: 14, color: p.ink),
            ),
          ),
        ],
      ),
    );
  }
}
