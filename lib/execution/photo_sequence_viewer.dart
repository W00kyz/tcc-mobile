import 'package:flutter/material.dart';

import 'package:route_monitor/execution/photo_sequence_widgets.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/ui/app_theme.dart';

/// Shows [shot] large. Returns true when the worker chose "Apagar"; a photo
/// already sent ([deletable] false) shows the cloud icon instead.
Future<bool> showShotViewer(
  BuildContext context, {
  required SessionShot shot,
  required bool deletable,
}) async {
  final deleted = await showDialog<bool>(
    context: context,
    builder: (_) => _ShotViewer(shot: shot, deletable: deletable),
  );
  return deleted ?? false;
}

class _ShotViewer extends StatelessWidget {
  const _ShotViewer({required this.shot, required this.deletable});

  final SessionShot shot;
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
            child: deletable ? _deleteButton(context, p) : _syncedNote(p),
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

  Widget _syncedNote(FieldPalette p) {
    return SizedBox(
      height: 48,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_done, color: p.white),
          const SizedBox(width: 8),
          const Text(
            AppStrings.photoSequenceSynced,
            style: TextStyle(color: kCameraSoftText),
          ),
        ],
      ),
    );
  }
}
