import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/appeals/appeal_api.dart';
import 'package:route_monitor/appeals/appeal_form_screen.dart';
import 'package:route_monitor/appeals/appeal_providers.dart';
import 'package:route_monitor/appeals/day_time.dart';
import 'package:route_monitor/appeals/released_stop_entry.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/released_stop_store.dart';
import 'package:route_monitor/ui/empty_state.dart';

/// `/recursos` (spec 2026-10-20-alocacao-automatica §7.5, §9), reachable
/// whatever the route's state:
/// - the released stops this device still holds data for (past days'
///   included), each with "Recorrer" while it may still be appealed and
///   "Descartar" always — the way out of a paused or closed day, where the
///   blocked-sync screen is not reachable;
/// - the other released points the worker can still contest, each opening
///   its appeal form;
/// - the appeals already sent, with their decisions.
///
/// Pull to refresh.
class AppealsScreen extends ConsumerWidget {
  const AppealsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eligible = ref.watch(appealEligibleProvider);
    final mine = ref.watch(myAppealsProvider);
    final local =
        ref.watch(localReleasedNoticesProvider).asData?.value ?? const [];
    final isEmpty =
        local.isEmpty &&
        (eligible.asData?.value.isEmpty ?? false) &&
        (mine.asData?.value.isEmpty ?? false);
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.appealsAppBarTitle)),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: isEmpty
            ? const EmptyState(
                title: AppStrings.appealsEmptyTitle,
                body: AppStrings.appealsEmptyBody,
              )
            : _lists(local, eligible, mine),
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(appealEligibleProvider)
      ..invalidate(localReleasedNoticesProvider)
      ..invalidate(myAppealsProvider);
    await ref.read(appealEligibleProvider.future);
  }

  Widget _lists(
    List<ReleasedStopNotice> local,
    AsyncValue<List<AppealableStop>> eligible,
    AsyncValue<List<FiledAppeal>> mine,
  ) {
    final localStops = {for (final notice in local) notice.routeStopId};
    return ListView(
      children: [
        if (local.isNotEmpty) ...[
          const _SectionTitle(AppStrings.appealsLocalTitle),
          for (final notice in local)
            _LocalReleasedStop(notice: notice, eligible: eligible),
        ],
        const _SectionTitle(AppStrings.appealsEligibleTitle),
        ..._section(
          eligible.whenData(
            (stops) => stops
                .where((stop) => !localStops.contains(stop.routeStopId))
                .toList(),
          ),
          // With device entries above, an empty rest says nothing.
          empty: local.isEmpty ? AppStrings.appealsEligibleEmpty : null,
          tile: _EligibleStopTile.new,
        ),
        const _SectionTitle(AppStrings.appealsMineTitle),
        ..._section(
          mine,
          empty: AppStrings.appealsMineEmpty,
          tile: _FiledAppealTile.new,
        ),
      ],
    );
  }

  /// One list's rows: a spinner, the load error, the empty line (none when
  /// [empty] is null), or a tile per item.
  static List<Widget> _section<T>(
    AsyncValue<List<T>> items, {
    required String? empty,
    required Widget Function(T item) tile,
  }) => items.when(
    loading: () => const [
      Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
    ],
    error: (_, _) => const [_Note(AppStrings.appealsLoadError)],
    data: (list) => list.isNotEmpty
        ? list.map(tile).toList()
        : [if (empty != null) _Note(empty)],
  );
}

/// A device notice as a [ReleasedStopEntry]. "Recorrer" needs the notice
/// to be appealable and — once the server's list is in — the stop to be on
/// it: off it, the window closed (or the appeal is already on record).
/// Offline the server cannot say, so the notice decides.
class _LocalReleasedStop extends StatelessWidget {
  const _LocalReleasedStop({required this.notice, required this.eligible});

  final ReleasedStopNotice notice;
  final AsyncValue<List<AppealableStop>> eligible;

  @override
  Widget build(BuildContext context) {
    final stop = notice.routeStopId;
    final serverStops = eligible.asData?.value;
    final onServerList = serverStops
        ?.where((eligibleStop) => eligibleStop.routeStopId == stop)
        .firstOrNull;
    final stillOpen = serverStops == null || onServerList != null;
    final name = onServerList?.servicePointName;
    return ReleasedStopEntry(
      routeStopId: stop,
      title: name ?? AppStrings.releasedStopTitle(stop),
      releaseReason: notice.releaseReason,
      canAppeal: notice.appealable && stillOpen,
      servicePointName: name,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(16), child: Text(text));
}

class _EligibleStopTile extends StatelessWidget {
  const _EligibleStopTile(this.stop);

  final AppealableStop stop;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(stop.servicePointName),
    subtitle: Text(
      AppStrings.appealEligibleDetails(
        building: stop.buildingName,
        floor: stop.floorLabel,
        reason: AppStrings.releaseReasonLabel(stop.releaseReason),
        deadline: formatDayTime(stop.deadline),
      ),
    ),
    isThreeLine: true,
    trailing: const Icon(Icons.chevron_right),
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => AppealFormScreen(
          routeStopId: stop.routeStopId,
          releaseReason: stop.releaseReason,
          servicePointName: stop.servicePointName,
        ),
      ),
    ),
  );
}

class _FiledAppealTile extends StatelessWidget {
  const _FiledAppealTile(this.appeal);

  final FiledAppeal appeal;

  @override
  Widget build(BuildContext context) {
    final reviewer = appeal.reviewedByName;
    return ListTile(
      title: Text(appeal.servicePointName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.appealFiledDetails(
              appeal.buildingName,
              formatDayTime(appeal.filedAt),
            ),
          ),
          if (reviewer != null)
            Text(AppStrings.appealReview(reviewer, appeal.reviewNote)),
        ],
      ),
      trailing: Text(AppStrings.appealStatusLabel(appeal.status)),
    );
  }
}

/// The stops the worker can still contest or settle: the server's eligible
/// list and this device's own release notices, each stop once. Drives the
/// badge on the home's account avatar.
///
///     final count = watchAppealableCount(ref);
int watchAppealableCount(WidgetRef ref) {
  final eligible = ref.watch(appealEligibleProvider).asData?.value ?? [];
  final local = ref.watch(localReleasedNoticesProvider).asData?.value ?? [];
  return {
    for (final stop in eligible) stop.routeStopId,
    for (final notice in local) notice.routeStopId,
  }.length;
}
