import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/start_availability.dart';

import '../support/fake_route_repository.dart';

// The server says it is 09:55:28 and the workday opens at 10:00:00: 4:32 left.
final _serverNow = DateTime.utc(2026, 11, 2, 9, 55, 28);
final _opensAt = DateTime.utc(2026, 11, 2, 10);

MyDay _day({
  bool serviceDay = true,
  RouteSummary? route,
  DateTime? startOpensAt,
  bool workdayOver = false,
  Duration serverOffset = Duration.zero,
  bool fromSnapshot = false,
}) => MyDay(
  serviceDay: serviceDay,
  route: route,
  positionIntervalSeconds: 60,
  silenceWarningMinutes: 30,
  silenceReleaseMinutes: 45,
  serverTime: _serverNow,
  startOpensAt: startOpensAt,
  workdayOver: workdayOver,
  serverOffset: serverOffset,
  fromSnapshot: fromSnapshot,
);

void main() {
  group('startAvailability', () {
    test('a_day_from_the_offline_snapshot_is_enabled_without_a_hint', () {
      // Its offset and opening are stale: the server's 409 decides.
      for (final stale in [
        _day(fromSnapshot: true, startOpensAt: _opensAt),
        _day(fromSnapshot: true, workdayOver: true),
      ]) {
        final result = startAvailability(stale, deviceNow: _serverNow);

        expect(result.enabled, isTrue);
        expect(result.countdown, isNull);
        expect(result.hint, isNull);
      }
    });

    test('untilCountdown_is_the_wait_for_the_5_minute_window', () {
      final wait = untilCountdown(
        _day(startOpensAt: _opensAt),
        deviceNow: DateTime.utc(2026, 11, 2, 9, 50),
      );

      expect(wait, const Duration(minutes: 5));
    });

    test('untilCountdown_is_null_inside_the_window_or_without_opening', () {
      final inside = untilCountdown(
        _day(startOpensAt: _opensAt),
        deviceNow: _serverNow,
      );
      final noOpening = untilCountdown(_day(), deviceNow: _serverNow);

      expect(inside, isNull);
      expect(noOpening, isNull);
    });

    test(
      'disabled_without_countdown_when_opening_is_more_than_5_minutes_away',
      () {
        final result = startAvailability(
          _day(startOpensAt: _opensAt),
          deviceNow: DateTime.utc(2026, 11, 2, 9, 54),
        );

        expect(result.enabled, isFalse);
        expect(result.countdown, isNull);
        expect(result.hint, AppStrings.routeStartNotOpenYet);
      },
    );

    test('countdown_appears_inside_the_last_5_minutes', () {
      final result = startAvailability(
        _day(startOpensAt: _opensAt),
        deviceNow: _serverNow,
      );

      expect(result.enabled, isFalse);
      expect(result.countdown, const Duration(minutes: 4, seconds: 32));
      expect(result.hint, isNull);
    });

    test('countdown_starts_at_exactly_5_minutes', () {
      final result = startAvailability(
        _day(startOpensAt: _opensAt),
        deviceNow: DateTime.utc(2026, 11, 2, 9, 55),
      );

      expect(result.countdown, const Duration(minutes: 5));
    });

    test('enabled_at_the_opening_instant', () {
      final result = startAvailability(
        _day(startOpensAt: _opensAt),
        deviceNow: _opensAt,
      );

      expect(result.enabled, isTrue);
      expect(result.countdown, isNull);
      expect(result.hint, isNull);
    });

    test('enabled_when_there_is_no_opening_to_wait_for', () {
      final result = startAvailability(_day(), deviceNow: _opensAt);

      expect(result.enabled, isTrue);
    });

    test('uses_the_server_clock_not_the_device_clock', () {
      // The device runs 3 h ahead of the server.
      final result = startAvailability(
        _day(startOpensAt: _opensAt, serverOffset: const Duration(hours: -3)),
        deviceNow: _serverNow.add(const Duration(hours: 3)),
      );

      expect(result.enabled, isFalse);
      expect(result.countdown, const Duration(minutes: 4, seconds: 32));
    });

    test('disabled_after_the_workday', () {
      final result = startAvailability(
        _day(workdayOver: true),
        deviceNow: _opensAt,
      );

      expect(result.enabled, isFalse);
      expect(result.countdown, isNull);
      expect(result.hint, AppStrings.routeWorkdayOver);
    });

    test('disabled_on_a_non_service_day', () {
      final result = startAvailability(
        _day(serviceDay: false),
        deviceNow: _opensAt,
      );

      expect(result.enabled, isFalse);
      expect(result.countdown, isNull);
      // The day panel already says "no service today"; no extra hint.
      expect(result.hint, isNull);
    });

    test('disabled_while_a_route_is_running', () {
      final result = startAvailability(
        _day(
          route: routeWith(stops: const []),
        ),
        deviceNow: _opensAt,
      );

      expect(result.enabled, isFalse);
    });

    test('enabled_for_a_paused_route_regardless_of_the_opening', () {
      final result = startAvailability(
        _day(
          route: routeWith(stops: const [], status: 'PAUSED'),
          startOpensAt: _opensAt,
        ),
        deviceNow: DateTime.utc(2026, 11, 2, 9),
      );

      expect(result.enabled, isTrue);
      expect(result.countdown, isNull);
    });
  });

  group('MyDay.fromJson', () {
    Map<String, dynamic> payload() => {
      'service_day': true,
      'route': null,
      'position_report_interval_seconds': 60,
      'location_silence_warning_minutes': 30,
      'location_silence_release_minutes': 45,
      'server_time': '2026-11-02T09:55:28Z',
      'start_opens_at': '2026-11-02T10:00:00Z',
      'workday_over': false,
    };

    test('reads the workday fields and the offset to the server clock', () {
      final day = MyDay.fromJson(
        payload(),
        receivedAt: DateTime.utc(2026, 11, 2, 12, 55, 28),
      );

      expect(day.serverTime, _serverNow);
      expect(day.startOpensAt, _opensAt);
      expect(day.workdayOver, isFalse);
      expect(day.serverOffset, const Duration(hours: -3));
    });

    test('keeps a null start_opens_at null', () {
      final json = payload()
        ..['start_opens_at'] = null
        ..['workday_over'] = true;

      final day = MyDay.fromJson(json, receivedAt: _serverNow);

      expect(day.startOpensAt, isNull);
      expect(day.workdayOver, isTrue);
      expect(day.serverOffset, Duration.zero);
    });
  });

  test('routeStartCountdown words the time left as mm:ss', () {
    expect(
      AppStrings.routeStartCountdown(const Duration(seconds: 272)),
      'Abre em 04:32',
    );
  });
}
