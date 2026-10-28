import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/gamification/achievements.dart';
import 'package:route_monitor/local/day_log_store.dart';

/// 2026-10-19 is a Monday.
DateTime _d(int day) => DateTime(2026, 10, day);

DayLogEntry _day(
  int day, {
  int points = 0,
  int cards = 0,
  int clean = 0,
  bool serviceDay = true,
}) => DayLogEntry(
  day: _d(day),
  serviceDay: serviceDay,
  pointsDone: points,
  cardsCompleted: cards,
  cleanCards: clean,
);

AchievementProgress _of(List<AchievementProgress> all, Achievement id) =>
    all.singleWhere((a) => a.id == id);

void main() {
  test('exactly five entries, in enum order', () {
    final all = achievementsFrom(const [], _d(19));

    expect(all.map((a) => a.id), Achievement.values);
    expect(all, hasLength(5));
    expect(all.every((a) => !a.unlocked), isTrue);
  });

  test('firstCard unlocks at one completed card', () {
    final locked = achievementsFrom([_day(19, points: 2)], _d(19));
    final unlocked = achievementsFrom([_day(19, points: 2, cards: 1)], _d(19));

    expect(_of(locked, Achievement.firstCard).unlocked, isFalse);
    expect(_of(locked, Achievement.firstCard).current, 0);
    expect(_of(unlocked, Achievement.firstCard).unlocked, isTrue);
    expect(_of(unlocked, Achievement.firstCard).target, 1);
  });

  test('streak5 and streak20 unlock at those streaks; current is the '
      'streak', () {
    final four = [for (var d = 19; d <= 22; d++) _day(d, points: 1)];
    final five = [for (var d = 19; d <= 23; d++) _day(d, points: 1)];

    final atFour = achievementsFrom(four, _d(22));
    final atFive = achievementsFrom(five, _d(23));

    expect(_of(atFour, Achievement.streak5).unlocked, isFalse);
    expect(_of(atFour, Achievement.streak5).current, 4);
    expect(_of(atFive, Achievement.streak5).unlocked, isTrue);
    expect(_of(atFive, Achievement.streak20).unlocked, isFalse);
    expect(_of(atFive, Achievement.streak20).current, 5);
    expect(_of(atFive, Achievement.streak20).target, 20);
  });

  test('a streak achievement stays unlocked after the streak breaks', () {
    final log = [
      for (var d = 5; d <= 9; d++) _day(d, points: 1),
      _day(13, points: 1),
    ];

    final all = achievementsFrom(log, _d(13));

    expect(_of(all, Achievement.streak5).unlocked, isTrue);
    expect(_of(all, Achievement.streak20).current, 1);
  });

  test('points100 sums pointsDone over every day', () {
    final log = [_day(19, points: 60), _day(20, points: 39)];
    final more = [...log, _day(21, points: 1)];

    expect(
      _of(achievementsFrom(log, _d(20)), Achievement.points100).current,
      99,
    );
    expect(
      _of(achievementsFrom(log, _d(20)), Achievement.points100).unlocked,
      isFalse,
    );
    expect(
      _of(achievementsFrom(more, _d(21)), Achievement.points100).unlocked,
      isTrue,
    );
  });

  test('cleanCard unlocks at one clean card', () {
    final dirty = achievementsFrom([_day(19, points: 4, cards: 1)], _d(19));
    final clean = achievementsFrom([
      _day(19, points: 4, cards: 1, clean: 1),
    ], _d(19));

    expect(_of(dirty, Achievement.cleanCard).unlocked, isFalse);
    expect(_of(clean, Achievement.cleanCard).unlocked, isTrue);
  });

  test('current never exceeds target', () {
    final all = achievementsFrom([_day(19, points: 250, cards: 9)], _d(19));

    expect(_of(all, Achievement.points100).current, 100);
    expect(_of(all, Achievement.firstCard).current, 1);
  });
}
