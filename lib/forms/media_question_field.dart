import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/execution/evidence_list.dart';
import 'package:route_monitor/execution/evidence_thumbnail.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/forms/media_photo_taker.dart';
import 'package:route_monitor/l10n/strings.dart';

/// The backend accepts at most this many photos per MEDIA answer
/// (`MAX_MEDIA_PHOTOS`, backend app/domain/execution/answers.py).
const maxMediaPhotos = 10;

/// A MEDIA question: the photos taken for it (thumbnails, each removable)
/// and the button that takes another. The answer is the list of the photos'
/// keys; [onChanged] receives the new list.
///
/// ```dart
/// MediaQuestionField(routeId: r, executionId: e, label: 'Foto do piso',
///   photoKeys: keys, onChanged: save)
/// ```
class MediaQuestionField extends ConsumerWidget {
  const MediaQuestionField({
    required this.routeId,
    required this.executionId,
    required this.label,
    required this.photoKeys,
    required this.onChanged,
    super.key,
  });

  final String routeId;
  final String executionId;
  final String label;
  final List<String> photoKeys;
  final ValueChanged<List<String>> onChanged;

  Future<void> _takePhoto(BuildContext context, WidgetRef ref) async {
    try {
      final key = await ref
          .read(mediaPhotoTakerProvider)
          .take(routeId: routeId, executionId: executionId);
      if (key == null) return; // The field worker cancelled the camera.
      onChanged([...photoKeys, key]);
      ref.invalidate(stopEvidenceProvider((routeId, executionId)));
      // Deliberately broad, same as the route screen's own "Adicionar foto":
      // a compression or storage failure all map to one message.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.routePhotoAddError)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final evidence = ref.watch(stopEvidenceProvider((routeId, executionId)));
    final byKey = {
      for (final entry in evidence.value ?? const <EvidenceListEntry>[])
        if (entry.idempotencyKey != null) entry.idempotencyKey!: entry,
    };
    final atLimit = photoKeys.length >= maxMediaPhotos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final key in photoKeys)
              _PhotoTile(
                entry: byKey[key],
                onRemove: () => onChanged([
                  for (final other in photoKeys)
                    if (other != key) other,
                ]),
              ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: atLimit ? null : () => _takePhoto(context, ref),
          icon: const Icon(Icons.add_a_photo),
          label: const Text(AppStrings.formMediaTakePhoto),
        ),
        if (atLimit)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(AppStrings.formMediaLimit),
          ),
      ],
    );
  }
}

/// One photo of the answer. [entry] is null while the stop's evidence list
/// is loading: a placeholder keeps the photo (and its remove button) on
/// screen.
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.entry, required this.onRemove});

  final EvidenceListEntry? entry;
  final VoidCallback onRemove;

  static const double _size = 72;

  @override
  Widget build(BuildContext context) {
    final photo = entry;
    return Stack(
      children: [
        if (photo == null)
          const SizedBox.square(
            dimension: _size,
            child: Icon(Icons.photo, size: 32),
          )
        else
          EvidenceThumbnail(photo, size: _size),
        Positioned(
          top: 0,
          right: 0,
          child: IconButton.filledTonal(
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            tooltip: AppStrings.formMediaRemove,
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
        ),
      ],
    );
  }
}
