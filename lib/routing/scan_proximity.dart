import 'package:latlong2/latlong.dart';

/// How near a building the worker must be for its floor's check-in to count
/// as "here". A GPS fix indoors drifts by tens of metres.
const double kScanProximityMeters = 80;

/// Whether [worker] is within [kScanProximityMeters] of [building]. A worker
/// with no fix counts as near: GPS is tolerated as unavailable (RF29/RNF13),
/// and the backend's own layers decide what to flag.
///
///     if (!isNearBuilding(position, building.position)) showFarNotice();
bool isNearBuilding(LatLng? worker, LatLng building) {
  if (worker == null) return true;
  return const Distance()(worker, building) <= kScanProximityMeters;
}
