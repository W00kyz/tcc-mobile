import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:route_monitor/appeals/appeals_screen.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/monitoring/monitoring_providers.dart';
import 'package:route_monitor/monitoring/notifications_screen.dart';
import 'package:route_monitor/routing/blocked_sync_screen.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/ui/app_theme.dart';

/// Past this many points the dots would not fit the pill; the text alone
/// carries the count.
const int _maxProgressDots = 12;

/// The floating white pill over the map (redesign §6.2): the account
/// avatar, the worker's name with "Lote 2 · 3 de 8 pontos hoje" and its
/// progress dots, the sync slot and the bell.
///
///     HomeTopBar(route: route, done: 3, total: 8, syncSlot: slot)
class HomeTopBar extends StatelessWidget {
  const HomeTopBar({
    this.route,
    this.done = 0,
    this.total = 0,
    this.syncSlot,
    super.key,
  });

  /// Today's route, when there is one: its worker name and batch.
  final RouteSummary? route;

  /// Points done today (server + device, spec §6.8) out of [total].
  final int done;
  final int total;

  /// The sync indicator's place (Task 10 fills it with `SyncIndicator`).
  final Widget? syncSlot;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    final slot = syncSlot;
    return Material(
      color: p.white,
      elevation: 3,
      shadowColor: p.ink,
      shape: const StadiumBorder(),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            const SizedBox(width: 8),
            _AccountAvatar(name: route?.fieldWorkerName ?? ''),
            const SizedBox(width: 10),
            Expanded(child: _progress(p)),
            ?slot,
            const _NotificationsBell(),
            const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }

  Widget _progress(FieldPalette p) {
    final current = route;
    if (current == null) return const SizedBox.shrink();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          current.fieldWorkerName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: p.ink,
          ),
        ),
        Text(
          AppStrings.dayProgress(current.currentBatch, done, total),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: p.muted),
        ),
        if (total > 0 && total <= _maxProgressDots)
          _ProgressDots(done: done, total: total, palette: p),
      ],
    );
  }
}

/// One circle per point of the day, the done ones filled moss.
class _ProgressDots extends StatelessWidget {
  const _ProgressDots({
    required this.done,
    required this.total,
    required this.palette,
  });

  final int done;
  final int total;
  final FieldPalette palette;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            for (var i = 0; i < total; i++)
              Container(
                key: ValueKey('progress-dot-${i < done ? 'on' : 'off'}-$i'),
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < done ? palette.moss : palette.rule,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _AccountEntry { myData, appeals }

/// The ink avatar with the worker's initial; its menu holds "Meus dados" and
/// "Recursos", badged with the points the worker can contest.
class _AccountAvatar extends ConsumerWidget {
  const _AccountAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    final count = watchAppealableCount(ref);
    final avatar = CircleAvatar(
      radius: 20,
      backgroundColor: p.ink,
      foregroundColor: p.white,
      child: name.isEmpty
          ? const Icon(Icons.person_outline)
          : Text(name.characters.first.toUpperCase()),
    );
    return PopupMenuButton<_AccountEntry>(
      tooltip: AppStrings.accountMenuTooltip,
      onSelected: (entry) => _open(context, entry),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _AccountEntry.myData,
          child: Text(AppStrings.myDataTitle),
        ),
        PopupMenuItem(
          value: _AccountEntry.appeals,
          child: _appealsEntry(count),
        ),
      ],
      child: count == 0 ? avatar : Badge(label: Text('$count'), child: avatar),
    );
  }

  Widget _appealsEntry(int count) {
    const label = Text(AppStrings.appealsTooltip);
    if (count == 0) return label;
    return Badge(label: Text('$count'), child: label);
  }

  void _open(BuildContext context, _AccountEntry entry) {
    switch (entry) {
      case _AccountEntry.myData:
        unawaited(context.push('/meus-dados'));
      case _AccountEntry.appeals:
        unawaited(context.push('/recursos'));
    }
  }
}

/// The bell that opens [NotificationsScreen], with a count badge while there
/// are unread notifications (RF49). A failed/loading count shows no badge
/// rather than a spinner in the header.
class _NotificationsBell extends ConsumerWidget {
  const _NotificationsBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider).asData?.value ?? 0;
    final button = IconButton(
      icon: const Icon(Icons.notifications_outlined),
      tooltip: AppStrings.routeNotificationsTooltip,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
      ),
    );
    if (unread == 0) return button;
    return Badge(label: Text('$unread'), child: button);
  }
}

/// A stop-gap sync slot until Task 10's indicator: renders nothing while the
/// status stream has not emitted; blocked opens [BlockedSyncScreen]; rows
/// waiting send now and re-run the next-batch pull; idle shows a check.
class SyncSlotButton extends ConsumerWidget {
  const SyncSlotButton({
    required this.routeId,
    required this.onSyncNow,
    super.key,
  });

  final String routeId;

  /// "Sincronizar agora": drains the outbox, then retries the pull.
  final Future<void> Function() onSyncNow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(routeSyncStatusProvider(routeId)).asData?.value;
    if (status == null) return const SizedBox.shrink();
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    if (status.state == RouteSyncState.blocked || status.blocked > 0) {
      return IconButton(
        icon: Icon(Icons.sync_problem, color: p.brick),
        tooltip: AppStrings.routeSyncBlockedBanner,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BlockedSyncScreen(routeId: routeId),
          ),
        ),
      );
    }
    if (status.pending > 0) {
      return IconButton(
        icon: Badge(
          label: Text('${status.pending}'),
          child: Icon(Icons.cloud_upload_outlined, color: p.ink),
        ),
        tooltip: AppStrings.routePendingSync(status.pending),
        onPressed: onSyncNow,
      );
    }
    return IconButton(
      icon: Icon(Icons.cloud_done_outlined, color: p.moss),
      tooltip: AppStrings.routeAllSynced,
      onPressed: null,
    );
  }
}
