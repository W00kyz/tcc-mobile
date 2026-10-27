import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/execution/execution_providers.dart'
    show apiBaseUrlProvider;
import 'package:route_monitor/monitoring/location_mode.dart';
import 'package:route_monitor/monitoring/monitoring_providers.dart';
import 'package:route_monitor/monitoring/ongoing_notification.dart';
import 'package:route_monitor/monitoring/position_reporting_trigger.dart';
import 'package:route_monitor/monitoring/position_source.dart';
import 'package:route_monitor/monitoring/silence_watchdog.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_providers.dart';

import '../support/fake_route_repository.dart';

/// The background-mode path with the screen locked: no widget builds, the
/// providers alone must keep the stream and the warning alive (spec
/// 2026-10-20-alocacao-automatica §7.3). The real `monitoringApiProvider`,
/// `positionReporterProvider` and `silenceWatchdogProvider` run here; only
/// the platform seams are faked.
void main() {
  late _FakePositionSource positions;
  late _RecordingScheduler scheduler;
  late FakeRouteRepository repository;
  late ProviderContainer container;

  setUp(() {
    positions = _FakePositionSource();
    scheduler = _RecordingScheduler();
    repository = FakeRouteRepository(
      myDayWith(routeWith(stops: [])),
    );
    container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(() => _TestSession(_session(1))),
        apiBaseUrlProvider.overrideWithValue('http://test-base'),
        // Like the real one, rebuilt on every session change — so a token
        // refresh reloads the day.
        routeRepositoryProvider.overrideWith((ref) {
          ref.watch(sessionProvider);
          return repository;
        }),
        locationModeProvider.overrideWith(
          (ref) async => LocationMode.background,
        ),
        positionSourceProvider.overrideWithValue(positions),
        locationServiceProvider.overrideWithValue(_NullLocation()),
        ongoingNotificationProvider.overrideWithValue(_NullNotification()),
        localSchedulerProvider.overrideWithValue(scheduler),
      ],
    );
    addTearDown(container.dispose);
    container.listen(positionReportingProvider, (_, _) {});
  });

  void refreshSession(Session? next) =>
      (container.read(sessionProvider.notifier) as _TestSession).refreshTo(
        next,
      );

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Route IN_PROGRESS, background stream up, app in the background.
  Future<SilenceWatchdog> lockedScreen() async {
    await settle();
    expect(positions.watchCount, 1);
    final watchdog = container.read(silenceWatchdogProvider)!..onAppPaused();
    expect(scheduler.scheduled, hasLength(1));
    return watchdog;
  }

  test('a token refresh while paused keeps the stream subscribed', () async {
    await lockedScreen();

    refreshSession(_session(2));
    await settle();

    expect(positions.cancelled, isFalse);
    expect(positions.watchCount, 1);
  });

  test('a token refresh while paused keeps the warning scheduled', () async {
    final watchdog = await lockedScreen();

    refreshSession(_session(2));
    await settle();

    expect(scheduler.cancelled, isEmpty);
    expect(
      identical(container.read(silenceWatchdogProvider), watchdog),
      isTrue,
    );
  });

  test('a day reload, even a failed one, does not stop the watchdog', () async {
    final watchdog = await lockedScreen();

    repository.fetchError = Exception('no signal');
    container.invalidate(myDayProvider);
    await settle();

    expect(scheduler.cancelled, isEmpty);
    expect(
      identical(container.read(silenceWatchdogProvider), watchdog),
      isTrue,
    );
    expect(positions.cancelled, isFalse);
  });

  test('a route going IN_PROGRESS starts reporting with no widget', () async {
    repository.day = myDayWith(routeWith(status: 'PAUSED', stops: []));
    container.invalidate(myDayProvider);
    await settle();
    expect(positions.watchCount, 0);

    repository.day = myDayWith(routeWith(stops: []));
    container.invalidate(myDayProvider);
    await settle();

    expect(positions.watchCount, 1);
  });

  test('signing out stops the stream and the warning', () async {
    await lockedScreen();

    refreshSession(null);
    await settle();

    expect(positions.cancelled, isTrue);
    expect(scheduler.cancelled, [SilenceWatchdog.notificationId]);
  });
}

/// A session whose access token is a readable JWT for the same user, issued
/// at [issuedAt] — what a refresh hands back.
Session _session(int issuedAt) {
  String part(Map<String, Object> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final token =
      '${part({'alg': 'HS256'})}.${part({'sub': 'u1', 'iat': issuedAt})}.sig';
  return Session(accessToken: token, refreshToken: 'r', role: 'FIELD_WORKER');
}

class _TestSession extends SessionNotifier {
  _TestSession(this._initial);

  final Session _initial;

  @override
  Session? build() => _initial;

  // A method, not a setter: it stands for the refresh the real notifier
  // performs.
  // ignore: use_setters_to_change_properties
  void refreshTo(Session? next) => state = next;
}

class _FakePositionSource implements PositionSource {
  final _fixes = StreamController<Coordinates>();
  int watchCount = 0;
  bool cancelled = false;

  @override
  Stream<Coordinates> watch({required Duration interval}) {
    watchCount++;
    _fixes.onCancel = () => cancelled = true;
    return _fixes.stream;
  }
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

class _NullLocation implements LocationService {
  @override
  Future<Coordinates> getCurrentPosition({
    required LocationPurpose purpose,
  }) async => const Coordinates(latitude: 0, longitude: 0);
}

class _NullNotification implements OngoingNotification {
  @override
  Future<void> show() async {}

  @override
  Future<void> hide() async {}
}
