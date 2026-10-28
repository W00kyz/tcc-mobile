import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/gamification/ink_stamp.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/batch_allocation.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/batch_card.dart';

/// The full card (redesign §6.8): the stamped card whole, "CARTÃO
/// COMPLETO!", the batch's points and time, the streak, and "Pegar próximo
/// lote" — the same next-batch request the map already makes. No confetti:
/// the card is the celebration. [startedAt] is the batch's first check-in;
/// without it the time runs from the first stamp.
///
///     await showFullCard(context, card, streak: 5, startedAt: firstCheckIn);
Future<void> showFullCard(
  BuildContext context,
  BatchCard card, {
  required int streak,
  DateTime? startedAt,
}) {
  final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: p.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => FullCardSheet(
      card: card,
      streak: streak,
      elapsed: batchElapsed(card, startedAt),
    ),
  );
}

/// From [startedAt] (or the first stamp) to the last stamp; zero when the
/// card holds no stamp time.
///
///     batchElapsed(card, DateTime(2026, 10, 21, 7, 42)); // 3:43:00
Duration batchElapsed(BatchCard card, DateTime? startedAt) {
  final stamps = [
    for (final slot in card.groups.expand((g) => g.slots)) ?slot.stampedAt,
  ]..sort();
  if (stamps.isEmpty) return Duration.zero;
  final elapsed = stamps.last.difference(startedAt ?? stamps.first);
  return elapsed.isNegative ? Duration.zero : elapsed;
}

/// The full card's content, sized to itself: nothing pads a gap above the
/// card (a nit of the 07 mock).
class FullCardSheet extends ConsumerWidget {
  const FullCardSheet({
    required this.card,
    required this.streak,
    required this.elapsed,
    super.key,
  });

  final BatchCard card;
  final int streak;
  final Duration elapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _handle(p)),
          const SizedBox(height: 28),
          _head(p),
          const SizedBox(height: 20),
          BatchCardView(card: card),
          const SizedBox(height: 20),
          _StreakLine(streak: streak, palette: p),
          const SizedBox(height: 24),
          ..._actions(context, ref),
        ],
      ),
    );
  }

  Widget _handle(FieldPalette p) => Container(
    width: 32,
    height: 4,
    decoration: BoxDecoration(
      color: p.rule,
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _head(FieldPalette p) => Column(
    children: [
      Text(
        AppStrings.fullCardTitle,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: kDisplayFont,
          fontSize: 31,
          height: 36 / 31,
          color: p.ink,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        AppStrings.fullCardSummary(card.batchNumber, card.total, elapsed),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 16,
          height: 1.5,
          fontWeight: FontWeight.w500,
          color: p.muted,
        ),
      ),
    ],
  );

  /// The next batch is the same request the map makes on its own; read
  /// before the pop, which may take this widget's ref with it.
  List<Widget> _actions(BuildContext context, WidgetRef ref) {
    final allocation = ref.read(batchAllocationProvider.notifier);
    final navigator = Navigator.of(context);
    return [
      FilledButton.icon(
        onPressed: () {
          navigator.pop();
          unawaited(allocation.retry());
        },
        icon: const Icon(Icons.arrow_forward),
        label: const Text(AppStrings.fullCardNextBatch),
      ),
      const SizedBox(height: 4),
      TextButton(
        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: navigator.pop,
        child: const Text(AppStrings.fullCardSeeMap),
      ),
    ];
  }
}

/// A small tilted stamp and "5 dias seguidos". Never a countdown or a
/// comparison (spec §5).
class _StreakLine extends StatelessWidget {
  const _StreakLine({required this.streak, required this.palette});

  final int streak;
  final FieldPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const InkStamp(size: 28, seed: 7, tiltDeg: -7),
        const SizedBox(width: 10),
        Text(
          AppStrings.streakDays(streak),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: palette.ink,
          ),
        ),
      ],
    );
  }
}
