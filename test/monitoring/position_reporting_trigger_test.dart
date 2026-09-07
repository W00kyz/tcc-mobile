import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/monitoring/monitoring_api.dart';
import 'package:route_monitor/monitoring/monitoring_providers.dart';
import 'package:route_monitor/monitoring/position_reporter.dart';
import 'package:route_monitor/monitoring/position_reporting_trigger.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';

void main() {
  late _SpyReporter reporter;
  late ProviderContainer container;
  late List<RouteSummary> currentRoutes;

  setUp(() {
    reporter = _SpyReporter();
    currentRoutes = const [];
    container = ProviderContainer(
      overrides: [
        positionReporterProvider.overrideWithValue(reporter),
        myRoutesProvider.overrideWith((ref) async => currentRoutes),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> pump(WidgetTester tester) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: PositionReportingTrigger(child: SizedBox.shrink()),
        ),
      ),
    );
  }

  void setRoutes(List<RouteSummary> routes) {
    currentRoutes = routes;
    container.invalidate(myRoutesProvider);
  }

  testWidgets('starts the reporter for an IN_PROGRESS route', (tester) async {
    setRoutes([_route('r1', 'IN_PROGRESS')]);
    await pump(tester);
    await tester.pumpAndSettle();

    expect(reporter.started, ['r1']);
  });

  testWidgets('stops the reporter when no route is IN_PROGRESS', (
    tester,
  ) async {
    setRoutes([_route('r1', 'PLANNED')]);
    await pump(tester);
    await tester.pumpAndSettle();

    expect(reporter.started, isEmpty);
    expect(reporter.stopCount, greaterThanOrEqualTo(1));
  });

  testWidgets('stops the reporter once the route leaves IN_PROGRESS', (
    tester,
  ) async {
    setRoutes([_route('r1', 'IN_PROGRESS')]);
    await pump(tester);
    await tester.pumpAndSettle();
    expect(reporter.started, ['r1']);

    setRoutes([_route('r1', 'DONE')]);
    await tester.pumpAndSettle();

    expect(reporter.stopCount, greaterThanOrEqualTo(1));
  });
}

RouteSummary _route(String id, String status) => RouteSummary(
  id: id,
  fieldWorkerName: 'Ana',
  routeDate: DateTime.utc(2026, 9, 7),
  routeType: 'DAILY',
  status: status,
  startedAt: null,
  stops: const [],
);

class _SpyReporter extends PositionReporter {
  _SpyReporter() : super(location: _NullLocation(), api: _NullApi());

  final List<String> started = [];
  int stopCount = 0;

  @override
  void start(String routeId) => started.add(routeId);

  @override
  void stop() => stopCount++;
}

class _NullLocation implements LocationService {
  @override
  Future<Coordinates> getCurrentPosition() async =>
      const Coordinates(latitude: 0, longitude: 0);
}

class _NullApi implements MonitoringApi {
  @override
  Future<void> reportPosition({
    required String routeId,
    required double latitude,
    required double longitude,
    required DateTime reportedAt,
    double? accuracyM,
  }) async {}
}
