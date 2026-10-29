import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/execution/evidence_list.dart';
import 'package:route_monitor/execution/evidence_photo_count.dart';
import 'package:route_monitor/execution/evidence_requirement.dart';
import 'package:route_monitor/execution/evidence_thumbnail.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/photo_sequence_screen.dart';
import 'package:route_monitor/l10n/floor_label.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart' show PendingOpState;
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/ui/app_theme.dart';

/// The camera button and the thumbnails of the task's photos. Only photos
/// still on the device (held until the stamp) can be removed: no
/// confirmation, a held photo is re-takeable, and it leaves the row at once.
///
///     TaskPhotos(route: route, stop: stop, executionId: executionId)
class TaskPhotos extends ConsumerWidget {
  const TaskPhotos({
    required this.route,
    required this.stop,
    required this.executionId,
    super.key,
  });

  final RouteSummary route;
  final RouteStopSummary stop;
  final String? executionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = executionId;
    final photos = id == null
        ? const <EvidenceListEntry>[]
        : _photosOf(ref, id);
    final mayAdd = id != null && _mayAddPhoto(ref, id);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _cameraButton(context, ref, mayAdd ? id : null),
        for (final photo in photos)
          _Thumbnail(
            photo,
            onRemove: () => _remove(ref, id!, photo.idempotencyKey!),
          ),
      ],
    );
  }

  /// Only once the count is known, and below the cap of an evidence task.
  bool _mayAddPhoto(WidgetRef ref, String executionId) {
    final count = ref.watch(stopPhotoCountProvider((route.id, executionId)));
    return count != null &&
        canAddEvidencePhoto(
          requiresEvidence: stop.requiresEvidence,
          photoCount: count,
        );
  }

  List<EvidenceListEntry> _photosOf(WidgetRef ref, String executionId) {
    final entries = ref
        .watch(stopEvidenceProvider((route.id, executionId)))
        .value;
    return [
      for (final entry in entries ?? const <EvidenceListEntry>[])
        if (entry.kind == 'PHOTO') entry,
    ];
  }

  /// Off without an open execution ([executionId] null): a photo needs one.
  Widget _cameraButton(
    BuildContext context,
    WidgetRef ref,
    String? executionId,
  ) {
    return IconButton.outlined(
      tooltip: AppStrings.taskAddPhotos,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      onPressed: executionId == null
          ? null
          : () => _takePhotos(context, ref, executionId),
      icon: const Icon(Icons.add_a_photo_outlined),
    );
  }

  Future<void> _takePhotos(
    BuildContext context,
    WidgetRef ref,
    String executionId,
  ) async {
    await openPhotoSequence(
      context,
      routeId: route.id,
      executionId: executionId,
      buildingName: stop.buildingName,
      floorLabel: floorDisplayLabel(stop.floorLabel),
      minimum: stop.requiresEvidence ? minEvidencePhotos : null,
    );
    _refreshPhotos(ref, executionId);
  }

  void _refreshPhotos(WidgetRef ref, String executionId) => ref
    ..invalidate(stopEvidenceProvider((route.id, executionId)))
    ..invalidate(localPhotoCountProvider(executionId));

  Future<void> _remove(WidgetRef ref, String executionId, String key) async {
    await ref.read(localWriteStoreProvider).deletePendingPhoto(key);
    _refreshPhotos(ref, executionId);
  }
}

/// A 64 dp thumbnail; one still on the device carries a 24 dp ✕ in a 48 dp
/// target at its top-right corner.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail(this.photo, {required this.onRemove});

  final EvidenceListEntry photo;
  final VoidCallback onRemove;

  /// The states `LocalWriteStore.deletePendingPhoto` accepts.
  bool get _removable =>
      photo.idempotencyKey != null &&
      photo.syncState != PendingOpState.synced &&
      photo.syncState != PendingOpState.sending;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 76,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: EvidenceThumbnail(photo, size: 64),
            ),
          ),
          if (_removable)
            Positioned(
              top: 0,
              right: 0,
              child: _RemovePhotoButton(onPressed: onRemove),
            ),
        ],
      ),
    );
  }
}

class _RemovePhotoButton extends StatelessWidget {
  const _RemovePhotoButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    return IconButton(
      tooltip: AppStrings.taskRemovePhoto,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      onPressed: onPressed,
      icon: DecoratedBox(
        decoration: BoxDecoration(
          color: p.ink,
          shape: BoxShape.circle,
          border: Border.all(color: p.white, width: 1.5),
        ),
        child: SizedBox.square(
          dimension: 24,
          child: Icon(Icons.close, size: 16, color: p.white),
        ),
      ),
    );
  }
}
