import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/appeals/appeal_form_screen.dart';
import 'package:route_monitor/appeals/appeal_providers.dart';
import 'package:route_monitor/appeals/appeals_screen.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/route_providers.dart' show myDayProvider;
import 'package:route_monitor/routing/route_repository.dart' show MyDay;
import 'package:route_monitor/sync/stop_release.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/ui/snackbar_lane.dart';

/// Listens for the stops the sync worker finds released (spec
/// 2026-10-20-alocacao-automatica §7.5). Each refreshes the appeals badge;
/// an appealable one shows "Estes pontos foram liberados — você pode
/// recorrer." with "Recorrer", which opens the pre-filled appeal — or the
/// appeals list when several stops wait for one. A reload of the day also
/// refreshes the badge: the server may have released points meanwhile.
///
///     Scaffold(body: ReleasedStopListener(child: body))
class ReleasedStopListener extends ConsumerWidget {
  const ReleasedStopListener({
    required this.lane,
    required this.child,
    super.key,
  });

  /// The home's snackbar line: the offer floats above the map sheet.
  final SnackbarLane lane;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref
      ..listen<AsyncValue<MyDay>>(myDayProvider, (previous, next) {
        // A reload settling — not one still in flight (refreshing data
        // reads as AsyncData too), nor the first load: the badge fetched
        // its own lists when it was built.
        final reloaded = previous?.hasValue == true && !next.isLoading;
        if (reloaded && next.hasValue) _refresh(ref);
      })
      ..listen<StopRelease?>(stopReleaseAnnouncementsProvider, (_, release) {
        if (release == null) return;
        _refresh(ref);
        if (release.appealable) _offerAppeal(context, ref);
      });
    return child;
  }

  static void _refresh(WidgetRef ref) => ref
    ..invalidate(appealEligibleProvider)
    ..invalidate(localReleasedNoticesProvider);

  void _offerAppeal(BuildContext context, WidgetRef ref) {
    // One snackbar for the batch of releases a sync pass finds, not a
    // queue of identical ones: the lane keeps only the newest.
    lane.show(
      SnackKind.appeal,
      (margin) => SnackBar(
        content: const Text(AppStrings.releasedStopsSnackbar),
        margin: margin,
        action: SnackBarAction(
          label: AppStrings.releasedStopsSnackbarAction,
          onPressed: () => unawaited(_openAppeal(context, ref)),
        ),
      ),
    );
  }

  Future<void> _openAppeal(BuildContext context, WidgetRef ref) async {
    final notices = [
      for (final notice
          in await ref.read(releasedStopStoreProvider).allNotices())
        if (notice.appealable) notice,
    ];
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
