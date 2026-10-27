import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/appeals/appeal_form_screen.dart';
import 'package:route_monitor/appeals/appeal_providers.dart';
import 'package:route_monitor/l10n/strings.dart';

/// One released stop this device still holds data for (spec
/// 2026-10-20-alocacao-automatica §7.5), with the two ways out: "Recorrer"
/// while the worker may still appeal, and "Descartar" always — so a release
/// refused, expired or simply not appealed never strands its data. Neither
/// needs today's route: the stop id and the notice are all they use.
///
///     ReleasedStopEntry(routeStopId: id, title: name,
///         releaseReason: notice.releaseReason, canAppeal: true)
class ReleasedStopEntry extends ConsumerWidget {
  const ReleasedStopEntry({
    required this.routeStopId,
    required this.title,
    required this.releaseReason,
    required this.canAppeal,
    this.servicePointName,
    super.key,
  });

  final String routeStopId;
  final String title;

  /// The server's `release_reason`; null when the device has no notice.
  final String? releaseReason;

  /// Whether to offer "Recorrer" (it also needs [releaseReason]).
  final bool canAppeal;

  /// Forwarded to the appeal form when known.
  final String? servicePointName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reason = releaseReason;
    final appealReason = canAppeal ? reason : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ListTile(
          title: Text(title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (reason != null)
                Text(
                  AppStrings.releasedStopReason(
                    AppStrings.releaseReasonLabel(reason),
                  ),
                ),
              if (appealReason == null)
                const Text(AppStrings.releasedStopNotAppealable),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            if (appealReason != null)
              TextButton(
                onPressed: () => _appeal(context, appealReason),
                child: const Text(AppStrings.releasedStopAppealButton),
              ),
            TextButton(
              onPressed: () => _discard(context, ref),
              child: const Text(AppStrings.releasedStopDiscardButton),
            ),
          ],
        ),
      ],
    );
  }

  /// The appeal form clears the stop itself once the appeal is on record.
  Future<void> _appeal(BuildContext context, String reason) =>
      Navigator.of(context).push(
        MaterialPageRoute<bool>(
          builder: (_) => AppealFormScreen(
            routeStopId: routeStopId,
            releaseReason: reason,
            servicePointName: servicePointName,
          ),
        ),
      );

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.releasedStopDiscardTitle),
        content: const Text(AppStrings.releasedStopDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStrings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(AppStrings.releasedStopDiscardButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await discardReleasedStop(ref, routeStopId);
    messenger.showSnackBar(
      const SnackBar(content: Text(AppStrings.releasedStopDiscarded)),
    );
  }
}
