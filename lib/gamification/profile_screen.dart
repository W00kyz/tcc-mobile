import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:route_monitor/appeals/appeals_screen.dart';

import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/impossibility_reason_dialog.dart';
import 'package:route_monitor/gamification/achievement_grid.dart';
import 'package:route_monitor/gamification/achievements.dart';
import 'package:route_monitor/gamification/gamification_providers.dart';
import 'package:route_monitor/gamification/ink_stamp.dart';
import 'package:route_monitor/gamification/streak.dart';
import 'package:route_monitor/l10n/floor_label.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/day_log_store.dart';
import 'package:route_monitor/routing/building_card_model.dart';
import 'package:route_monitor/routing/day_local_state.dart';
import 'package:route_monitor/routing/home_notices.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/ui/app_theme.dart';

/// "Seu perfil" (`/perfil`, redesign §6.8/§6.12), from the avatar menu: the
/// streak with this week's days, the five achievements, and the shortcuts to
/// Meus dados, Recursos and Sair. Only the worker's own numbers: no ranking,
/// no average, no other worker (spec §5).
///
///     GoRoute(path: '/perfil', builder: (_, _) => const ProfileScreen())
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    // Loading or unreadable reads as an empty log: zero, never an error.
    final log = ref.watch(dayLogEntriesProvider).value ?? const [];
    final today = ref.watch(gamificationClockProvider)();
    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(title: const Text(AppStrings.profileTitle)),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          _StreakCard(log: log, today: today),
          _sectionTitle(p),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: AchievementGrid(achievements: achievementsFrom(log, today)),
          ),
          const SizedBox(height: 14),
          const _ProfileShortcuts(),
        ],
      ),
    );
  }

  Widget _sectionTitle(FieldPalette p) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
    child: Text(
      AppStrings.profileAchievements,
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.ink),
    ),
  );
}

/// "12 dias seguidos", this week Seg..Dom, and the reassurance that a day
/// without service keeps the streak.
class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.log, required this.today});

  final List<DayLogEntry> log;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    final muted = TextStyle(fontSize: 12, height: 16 / 12, color: p.muted);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.rule),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(p),
          const SizedBox(height: 12),
          _WeekRow(log: log, today: today),
          const SizedBox(height: 10),
          Text(AppStrings.profileStreakNote, style: muted),
        ],
      ),
    );
  }

  Widget _header(FieldPalette p) => Row(
    children: [
      const InkStamp(size: 28, seed: 11, tiltDeg: -7),
      const SizedBox(width: 10),
      Text(
        AppStrings.streakDays(currentStreak(log, today)),
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: p.ink,
        ),
      ),
    ],
  );
}

/// Monday to Sunday of [today]'s week: a stamp for a worked day, a dot for
/// a day without service, an empty circle otherwise; today underlined.
class _WeekRow extends StatelessWidget {
  const _WeekRow({required this.log, required this.today});

  final List<DayLogEntry> log;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final byDay = {for (final e in log) dayKey(e.day): e};
    final monday = DateTime(
      today.year,
      today.month,
      today.day - today.weekday + 1,
    );
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: _WeekDay(
              label: AppStrings.weekdayShort[i],
              entry:
                  byDay[dayKey(
                    DateTime(monday.year, monday.month, monday.day + i),
                  )],
              isToday: i == today.weekday - 1,
            ),
          ),
      ],
    );
  }
}

class _WeekDay extends StatelessWidget {
  const _WeekDay({
    required this.label,
    required this.entry,
    required this.isToday,
  });

  final String label;
  final DayLogEntry? entry;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    return Column(
      children: [
        SizedBox.square(dimension: 38, child: Center(child: _mark(p))),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
            color: isToday ? p.ink : p.muted,
            decoration: isToday ? TextDecoration.underline : null,
            decorationThickness: 2,
          ),
        ),
      ],
    );
  }

  Widget _mark(FieldPalette p) {
    final day = entry;
    if (day != null && day.pointsDone > 0) {
      return InkStamp(
        size: 38,
        seed: day.day.day,
        tiltDeg: (day.day.day % 5 - 2) * 3,
      );
    }
    if (day != null && !day.serviceDay) {
      return Semantics(
        container: true,
        label: AppStrings.profileNoServiceDay,
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: p.muted),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.paper,
        border: Border.all(color: p.rule, width: 1.5),
      ),
    );
  }
}

