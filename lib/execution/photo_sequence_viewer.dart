import 'package:flutter/material.dart';

import 'package:route_monitor/execution/photo_sequence_widgets.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/ui/app_theme.dart';

/// Shows [shot] large with where its upload stands ([status]). Returns true
/// when the worker chose "Apagar", offered only when [deletable]; a photo
/// already sent shows the cloud icon instead.
Future<bool> showShotViewer(
  BuildContext context, {
  required SessionShot shot,
  required ShotStatus status,
  required bool deletable,
}) async {
  final deleted = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _ShotViewer(shot: shot, status: status, deletable: deletable),
  );
  return deleted ?? false;
}

class _ShotViewer extends StatelessWidget {
  const _ShotViewer({
    required this.shot,
    required this.status,
    required this.deletable,
  });

  final SessionShot shot;
  final ShotStatus status;
  final bool deletable;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>()!;
    return Dialog(
      backgroundColor: kCameraChrome,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.memory(shot.bytes, fit: BoxFit.contain),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                _statusNote(p),
                if (deletable) _deleteButton(context, p),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deleteButton(BuildContext context, FieldPalette p) {
    return TextButton(
      key: const Key('photo-delete'),
      style: TextButton.styleFrom(
        minimumSize: const Size(96, 48),
        foregroundColor: p.white,
      ),
      onPressed: () => Navigator.of(context).pop(true),
      child: const Text(AppStrings.photoSequenceDelete),
    );
  }

  /// "Foto já enviada" only for a delivered shot (final review I-1): a
  /// pending, failed or uploading one says it is not sent yet, a blocked one
  /// says it could not be sent.
  Widget _statusNote(FieldPalette p) {
    final (icon, color, text) = _noteParts(p);
    return SizedBox(
      height: 48,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(color: kCameraSoftText)),
        ],
      ),
    );
  }

  (IconData, Color, String) _noteParts(FieldPalette p) => switch (status) {
    ShotStatus.delivered => (
      Icons.cloud_done,
      p.white,
      AppStrings.photoSequenceSynced,
    ),
    ShotStatus.notSent => (
      Icons.cloud_upload,
      p.white,
      AppStrings.photoSequenceNotSent,
    ),
    ShotStatus.blocked => (
      Icons.cloud_off,
      p.brick,
      AppStrings.photoSequenceBlocked,
    ),
  };
}
