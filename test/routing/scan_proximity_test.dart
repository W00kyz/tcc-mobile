import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_monitor/routing/scan_proximity.dart';

void main() {
  const building = LatLng(-7.2175, -35.9094);
  LatLng northOf(double meters) => const Distance().offset(building, meters, 0);

  test('no GPS fix counts as near', () {
    expect(isNearBuilding(null, building), isTrue);
  });

  test('79 m away is near', () {
    expect(isNearBuilding(northOf(79), building), isTrue);
  });

  test('81 m away is not near', () {
    expect(isNearBuilding(northOf(81), building), isFalse);
  });

  test('standing on the building is near', () {
    expect(isNearBuilding(building, building), isTrue);
  });

  test('the threshold is 80 m', () {
    expect(kScanProximityMeters, 80);
  });
}
