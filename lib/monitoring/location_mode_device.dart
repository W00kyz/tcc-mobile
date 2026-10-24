import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/monitoring/location_mode.dart';

/// [PermissionPort] over `permission_handler`. Only exercisable on a device
/// (no platform channel under `flutter test`); the decisions it feeds are
/// covered by `test/monitoring/location_mode_test.dart`.
class PermissionHandlerPort implements PermissionPort {
  @override
  Future<bool> requestWhileInUse() async =>
      (await Permission.locationWhenInUse.request()).isGranted;

  // The background foreground service is Android-only (spec §7.3): any other
  // platform stays in foregroundOnly.
  @override
  Future<bool> isAlwaysGranted() async =>
      defaultTargetPlatform == TargetPlatform.android &&
      (await Permission.locationAlways.status).isGranted;

  @override
  Future<bool> requestAlways() async =>
      defaultTargetPlatform == TargetPlatform.android &&
      (await Permission.locationAlways.request()).isGranted;

  @override
  Future<void> requestNotifications() => Permission.notification.request();
}

/// [LocationModePrompts] as two plain dialogs over [context].
///
///     final prompts = DialogLocationModePrompts(context);
///     await resolveLocationMode(port, prompts: prompts, asked: store);
class DialogLocationModePrompts implements LocationModePrompts {
  DialogLocationModePrompts(this.context);

  final BuildContext context;

  @override
  Future<void> explainBackground() => _show(
    AppStrings.locationAlwaysRationale,
    AppStrings.locationPromptContinue,
  );

  @override
  Future<void> noteForegroundOnly() => _show(
    AppStrings.locationForegroundOnlyNote,
    AppStrings.locationPromptUnderstood,
  );

  Future<void> _show(String message, String action) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(action),
          ),
        ],
      ),
    );
  }
}
