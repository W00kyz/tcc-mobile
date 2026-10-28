import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/execution/execution_providers.dart'
    show dayLogStoreProvider, localWriteStoreProvider;
import 'package:route_monitor/gamification/full_card_sheet.dart';
import 'package:route_monitor/gamification/gamification_providers.dart';
import 'package:route_monitor/gamification/streak.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/stop_actions.dart';
import 'package:route_monitor/sync/sync_providers.dart';

/// How long the completion waits for the last check-out's drain before it
/// decides whether the card was clean.
const Duration fullCardCleanWindow = Duration(seconds: 10);

/// The map home's gamification hooks (redesign §6.8): logs each day the
/// worker's day is read, and opens the full card once the stamp that
/// completes [card] has landed.
///
///     FullCardTrigger(card: card, routeId: route?.id, child: body)
class FullCardTrigger extends ConsumerStatefulWidget {
  const FullCardTrigger({
    required this.card,
    required this.routeId,
    required this.child,
    super.key,
  });

  /// The card as last drawn, null while no batch is worked.
  final BatchCard? card;
  final String? routeId;
  final Widget child;

  @override
  ConsumerState<FullCardTrigger> createState() => _FullCardTriggerState();
}

class _FullCardTriggerState extends ConsumerState<FullCardTrigger> {
  /// The stop just stamped, until a card with its slot done is drawn.
  String? _stamped;

  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<MyDay>>(myDayProvider, (_, next) {
      if (next case AsyncData(:final value)) _recordDayOpened(value);
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(lastStampedStopProvider, (_, stopId) {
      if (stopId != null) _stamped = stopId;
    });
    _openWhenComplete(widget.card, widget.routeId);
    return widget.child;
  }

  /// The stamp is set once the check-out is written, but the card catches
  /// up a frame or more later (its progress row is re-read): wait for the
  /// card showing that slot done, then look at `complete` once.
  void _openWhenComplete(BatchCard? card, String? routeId) {
    final stopId = _stamped;
    if (stopId == null || card == null || routeId == null) return;
    final slot = card.groups
        .expand((g) => g.slots)
        .where((s) => s.stopId == stopId)
        .firstOrNull;
    if (slot != null && slot.state != SlotState.done) return;
    _stamped = null;
    if (slot == null || !card.complete) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _logged('full_card_failed', _celebrate(card, routeId)),
    );
  }

  Future<void> _celebrate(BatchCard card, String routeId) async {
    final now = ref.read(gamificationClockProvider)();
    _logged('card_completion_failed', _recordCompletion(routeId, now));
    final log = await ref.read(dayLogStoreProvider).all();
    final startedAt = await ref.read(firstCheckInLookupProvider)(
      card.groups.expand((g) => g.slots).map((s) => s.stopId),
    );
    if (!mounted) return;
    await showFullCard(
      context,
      card,
      streak: currentStreak(log, now),
      startedAt: startedAt,
    );
  }

  /// Counts the card once. "Clean" is decided after the drain the last
  /// check-out kicked (bounded by [fullCardCleanWindow]): read at the stamp
  /// itself, the outbox always still holds that check-out, and the "sem
  /// pendências" achievement could never be earned.
  Future<void> _recordCompletion(String routeId, DateTime now) async {
    final worker = ref.read(syncWorkerProvider);
    final store = ref.read(localWriteStoreProvider);
    final dayLog = ref.read(dayLogStoreProvider);
    try {
      await worker.syncRoute(routeId).timeout(fullCardCleanWindow);
    } on TimeoutException {
      // Still sending: whatever is left counts as pending below.
    }
    final pending = await store.unsyncedForRoute(routeId);
    final blocked = await store.blockedForRoute(routeId);
    await dayLog.recordCardCompleted(
      now,
      clean: pending.isEmpty && blocked.isEmpty,
    );
    if (mounted) ref.invalidate(dayLogEntriesProvider);
  }

  void _recordDayOpened(MyDay day) {
    final now = ref.read(gamificationClockProvider)();
    _logged(
      'day_log_open_failed',
      ref
          .read(dayLogStoreProvider)
          .recordDayOpened(now, serviceDay: day.serviceDay),
    );
  }

  /// A gamification write never breaks the day: a failure is logged.
  void _logged(String event, Future<void> work) {
    unawaited(
      work.catchError((Object error, StackTrace stack) {
        developer.log(
          jsonEncode({'event': event, 'error': '$error'}),
          name: 'gamification',
          stackTrace: stack,
        );
      }),
    );
  }
}
