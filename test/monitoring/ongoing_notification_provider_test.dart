import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/monitoring/monitoring_providers.dart';
import 'package:route_monitor/monitoring/ongoing_notification.dart';

void main() {
  test(
    'ongoingNotificationProvider builds the real LocalOngoingNotification',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(ongoingNotificationProvider),
        isA<LocalOngoingNotification>(),
      );
    },
  );
}