/// Meus dados, Recursos, Encerrar por hoje (only while a route is in
/// progress) and Sair, as plain 56dp list rows.
class _ProfileShortcuts extends ConsumerWidget {
  const _ProfileShortcuts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    final route = ref.watch(myDayProvider).value?.route;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.rule)),
      ),
      child: Column(
        children: [
          _row(const Icon(Icons.badge_outlined), AppStrings.myDataTitle, () {
            unawaited(context.push('/meus-dados'));
          }),
          _row(
            _badged(Icons.flag_outlined, watchAppealableCount(ref)),
            AppStrings.appealsTooltip,
            () => unawaited(context.push('/recursos')),
          ),
          if (route != null && route.status == 'IN_PROGRESS')
            _endDayRow(context, ref, route),
          _row(const Icon(Icons.logout), AppStrings.profileSignOut, () {
            unawaited(ref.read(sessionProvider.notifier).logout());
          }),
        ],
      ),
    );
  }

  /// The points the worker can contest, carried over from the map avatar.
  Widget _badged(IconData icon, int count) =>
      count == 0 ? Icon(icon) : Badge(label: Text('$count'), child: Icon(icon));

  /// Off, saying which, while a floor's check-in is open: ending the day
  /// then would strand its stamped tasks, never checked out.
  Widget _endDayRow(BuildContext context, WidgetRef ref, RouteSummary route) {
    final open = _openFloor(ref, route);
    return _row(
      const Icon(Icons.event_busy_outlined),
      AppStrings.profileEndDay,
      open == null ? () => unawaited(_endDay(context, ref, route)) : null,
      subtitle: open == null
          ? AppStrings.profileEndDaySubtitle
          : AppStrings.endDayFinishOpenFloor(
              open.building.name,
              floorDisplayLabel(open.floor.label),
            ),
    );
  }

  /// The day's floor with a check-in open, as the map home draws it.
  OpenFloor? _openFloor(WidgetRef ref, RouteSummary route) {
    final impeded =
        ref.watch(impededStopIdsProvider(route.id)).value ?? const <String>{};
    final local = watchLocalStates(ref, route);
    return openFloorOfDay(buildDayBuildings(route, local, impeded, const {}));
  }

  /// A null [onTap] draws the row disabled.
  Widget _row(
    Widget leading,
    String label,
    VoidCallback? onTap, {
    String? subtitle,
  }) => ListTile(
    minTileHeight: 56,
    leading: leading,
    title: Text(label),
    subtitle: subtitle == null ? null : Text(subtitle),
    enabled: onTap != null,
    onTap: onTap,
  );

  /// "Encerrar por hoje": asks why, hands the rest of the route back
  /// (`ROUTE_REMAINDER`) and returns to the map as soon as the report is
  /// written; the sync and the day reload follow without holding the worker
  /// on this screen (offline must not delay the pop). Cancelling the reason
  /// reports nothing.
  Future<void> _endDay(
    BuildContext context,
    WidgetRef ref,
    RouteSummary route,
  ) async {
    final reason = await showImpossibilityReasonDialog(context);
    if (reason == null || !context.mounted) return;
    // Captured before any await: this screen is gone once it pops.
    final container = ProviderScope.containerOf(context);
    final notify = homeNotifier(ref, context);
    final navigator = Navigator.of(context);
    await container
        .read(executionRepositoryProvider)
        .reportImpediment(
          routeId: route.id,
          routeStopId: null,
          scope: 'ROUTE_REMAINDER',
          reason: reason,
        );
    await _discardHeldPhotos(container, route);
    notify(AppStrings.routeImpedimentReported);
    navigator.pop();
    await container.read(syncWorkerProvider).syncRoute(route.id);
    container.invalidate(myDayProvider);
  }

  /// The photos held for a task of [route] still open: it is handed back
  /// with the rest, and the backend refuses evidence of a released stop.
  Future<void> _discardHeldPhotos(
    ProviderContainer container,
    RouteSummary route,
  ) async {
    final progress = container.read(stopProgressStoreProvider);
    final store = container.read(localWriteStoreProvider);
    final open = route.stops
        .where((s) => s.status == 'PENDING' || s.status == 'IN_PROGRESS')
        .map((s) => s.id);
    for (final entry in await progress.allForRoute(open)) {
      await store.discardHeldPhotos(entry.executionId);
    }
  }
}
