import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/location_service.dart';

/// A continuous stream of GPS fixes — the background mode's source (spec
/// 2026-10-20-alocacao-automatica §7.3). A seam so `PositionReporter` and its
/// tests never reach the Geolocator platform channel.
// A single-method interface on purpose, like `LocationService`.
// ignore: one_member_abstracts
abstract class PositionSource {
  /// Fixes roughly every [interval] until the subscription is cancelled.
  Stream<Coordinates> watch({required Duration interval});
}

/// The stream settings of the background mode. On Android, Geolocator runs
/// the stream in a foreground service — the fixed "Rota em andamento"
/// notification — so it keeps reporting with the screen locked.
///
///     Geolocator.getPositionStream(
///       locationSettings: backgroundLocationSettings(interval),
///     );
LocationSettings backgroundLocationSettings(Duration interval) {
  // Same battery trade as `LocationPurpose.tracking` (RNF22), but no distance
  // filter: a worker parked in a room for half an hour must keep reporting,
  // or the server takes the quiet for silence and releases their points.
  if (defaultTargetPlatform != TargetPlatform.android) {
    return const LocationSettings(accuracy: LocationAccuracy.medium);
  }
  return AndroidSettings(
    accuracy: LocationAccuracy.medium,
    intervalDuration: interval,
    foregroundNotificationConfig: const ForegroundNotificationConfig(
      notificationTitle: AppStrings.routeInProgressTitle,
      notificationText: AppStrings.routeInProgressText,
      // Its own name in the system settings, apart from the in-app ongoing
      // notice's "Coleta de localização" channel.
      notificationChannelName: AppStrings.routeInProgressTitle,
      enableWakeLock: true,
      setOngoing: true,
    ),
  );
}

/// The real stream. Only exercisable on a device; the settings it uses are
/// covered by `test/monitoring/position_source_test.dart`.
class GeolocatorPositionSource implements PositionSource {
  @override
  Stream<Coordinates> watch({required Duration interval}) {
    return Geolocator.getPositionStream(
      locationSettings: backgroundLocationSettings(interval),
    ).map(
      (position) => Coordinates(
        latitude: position.latitude,
        longitude: position.longitude,
      ),
    );
  }
}
