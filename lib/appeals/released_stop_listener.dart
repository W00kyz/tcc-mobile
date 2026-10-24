import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/appeals/appeal_form_screen.dart';
import 'package:route_monitor/appeals/appeal_providers.dart';
import 'package:route_monitor/appeals/appeals_screen.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/route_providers.dart' show myDayProvider;
import 'package:route_monitor/sync/stop_release.dart';
import 'package:route_monitor/sync/sync_providers.dart';

/// Listens for the stops the sync worker finds released (spec
/// 2026-10-20-alocacao-automatica §7.5). Each refreshes the appeals badge;
/// an appealable one shows "Estes pontos foram liberados — você pode
/// recorrer." with "Recorrer", which opens the pre-filled appeal — or the
/// appeals list when several stops wait for one.
///
///     Scaffold(body: ReleasedStopListener(child: body))
class ReleasedStopListener extends ConsumerWidget {
  const ReleasedStopListener({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<StopRelease?>(stopReleaseAnnouncementsProvider, (_, release) {
      if (release == null) return;
      ref.invalidate(appealEligibleProvider);
      if (!release.appealable) return;
      // One snackbar for the batch of releases a sync pass finds, not a
      // queue of identical ones.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text(AppStrings.releasedStopsSnackbar),
            action: SnackBarAction(
              label: AppStrings.releasedStopsSnackbarAction,
              onPressed: () => unawaited(_openAppeal(context, ref)),
            ),
          ),
        );
    });
    return child;
  }

  Future<void> _openAppeal(BuildContext context, WidgetRef ref) async {
    final notices = await ref
        .read(releasedStopStoreProvider)
        .appealableNotices();
    if (!context.mounted) return;
    final navigator = Navigator.of(context);
    if (notices.length != 1) {
      await navigator.push(
        MaterialPageRoute<void>(builder: (_) => const AppealsScreen()),
      );
      return;
    }
    final notice = notices.single;
    await navigator.push(
      MaterialPageRoute<bool>(
        builder: (_) => AppealFormScreen(
          routeStopId: notice.routeStopId,
          releaseReason: notice.releaseReason,
          servicePointName: _pointName(ref, notice.routeStopId),
        ),
      ),
    );
  }

  /// The point's name as the device last saw the day, when it has it.
  static String? _pointName(WidgetRef ref, String routeStopId) => ref
      .read(myDayProvider)
      .value
      ?.route
      ?.stops
      .where((stop) => stop.id == routeStopId)
      .firstOrNull
      ?.servicePointName;
}
