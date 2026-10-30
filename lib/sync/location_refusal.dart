import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/l10n/strings.dart';

/// A location completion the server refused (spec 2026-10-30-locais-externos
/// §4): what the sync worker reports once per refused row, so the app can
/// tell the worker the place is still pending and why.
///
///     final refusal = LocationRefusal.of(error, routeStopId: 's1');
///     if (refusal != null) showSnack(refusal.message);
class LocationRefusal {
  const LocationRefusal({
    required this.routeStopId,
    required this.placeName,
    required this.code,
    required this.distanceM,
    required this.radiusM,
  });

  /// [error] as a refusal of [routeStopId]'s completion, or null when it is
  /// any other failure. [placeName] comes from the queued payload.
  static LocationRefusal? of(
    Object error, {
    required String routeStopId,
    String? placeName,
  }) {
    final refused = LocationRefusedException.fromError(error);
    if (refused == null) return null;
    return LocationRefusal(
      routeStopId: routeStopId,
      placeName: placeName,
      code: refused.code,
      distanceM: refused.distanceM,
      radiusM: refused.radiusM,
    );
  }

  final String routeStopId;

  /// The place's name as the device knew it when the worker tapped; null for
  /// a row queued without one.
  final String? placeName;
  final String code;
  final double? distanceM;
  final int? radiusM;

  /// The pt-BR notice: how far the worker was, or that the location was off.
  String get message {
    final place = placeName ?? AppStrings.locationRefusedPlaceFallback;
    if (code == LocationRefusedException.codeLocationRequired) {
      return AppStrings.locationRefusedNoLocation(place);
    }
    final distance = distanceM;
    if (distance == null) return AppStrings.locationRefusedTooFar(place);
    return AppStrings.locationRefusedOutOfRadius(place, distance.round());
  }
}
