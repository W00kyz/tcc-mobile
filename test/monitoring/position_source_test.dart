import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/monitoring/position_source.dart';

void main() {
  test('Android: a foreground service with the "Rota em andamento" notice', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final settings =
        backgroundLocationSettings(const Duration(seconds: 60))
            as AndroidSettings;

    expect(settings.intervalDuration, const Duration(seconds: 60));
    // No distance filter: a worker parked in a room still reports, or the
    // server would take the quiet for silence.
    expect(settings.distanceFilter, 0);
    final notice = settings.foregroundNotificationConfig!;
    expect(notice.notificationTitle, AppStrings.routeInProgressTitle);
    expect(notice.notificationText, AppStrings.routeInProgressText);
    expect(notice.notificationChannelName, AppStrings.routeInProgressTitle);
    expect(notice.enableWakeLock, isTrue);
    expect(notice.setOngoing, isTrue);
  });

  test('elsewhere: plain settings, no Android service', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final settings = backgroundLocationSettings(const Duration(seconds: 60));

    expect(settings, isNot(isA<AndroidSettings>()));
  });
}
