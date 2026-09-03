import 'dart:math' as math;

import 'package:route_monitor/routing/route_repository.dart';

/// Earth radius in metres — same constant as
/// `backend/app/domain/execution/geo.py` (`_EARTH_RADIUS_M`).
const _earthRadiusM = 6371000.0;

// spec Ruling 4 wants this cached from `GET /settings` at the last sync;
// deferred — Etapa 6 open point. The server re-validates with the real
// configured radius, so a stale local value only affects the auto-vs-picker
// choice, and a mismatch degrades to a review flag.
const _checkRadiusMeters = 50.0;

/// Haversine distance in metres between two `(lat, lng)` points. Ported
/// verbatim from `backend/app/domain/execution/geo.py` (`haversine_meters`)
/// so the offline room resolution here matches the server's spatial check
/// (spec Ruling 4). `haversineMeters(-7.21, -35.90, -7.21, -35.90) == 0.0`.
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  final phi1 = _radians(lat1);
  final phi2 = _radians(lat2);
  final dPhi = _radians(lat2 - lat1);
  final dLambda = _radians(lng2 - lng1);
  final sinPhi = math.sin(dPhi / 2);
  final sinLambda = math.sin(dLambda / 2);
  final a =
      sinPhi * sinPhi + math.cos(phi1) * math.cos(phi2) * sinLambda * sinLambda;
  return 2 * _earthRadiusM * math.asin(math.sqrt(a));
}

double _radians(double degrees) => degrees * math.pi / 180.0;

/// One PENDING route stop the offline check-in flow could be resolving to,
/// with its distance from the check-in GPS fix (`null` when GPS is
/// unavailable). Mirrors the backend's `validation.Candidate` — trimmed to
/// what the picker and the enqueue need (`RouteStopSummary` carries no
/// `service_point_id`).
class RoomCandidateLocal {
  const RoomCandidateLocal({
    required this.routeStopId,
    required this.servicePointName,
    this.distanceM,
  });

  final String routeStopId;
  final String servicePointName;

  /// Metres from the check-in GPS fix, or `null` when GPS was unavailable.
  final double? distanceM;
}

/// The outcome of resolving which room an offline check-in belongs to. Per
/// spec Ruling 4 / Ruling P8 there is no dead end: the flow always ends at a
/// concrete `route_stop_id`, either resolved automatically or picked by the
/// field worker.
sealed class RoomResolution {}

/// Exactly one plausible PENDING stop — check in against it with no prompt.
class ResolvedRoom extends RoomResolution {
  ResolvedRoom(this.routeStopId);

  final String routeStopId;
}

/// Two or more plausible PENDING stops — the field worker picks one. The
/// list is nearest-first (candidates with no distance come last).
class AmbiguousRooms extends RoomResolution {
  AmbiguousRooms(this.candidates);

  final List<RoomCandidateLocal> candidates;
}

/// Resolves the room for an offline check-in against [pendingStops] (all of
/// the route's `PENDING` stops — NOT floor-scoped, because neither
/// `RouteStopSummary` nor the backend's `RouteStopOut` carries a `floor_id`;
/// spec Ruling P3: the QR's Ed25519 signature already proved the floor, GPS
/// radius disambiguates, and the server re-runs the full floor-scoped
/// resolution plus all anti-fraud layers on sync and is authoritative).
///
/// Mirrors the SHAPE of `backend/app/domain/execution/validation.py`'s
/// `resolve_room`:
/// - exactly 1 stop within [_checkRadiusMeters] → [ResolvedRoom];
/// - 2+ within radius → [AmbiguousRooms] over those, nearest-first;
/// - 0 within radius (or no GPS) but exactly 1 PENDING stop on the whole
///   route → [ResolvedRoom] anyway (mirrors `validation.py:117`, "a single
///   candidate on the floor resolves anyway");
/// - 0 within radius (or no GPS) with 2+ PENDING stops → [AmbiguousRooms]
///   over ALL of them, nearest-first.
RoomResolution resolveRoomLocally({
  required List<RouteStopSummary> pendingStops,
  required double? latitude,
  required double? longitude,
}) {
  final hasGps = latitude != null && longitude != null;
  final candidates = [
    for (final stop in pendingStops)
      RoomCandidateLocal(
        routeStopId: stop.id,
        servicePointName: stop.servicePointName,
        distanceM: hasGps
            ? haversineMeters(
                latitude,
                longitude,
                stop.latitude,
                stop.longitude,
              )
            : null,
      ),
  ];

  final inRadius = candidates
      .where((c) => c.distanceM != null && c.distanceM! <= _checkRadiusMeters)
      .toList();
  if (inRadius.length == 1) return ResolvedRoom(inRadius.single.routeStopId);
  if (inRadius.length >= 2) return AmbiguousRooms(_nearestFirst(inRadius));

  // Nothing in radius, or no GPS at all. A lone PENDING stop still resolves
  // (validation.py:117); everything else is a pick over all pending stops.
  if (candidates.length == 1) {
    return ResolvedRoom(candidates.single.routeStopId);
  }
  return AmbiguousRooms(_nearestFirst(candidates));
}

/// Distance ascending, then service-point name — the same order as the
/// backend's `_sort_key` (no-distance candidates sort last via `+inf`).
List<RoomCandidateLocal> _nearestFirst(List<RoomCandidateLocal> candidates) {
  final sorted = [...candidates]
    ..sort((a, b) {
      final da = a.distanceM ?? double.infinity;
      final db = b.distanceM ?? double.infinity;
      final byDistance = da.compareTo(db);
      if (byDistance != 0) return byDistance;
      return a.servicePointName.compareTo(b.servicePointName);
    });
  return sorted;
}
