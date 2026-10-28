import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/blocked_sync_screen.dart';
import 'package:route_monitor/routing/day_state_panels.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/ui/app_theme.dart';

/// Opens the sync detail: pending, blocked and "Enviar agora".
///
///     showSyncDetailSheet(context, route.id)
Future<void> showSyncDetailSheet(BuildContext context, String routeId) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => SyncDetailSheet(routeId: routeId),
  );
}

class SyncDetailSheet extends ConsumerWidget {
  const SyncDetailSheet({required this.routeId, super.key});

  final String routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    final status = ref.watch(routeSyncStatusProvider(routeId)).asData?.value;
    final pending = status?.pending ?? 0;
    final blocked = status?.blocked ?? 0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppStrings.syncDetailTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.syncDetailPending(pending),
              style: TextStyle(color: p.muted),
            ),
            if (blocked > 0)
              Text(
                AppStrings.syncDetailBlocked(blocked),
                style: TextStyle(color: p.brick),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _sendNow(context, ref),
              child: const Text(AppStrings.syncSendNow),
            ),
            if (blocked > 0) _seeBlocked(context),
          ],
        ),
      ),
    );
  }

  Widget _seeBlocked(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      onPressed: () => _openBlocked(context),
      child: const Text(AppStrings.syncSeeBlocked),
    ),
  );

  void _sendNow(BuildContext context, WidgetRef ref) {
    // Started before the pop: the sheet's ref dies with it.
    unawaited(sendAllAndPull(ref));
    Navigator.of(context).pop();
  }

  void _openBlocked(BuildContext context) {
    final navigator = Navigator.of(context)..pop();
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => BlockedSyncScreen(routeId: routeId),
        ),
      ),
    );
  }
}
