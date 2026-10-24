import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/monitoring/location_mode.dart';
import 'package:route_monitor/monitoring/monitoring_api.dart';
import 'package:route_monitor/monitoring/monitoring_providers.dart';
import 'package:route_monitor/monitoring/ongoing_notification.dart';
import 'package:route_monitor/monitoring/position_reporter.dart';
import 'package:route_monitor/monitoring/position_reporting_trigger.dart';
import 'package:route_monitor/monitoring/position_source.dart';
import 'package:route_monitor/monitoring/silence_watchdog.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';

import '../support/fake_route_repository.dart';

void main() {
  late _SpyReporter reporter;
  late ProviderContainer container;
  late RouteSummary? currentRoute;
  late LocationMode locationMode;
  late _RecordingScheduler scheduler;
  late SilenceWatchdog watchdog;

  setUp(() {
    reporter = _SpyReporter();
    currentRoute = null;
    locationMode = LocationMode.foregroundOnly;
    scheduler = _RecordingScheduler();
    watchdog = SilenceWatchdog(
      clock: () => DateTime.utc(2026, 10, 20, 8),
      scheduler: scheduler,
      warningMinutes: 30,
      releaseMinutes: 45,
    );
    container = ProviderContainer(
      overrides: [
        positionReporterProvider.overrideWithValue(reporter),
        myDayProvider.overrideWith((ref) async => myDayWith(currentRoute)),
        sessionProvider.overrideWithBuild((ref, notifier) => _session()),
        locationModeProvider.overrideWith((ref) async => locationMode),
        silenceWatchdogProvider.overrideWithValue(watchdog),
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
    expect(reporter.modes, [LocationMode.foregroundOnly]);
    // `position_report_interval_seconds` from `GET /routes/me`.
    expect(reporter.intervals, [const Duration(seconds: 60)]);
  });

  testWidgets('starts in background mode when "always" is granted', (
    tester,
  ) async {
    locationMode = LocationMode.background;
    setRoute(_route('IN_PROGRESS'));
    await pump(tester);
    await tester.pumpAndSettle();

    expect(reporter.modes, [LocationMode.background]);
  });

  testWidgets('watches the silence clock while the route is IN_PROGRESS', (
    tester,
  ) async {
    setRoute(_route('IN_PROGRESS'));
    await pump(tester);
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(scheduler.scheduled, [DateTime.utc(2026, 10, 20, 8, 30)]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(scheduler.cancelled, [SilenceWatchdog.notificationId]);
  });

  testWidgets('stops the silence clock once the route leaves IN_PROGRESS', (
    tester,
  ) async {
    setRoute(_route('IN_PROGRESS'));
    await pump(tester);
    await tester.pumpAndSettle();

    setRoute(_route('PAUSED'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    expect(scheduler.scheduled, isEmpty);
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
          locationModeProvider.overrideWith((ref) async => locationMode),
          silenceWatchdogProvider.overrideWithValue(watchdog),
        ],
      );
      addTearDown(container.dispose);

      await pump(tester);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

      expect(reporter.started, isEmpty);
      expect(reporter.stopCount, greaterThanOrEqualTo(1));
      expect(scheduler.scheduled, isEmpty);
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
        positionSource: _NullPositionSource(),
        api: _NullApi(),
        notification: _FakeOngoingNotification(),
      );

  final _FakeOngoingNotification notification;
  final List<String> started = [];
  final List<LocationMode> modes = [];
  final List<Duration> intervals = [];
  int stopCount = 0;

  @override
  void start(
    String routeId, {
    LocationMode mode = LocationMode.foregroundOnly,
    Duration interval = const Duration(seconds: 60),
  }) {
    started.add(routeId);
    modes.add(mode);
    intervals.add(interval);
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

class _NullPositionSource implements PositionSource {
  @override
  Stream<Coordinates> watch({required Duration interval}) =>
      const Stream.empty();
}

class _RecordingScheduler implements LocalScheduler {
  final List<DateTime> scheduled = [];
  final List<int> cancelled = [];

  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async => scheduled.add(at);

  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}
