import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/monitoring/monitoring_api.dart';
import 'package:route_monitor/monitoring/monitoring_providers.dart';
import 'package:route_monitor/monitoring/ongoing_notification.dart';
import 'package:route_monitor/monitoring/position_reporter.dart';
import 'package:route_monitor/monitoring/position_reporting_trigger.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';

import '../support/fake_route_repository.dart';

void main() {
  late _SpyReporter reporter;
  late ProviderContainer container;
  late RouteSummary? currentRoute;

  setUp(() {
    reporter = _SpyReporter();
    currentRoute = null;
    container = ProviderContainer(
      overrides: [
        positionReporterProvider.overrideWithValue(reporter),
        myDayProvider.overrideWith((ref) async => myDayWith(currentRoute)),
        sessionProvider.overrideWithBuild((ref, notifier) => _session()),
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

  void setRoute(RouteSummary? route) {
    currentRoute = route;
    container.invalidate(myDayProvider);
  }

  testWidgets('starts the reporter for an IN_PROGRESS route', (tester) async {
    setRoute(_route('IN_PROGRESS'));
    await pump(tester);
    await tester.pumpAndSettle();

    expect(reporter.started, ['r1']);
  });

  testWidgets('stops the reporter before the first batch of the day', (
    tester,
  ) async {
    setRoute(null);
    await pump(tester);
    await tester.pumpAndSettle();

    expect(reporter.started, isEmpty);
    expect(reporter.stopCount, greaterThanOrEqualTo(1));
  });

  testWidgets('stops the reporter once the route leaves IN_PROGRESS', (
    tester,
  ) async {
    setRoute(_route('IN_PROGRESS'));
    await pump(tester);
    await tester.pumpAndSettle();
    expect(reporter.started, ['r1']);

    setRoute(_route('DONE'));
    await tester.pumpAndSettle();

    expect(reporter.stopCount, greaterThanOrEqualTo(1));
    // Auto-stop tears down the persistent collection notice too (RNF11).
    expect(reporter.notification.hides, greaterThanOrEqualTo(1));
  });

  testWidgets(
    'never starts the reporter while the session still owes consent (RNF10)',
    (tester) async {
      currentRoute = _route('IN_PROGRESS');
      container = ProviderContainer(
        overrides: [
          positionReporterProvider.overrideWithValue(reporter),
          myDayProvider.overrideWith((ref) async => myDayWith(currentRoute)),
          sessionProvider.overrideWithBuild(
            (ref, notifier) => _session(consentRequired: true),
          ),
        ],
      );
      addTearDown(container.dispose);

      await pump(tester);
      await tester.pumpAndSettle();

      expect(reporter.started, isEmpty);
      expect(reporter.stopCount, greaterThanOrEqualTo(1));
    },
  );

  // The `if (day == null) return child;` guard is the load-bearing
  // login-screen-crash guard: with no successful day, the widget must
  // NOT touch `positionReporterProvider` (it reads `API_BASE_URL`, unset on the
  // login screen). Here `positionReporterProvider` is deliberately left
  // un-overridden and pointed at a builder that throws, so any read fails.
  for (final state in ['error', 'loading']) {
    testWidgets(
      'renders child without reading the reporter ($state day)',
      (
        tester,
      ) async {
        final guardContainer = ProviderContainer(
          // No backoff retry timer left pending when the error branch throws.
          retry: (_, _) => null,
          overrides: [
            positionReporterProvider.overrideWith(
              (ref) =>
                  throw StateError('positionReporterProvider must not be read'),
            ),
            myDayProvider.overrideWith((ref) async {
              if (state == 'error') throw Exception('logged out');
              return Completer<MyDay>().future;
            }),
          ],
        );
        addTearDown(guardContainer.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: guardContainer,
            child: const Directionality(
              textDirection: TextDirection.ltr,
              child: PositionReportingTrigger(
                child: Text('guarded-child'),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('guarded-child'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Session _session({bool consentRequired = false}) => Session(
  accessToken: 'a-test-token',
  refreshToken: 'a-refresh-token',
  role: 'FIELD_WORKER',
  consentRequired: consentRequired,
);

RouteSummary _route(String status) => routeWith(status: status, stops: []);

class _SpyReporter extends PositionReporter {
  _SpyReporter()
    : notification = _FakeOngoingNotification(),
      super(
        location: _NullLocation(),
        api: _NullApi(),
        notification: _FakeOngoingNotification(),
      );

  final _FakeOngoingNotification notification;
  final List<String> started = [];
  int stopCount = 0;

  @override
  void start(String routeId) {
    started.add(routeId);
    unawaited(notification.show());
  }

  @override
  void stop() {
    stopCount++;
    unawaited(notification.hide());
  }
}

class _FakeOngoingNotification implements OngoingNotification {
  int hides = 0;

  @override
  Future<void> show() async {}

  @override
  Future<void> hide() async => hides++;
}

class _NullLocation implements LocationService {
  @override
  Future<Coordinates> getCurrentPosition({
    required LocationPurpose purpose,
  }) async => const Coordinates(latitude: 0, longitude: 0);
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

  @override
  Future<List<AppNotification>> fetchNotifications({int limit = 30}) async {
    throw UnimplementedError();
  }

  @override
  Future<int> unreadCount() async => throw UnimplementedError();

  @override
  Future<void> markRead(String id) async {
    throw UnimplementedError();
  }
}
