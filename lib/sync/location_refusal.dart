import 'dart:convert';

import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/pending_operation.dart';

/// A location completion the server refused (spec 2026-10-30-locais-externos
/// §4): what the sync worker reports once per refused row, so the app can
/// tell the worker the place is still pending and why.
///
///     final refusal = LocationRefusal.of(error, routeStopId: 's1');
///     if (refusal != null) showSnack(refusal.message);
class LocationRefusal {
  const LocationRefusal({
    required this.operationId,
    required this.routeStopId,
    required this.placeName,
    required this.code,
    required this.distanceM,
    required this.radiusM,
  });

  /// The refusal a `rejected` [row] records: the place from its payload, the
  /// reason from its `lastError` ([toStoredError]). A row whose error is not
  /// that JSON reads as "too far", with no distance.
  factory LocationRefusal.fromRejectedRow(PendingOperationRow row) {
    final stored = _decodeStored(row.lastError);
    return LocationRefusal(
      operationId: row.id,
      routeStopId: row.payload['route_stop_id'] as String,
      placeName: row.payload['place_name'] as String?,
      code:
          stored['code'] as String? ?? LocationRefusedException.codeOutOfRadius,
      distanceM: (stored['distance_m'] as num?)?.toDouble(),
      radiusM: (stored['radius_m'] as num?)?.toInt(),
    );
  }

  /// [error] as a refusal of [routeStopId]'s completion, or null when it is
  /// any other failure. [placeName] comes from the queued payload.
  static LocationRefusal? of(
    Object error, {
    required String operationId,
    required String routeStopId,
    String? placeName,
  }) {
    final refused = LocationRefusedException.fromError(error);
    if (refused == null) return null;
    return LocationRefusal(
      operationId: operationId,
      routeStopId: routeStopId,
      placeName: placeName,
      code: refused.code,
      distanceM: refused.distanceM,
      radiusM: refused.radiusM,
    );
  }

  /// The refused `locationCompletion` row: what a notice is acknowledged by.
  final String operationId;
  final String routeStopId;

  /// The place's name as the device knew it when the worker tapped; null for
  /// a row queued without one.
  final String? placeName;
  final String code;
  final double? distanceM;
  final int? radiusM;

  /// What `markRejected` stores as the row's `lastError`: the server's
  /// reason, readable again by [LocationRefusal.fromRejectedRow] in another
  /// isolate (the background drain rejects, the app tells).
  String toStoredError() => jsonEncode({
    'code': code,
    'distance_m': distanceM,
    'radius_m': radiusM,
  });

  static Map<String, dynamic> _decodeStored(String? lastError) {
    if (lastError == null) return const {};
    try {
      final decoded = jsonDecode(lastError);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

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
