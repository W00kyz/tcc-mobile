import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/gamification/streak.dart';
import 'package:route_monitor/local/day_log_store.dart';

/// 2026-10-19 is a Monday.
DateTime _d(int day) => DateTime(2026, 10, day);

DayLogEntry _worked(int day, {int points = 3}) => DayLogEntry(
  day: _d(day),
  serviceDay: true,
  pointsDone: points,
  cardsCompleted: 0,
  cleanCards: 0,
);

DayLogEntry _opened(int day, {bool serviceDay = true}) => DayLogEntry(
  day: _d(day),
  serviceDay: serviceDay,
  pointsDone: 0,
  cardsCompleted: 0,
  cleanCards: 0,
);

void main() {
  test('Mon-Fri worked, Monday today with nothing done yet: 5 '
      '(the missing weekend is neutral)', () {
    final log = [for (var d = 19; d <= 23; d++) _worked(d), _opened(26)];

    expect(currentStreak(log, _d(26)), 5);
  });

  test('a weekday with no row breaks the streak; the count restarts '
      'after it', () {
    // Mon, Tue worked; Wed missing; Thu, Fri worked.
    final log = [_worked(19), _worked(20), _worked(22), _worked(23)];

    expect(currentStreak(log, _d(23)), 2);
  });

  test('a serviceDay=false Wednesday between worked days does not break '
      'it', () {
    final log = [
      _worked(19),
      _worked(20),
      _opened(21, serviceDay: false),
      _worked(22),
      _worked(23),
    ];

    expect(currentStreak(log, _d(23)), 4);
  });

  test('a past service day with 0 points breaks it', () {
    final log = [_worked(19), _worked(20), _opened(21), _worked(22)];

    expect(currentStreak(log, _d(22)), 1);
  });

  test('today with 0 points neither breaks nor counts', () {
    final log = [_worked(19), _worked(20), _opened(21)];

    expect(currentStreak(log, _d(21)), 2);
  });

  test('today with points counts', () {
    final log = [_worked(19), _worked(20), _worked(21)];

    expect(currentStreak(log, _d(21)), 3);
  });

  test('an empty log is 0', () {
    expect(currentStreak(const [], _d(21)), 0);
  });

  test('longestStreak keeps the best run after a break', () {
    final log = [
      for (var d = 5; d <= 9; d++) _worked(d),
      // Mon 12 missing breaks it.
      _worked(13),
    ];

    expect(longestStreak(log, _d(13)), 5);
    expect(currentStreak(log, _d(13)), 1);
  });
}
