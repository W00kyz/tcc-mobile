import 'package:route_monitor/local/day_log_store.dart';

/// How one calendar day weighs on the streak.
enum StreakDay {
  /// At least one point concluded: the streak grows.
  worked,

  /// Neither grows nor breaks it: a day without service, a weekend with no
  /// row, or today before the first point (the day is not over yet).
  neutral,

  /// A service day that ended with no point: the streak restarts.
  broken,
}

/// Classifies [date] from its [entry] (null = the app was never opened that
/// day). A missing Saturday or Sunday is neutral (Review Focus 5); a missing
/// weekday is broken.
///
///     streakDayOf(null, DateTime(2026, 10, 25), today: today); // neutral
StreakDay streakDayOf(
  DayLogEntry? entry,
  DateTime date, {
  required DateTime today,
}) {
  if (entry != null && entry.pointsDone > 0) return StreakDay.worked;
  if (_sameDate(date, today)) return StreakDay.neutral;
  if (entry != null && !entry.serviceDay) return StreakDay.neutral;
  if (entry == null && date.weekday >= DateTime.saturday) {
    return StreakDay.neutral;
  }
  return StreakDay.broken;
}

/// Days in a row with at least one point, up to [today] — the "N dias
/// seguidos" (redesign §6.8). Today with no point yet does not break it.
///
///     currentStreak(await dayLog.all(), DateTime.now()); // 5
int currentStreak(List<DayLogEntry> log, DateTime today) =>
    _runs(log, today).current;

/// The longest streak ever reached up to [today]: an unlocked streak
/// achievement stays unlocked after a break.
///
///     longestStreak(await dayLog.all(), DateTime.now()); // 12
int longestStreak(List<DayLogEntry> log, DateTime today) =>
    _runs(log, today).best;

/// One forward pass from the first logged day to [today].
({int current, int best}) _runs(List<DayLogEntry> log, DateTime today) {
  if (log.isEmpty) return (current: 0, best: 0);
  final byDay = {for (final e in log) dayKey(e.day): e};
  final last = _dateOf(today);
  var run = 0;
  var best = 0;
  for (var d = _dateOf(log.first.day); !d.isAfter(last); d = _next(d)) {
    switch (streakDayOf(byDay[dayKey(d)], d, today: last)) {
      case StreakDay.worked:
        run++;
        if (run > best) best = run;
      case StreakDay.neutral:
        break;
      case StreakDay.broken:
        run = 0;
    }
  }
  return (current: run, best: best);
}

DateTime _dateOf(DateTime at) => DateTime(at.year, at.month, at.day);

/// Calendar arithmetic, not `add(Duration(days: 1))`: a DST change would
/// skip or repeat a date.
DateTime _next(DateTime date) => DateTime(date.year, date.month, date.day + 1);

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
