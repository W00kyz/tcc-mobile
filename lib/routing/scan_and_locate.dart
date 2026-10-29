import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/home_notices.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';

/// A completed scan+GPS read, threaded from [scanAndLocate] into a check-in
/// or check-out attempt.
class ScanResult {
  const ScanResult(this.rawValue, this.coordinates);
  final String rawValue;
  final Coordinates? coordinates;
}

/// Pushes [ScanScreen] and, if a value came back, pairs it with a
/// tolerant GPS read — the shared first half of both check-in and
/// check-out (Ruling 16: check-out reuses check-in's scan+GPS dance).
/// Returns null when the scan was dismissed or the context is no longer
/// mounted afterward.
///
///     final scan = await scanAndLocate(context, ref, EntryScan(building));
Future<ScanResult?> scanAndLocate(
  BuildContext context,
  WidgetRef ref,
  ScanContext scanContext,
) async {
  final rawValue = await Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => ScanScreen(context: scanContext),
    ),
  );
  if (rawValue == null || !context.mounted) return null;

  final coordinates = await tryGetPosition(context, ref);
  return ScanResult(rawValue, coordinates);
}

/// GPS is tolerated as unavailable here (RF29/RNF13 — a basement has no
/// signal): the backend's Layer 7 already treats a missing position as
/// ACCEPT+flag, so a failure here must not block the check-in, only note
/// it to the field worker.
Future<Coordinates?> tryGetPosition(BuildContext context, WidgetRef ref) async {
  final notify = homeNotifier(ref, context);
  try {
    return await ref
        .read(locationServiceProvider)
        .getCurrentPosition(purpose: LocationPurpose.checkin);
    // Deliberately broad: GeolocatorLocationService can fail with a
    // StateError (permission denied), a platform exception, or a timeout
    // — all of them mean "proceed without GPS" here, never "block".
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    if (context.mounted) notify(AppStrings.routeLocationUnavailableCheckIn);
    return null;
  }
}

/// The entry scan's context line: a QR resolves its floor only after the
/// scan, so it names the building of the batch's next pending stop.
///
///     scanAndLocate(context, ref, entryScanContext(route));
ScanContext entryScanContext(RouteSummary route) {
  final next = route.currentBatchStops.firstWhere(
    (stop) => stop.status == 'PENDING',
    orElse: () => route.currentBatchStops.first,
  );
  return EntryScan(next.buildingName);
}
