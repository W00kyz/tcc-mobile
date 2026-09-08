import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:route_monitor/routing/location_service.dart';

void main() {
  group('locationSettingsFor', () {
    test('checkin asks for the highest accuracy and no distance filter', () {
      final settings = locationSettingsFor(LocationPurpose.checkin);

      expect(settings.accuracy, LocationAccuracy.high);
      expect(settings.distanceFilter, 0);
    });

    test('tracking trades accuracy for a 25 m filter to spare battery', () {
      final settings = locationSettingsFor(LocationPurpose.tracking);

      expect(settings.accuracy, LocationAccuracy.medium);
      expect(settings.distanceFilter, 25);
    });
  });
}
