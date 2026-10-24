import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:route_monitor/appeals/appeal_api.dart';
import 'package:route_monitor/appeals/appeal_form_screen.dart';
import 'package:route_monitor/appeals/appeal_providers.dart';
import 'package:route_monitor/appeals/day_time.dart';
import 'package:route_monitor/l10n/strings.dart';

/// `/recursos` (spec 2026-10-20-alocacao-automatica §7.5, §9): the released
/// points the worker can still contest — each opens its appeal form — and
/// the appeals already sent, with their decisions. Pull to refresh.
class AppealsScreen extends ConsumerWidget {
  const AppealsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eligible = ref.watch(appealEligibleProvider);
    final mine = ref.watch(myAppealsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.appealsAppBarTitle)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(appealEligibleProvider)
            ..invalidate(myAppealsProvider);
          await ref.read(appealEligibleProvider.future);
        },
        child: ListView(
          children: [
            const _SectionTitle(AppStrings.appealsEligibleTitle),
            ..._section(
              eligible,
              empty: AppStrings.appealsEligibleEmpty,
              tile: _EligibleStopTile.new,
            ),
            const _SectionTitle(AppStrings.appealsMineTitle),
            ..._section(
              mine,
              empty: AppStrings.appealsMineEmpty,
              tile: _FiledAppealTile.new,
            ),
          ],
        ),
      ),
    );
  }

  /// One list's rows: a spinner, the load error, the empty line, or a tile
  /// per item.
  static List<Widget> _section<T>(
    AsyncValue<List<T>> items, {
    required String empty,
    required Widget Function(T item) tile,
  }) => items.when(
    loading: () => const [
      Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
    ],
    error: (_, _) => const [_Note(AppStrings.appealsLoadError)],
    data: (list) => list.isEmpty ? [_Note(empty)] : list.map(tile).toList(),
  );
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

/// The route screen's app-bar entry to [AppealsScreen], badged with how many
/// released points the worker can still contest. A failed or loading count
/// shows no badge, like the notifications bell.
class AppealsEntryButton extends ConsumerWidget {
  const AppealsEntryButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(appealEligibleProvider).asData?.value.length ?? 0;
    final button = IconButton(
      icon: const Icon(Icons.gavel_outlined),
      tooltip: AppStrings.appealsTooltip,
      onPressed: () => context.push('/recursos'),
    );
    if (count == 0) return button;
    return Badge(label: Text('$count'), child: button);
  }
}
