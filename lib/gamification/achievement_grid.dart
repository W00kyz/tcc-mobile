import 'package:flutter/material.dart';

import 'package:route_monitor/gamification/achievements.dart';
import 'package:route_monitor/gamification/ink_stamp.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/stamp_painters.dart';

const int _perRow = 3;
const double _stampSize = 64;

/// The profile's achievements (redesign §6.8): one circular stamp each,
/// inked when earned, a dashed outline with `current/target` when not.
///
///     AchievementGrid(achievements: achievementsFrom(log, today))
class AchievementGrid extends StatelessWidget {
  const AchievementGrid({required this.achievements, super.key});

  final List<AchievementProgress> achievements;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth / _perRow;
        return Wrap(
          runSpacing: 14,
          children: [
            for (final a in achievements)
              SizedBox(
                width: width,
                child: _AchievementTile(progress: a),
              ),
          ],
        );
      },
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({required this.progress});

  final AchievementProgress progress;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    final unlocked = progress.unlocked;
    return Column(
      children: [
        ExcludeSemantics(child: _stamp(p)),
        const SizedBox(height: 6),
        Text(
          achievementLabel(progress.id),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 16 / 12,
            fontWeight: FontWeight.w600,
            color: unlocked ? p.ink : p.muted,
          ),
        ),
        if (!unlocked)
          Text(
            AppStrings.achievementProgress(progress.current, progress.target),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: p.muted,
            ),
          ),
      ],
    );
  }

  Widget _stamp(FieldPalette p) {
    final id = progress.id;
    if (progress.unlocked) {
      return InkStamp(
        key: ValueKey('achievement-unlocked-${id.name}'),
        size: _stampSize,
        seed: id.index + 3,
        tiltDeg: _tilts[id.index],
        mark: _mark(p.moss),
      );
    }
    return CustomPaint(
      key: ValueKey('achievement-locked-${id.name}'),
      painter: RingPainter(kind: RingKind.locked, palette: p),
      child: SizedBox.square(
        dimension: _stampSize,
        child: Center(child: _mark(p.muted) ?? _lockedDot(p.muted)),
      ),
    );
  }

  /// The number a streak or points stamp carries; null for a check.
  Widget? _mark(Color color) {
    final number = switch (progress.id) {
      Achievement.streak5 => '5',
      Achievement.streak20 => '20',
      Achievement.points100 => '100',
      Achievement.firstCard || Achievement.cleanCard => null,
    };
    if (number == null) return null;
    return Text(
      number,
      style: TextStyle(
        fontSize: number.length > 2 ? 18 : 20,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    );
  }

  /// A not-yet-earned card achievement: a neutral dot, never a check — a
  /// check would read as done.
  Widget _lockedDot(Color color) => Container(
    key: const ValueKey('achievement-locked-dot'),
    width: 8,
    height: 8,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

/// A fixed tilt per achievement, like a slot's: never changes on redraw.
const List<double> _tilts = [-6, 7, -4, -3, 5];

/// The pt-BR name of [id].
///
///     achievementLabel(Achievement.streak5); // '5 dias seguidos'
String achievementLabel(Achievement id) => switch (id) {
  Achievement.firstCard => AppStrings.achievementFirstCard,
  Achievement.streak5 => AppStrings.achievementStreak5,
  Achievement.streak20 => AppStrings.achievementStreak20,
  Achievement.points100 => AppStrings.achievementPoints100,
  Achievement.cleanCard => AppStrings.achievementCleanCard,
};
