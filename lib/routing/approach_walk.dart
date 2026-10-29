import 'package:latlong2/latlong.dart';
import 'package:route_monitor/routing/campus_map.dart';

// The off-road ends of the live first leg: OSRM snaps a street path's ends
// to the nearest mapped road, and the campus paths between buildings are not
// in the map data, so the worker and the stop are bridged on foot, dashed.

/// Below this a snapped end is on the spot: no walk is drawn.
const double _walkGapM = 5;

/// The walk between [spot] and the street path's start ([toStart]) or end;
/// null without a spot or when the gap is under [_walkGapM] (a straight hop
/// already starts at the worker).
///
///     approachWalk(worker, street, toStart: true); // worker → street start
RouteMapLeg? approachWalk(
  LatLng? spot,
  List<LatLng> street, {
  required bool toStart,
}) {
  if (spot == null || street.length < 2) return null;
  final end = toStart ? street.first : street.last;
  if (const Distance()(spot, end) < _walkGapM) return null;
  return RouteMapLeg(
    points: toStart ? [spot, end] : [end, spot],
    approximate: true,
    kind: LegKind.next,
    walk: true,
  );
}
