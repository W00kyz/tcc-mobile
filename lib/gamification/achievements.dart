import 'dart:math' as math;

import 'package:route_monitor/gamification/streak.dart';
import 'package:route_monitor/local/day_log_store.dart';

/// The five personal achievements (redesign §6.8), in display order. Few,
/// sober and true: each is computed from the device's own day log.
enum Achievement { firstCard, streak5, streak20, points100, cleanCard }

/// Where the worker stands on one [Achievement]: a locked one shows
/// `current/target` (e.g. `12/20`).
class AchievementProgress {
  const AchievementProgress({
    required this.id,
    required this.unlocked,
    required this.current,
    required this.target,
  });

  final Achievement id;
  final bool unlocked;

  /// Progress so far, never above [target].
  final int current;
  final int target;
}

/// Every achievement, in enum order, from the day [log] as of [today].
///
///     achievementsFrom(await dayLog.all(), DateTime.now());
List<AchievementProgress> achievementsFrom(
  List<DayLogEntry> log,
  DateTime today,
) {
  final cards = log.fold(0, (sum, e) => sum + e.cardsCompleted);
  final clean = log.fold(0, (sum, e) => sum + e.cleanCards);
  final points = log.fold(0, (sum, e) => sum + e.pointsDone);
  final streak = currentStreak(log, today);
  final best = longestStreak(log, today);
  return [
    _counted(Achievement.firstCard, cards, 1),
    _streak(Achievement.streak5, streak, best, 5),
    _streak(Achievement.streak20, streak, best, 20),
    _counted(Achievement.points100, points, 100),
    _counted(Achievement.cleanCard, clean, 1),
  ];
}

AchievementProgress _counted(Achievement id, int value, int target) =>
    AchievementProgress(
      id: id,
      unlocked: value >= target,
      current: math.min(value, target),
      target: target,
    );

/// Unlocked by the best streak ever; [current] is today's streak.
AchievementProgress _streak(
  Achievement id,
  int current,
  int best,
  int target,
) => AchievementProgress(
  id: id,
  unlocked: best >= target,
  current: math.min(current, target),
  target: target,
);
