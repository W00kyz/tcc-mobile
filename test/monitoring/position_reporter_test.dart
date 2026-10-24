import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/monitoring/location_mode.dart';
import 'package:route_monitor/monitoring/monitoring_api.dart';
import 'package:route_monitor/monitoring/ongoing_notification.dart';
import 'package:route_monitor/monitoring/position_reporter.dart';
import 'package:route_monitor/monitoring/position_source.dart';
import 'package:route_monitor/routing/location_service.dart';

void main() {
  late _FakeLocationService location;
  late _RecordingMonitoringApi api;
  late _FakeTimer timer;
  late _FakeOngoingNotification notification;
  late _FakePositionSource positions;
  late List<DateTime> sent;
  final sentAt = DateTime.utc(2026, 10, 20, 9, 15);

  setUp(() {
    location = _FakeLocationService();
    api = _RecordingMonitoringApi();
    timer = _FakeTimer();
    notification = _FakeOngoingNotification();
    positions = _FakePositionSource();
    sent = [];
  });

  PositionReporter build() => PositionReporter(
    location: location,
    positionSource: positions,
    api: api,
    notification: notification,
    onPositionSent: sent.add,
    now: () => sentAt,
    createTimer: timer.create,
  );

  test(
    'each tick reports the current position while the worker moves',
    () async {
      location.route = [
        const Coordinates(latitude: -7.21, longitude: -35.90),
        const Coordinates(latitude: -7.211, longitude: -35.90),
        const Coordinates(latitude: -7.212, longitude: -35.90),
      ];
      build().start('r1');

      await timer.tick();
      await timer.tick();
      await timer.tick();

      expect(api.calls, hasLength(3));
      for (final call in api.calls) {
        expect(call.routeId, 'r1');
        expect(call.longitude, -35.90);
      }
      expect(api.calls.map((call) => call.latitude), [-7.21, -7.211, -7.212]);
      // RNF22: the long-running in-route stream asks for the battery-sparing
      // `tracking` accuracy, never the one-shot check-in profile.
      expect(location.lastPurpose, LocationPurpose.tracking);
    },
  );

  test(
    'a parked worker is sampled less and less often (RNF22)',
    () async {
      // Same spot every time: report, skip 1, report, skip 3, report, skip 4…
      build().start('r1');

      for (var i = 0; i < 12; i++) {
        await timer.tick();
      }

      expect(location.fixes, 4);
      expect(api.calls, hasLength(4));
    },
  );

  test('moving again restores the base cadence (RNF22)', () async {
    build().start('r1');
    await timer.tick(); // first fix
    await timer.tick(); // same spot → skip the next tick
    await timer.tick(); // skipped
    location.route = [
      const Coordinates(latitude: -7.22, longitude: -35.90),
      const Coordinates(latitude: -7.23, longitude: -35.90),
    ];

    await timer.tick(); // moved ~1.1 km
    await timer.tick(); // moved again — no skip in between

    expect(location.fixes, 4);
  });

  test('stop() cancels the timer — no further reports', () async {
    final reporter = build()..start('r1');
    await timer.tick();
    expect(api.calls, hasLength(1));

    reporter.stop();

    expect(timer.cancelled, isTrue);
    expect(timer.tickCallback, isNull);
  });

  test('start() for the same route is a no-op (keeps the running timer)', () {
    final reporter = build()..start('r1');
    final firstCallback = timer.tickCallback;

    reporter.start('r1');

    expect(identical(timer.tickCallback, firstCallback), isTrue);
    expect(timer.createdCount, 1);
  });

  test(
    'start() for a different route restarts against the new route',
    () async {
      build()
        ..start('r1')
        ..start('r2');
      await timer.tick();

      expect(timer.createdCount, 2);
      expect(api.calls.single.routeId, 'r2');
    },
  );

  test('a generic API error is swallowed — the timer keeps ticking', () async {
    api.error = StateError('boom');
    build().start('r1');

    await timer.tick();
    await timer.tick();

    expect(api.attempts, 2);
    expect(timer.cancelled, isFalse);
  });

  test('a 409 stops the reporter (route no longer IN_PROGRESS)', () async {
    api.error = DioException(
      requestOptions: RequestOptions(path: '/worker-positions'),
      response: Response<void>(
        requestOptions: RequestOptions(path: '/worker-positions'),
        statusCode: 409,
      ),
    );
    build().start('r1');

    await timer.tick();

    expect(timer.cancelled, isTrue);
  });

  test(
    'a non-409 DioException is swallowed — the timer keeps ticking',
    () async {
      api.error = DioException(
        requestOptions: RequestOptions(path: '/worker-positions'),
        response: Response<void>(
          requestOptions: RequestOptions(path: '/worker-positions'),
          statusCode: 503,
        ),
      );
      build().start('r1');

      await timer.tick();

      expect(timer.cancelled, isFalse);
    },
  );

  test('a location failure is swallowed — the timer keeps ticking', () async {
    location.error = StateError('GPS denied');
    build().start('r1');

    await timer.tick();

    expect(api.attempts, 0);
    expect(timer.cancelled, isFalse);
  });

  test('start() posts the ongoing collection notice (RNF11)', () {
    build().start('r1');

    expect(notification.shows, 1);
  });

  test('start() for the same route does not re-post the notice', () {
    build()
      ..start('r1')
      ..start('r1');

    expect(notification.shows, 1);
  });

  test('stop() cancels the ongoing collection notice', () {
    build()
      ..start('r1')
      ..stop();

    expect(notification.hides, greaterThanOrEqualTo(1));
  });

  test('a 409 on a tick stops the reporter and cancels the notice', () async {
    api.error = DioException(
      requestOptions: RequestOptions(path: '/worker-positions'),
      response: Response<void>(
        requestOptions: RequestOptions(path: '/worker-positions'),
        statusCode: 409,
      ),
    );
    build().start('r1');

    await timer.tick();

    expect(timer.cancelled, isTrue);
    expect(notification.hides, greaterThanOrEqualTo(1));
  });

  test('foregroundOnly ticks on the interval the server sent', () {
    build().start('r1', interval: const Duration(seconds: 90));

    expect(timer.lastInterval, const Duration(seconds: 90));
    expect(positions.watchedInterval, isNull);
  });

  test('a successful foreground send records when it was sent', () async {
    build().start('r1');

    await timer.tick();
    expect(sent, [sentAt]);
    expect(api.calls.single.reportedAt, sentAt);

    api.error = StateError('no signal');
    await timer.tick();
    expect(sent, [sentAt]);
  });

  group('background mode', () {
    PositionReporter startBackground() => build()
      ..start(
        'r1',
        mode: LocationMode.background,
        interval: const Duration(seconds: 30),
      );

    test('posts each fix of the position stream, no timer', () async {
      startBackground();

      expect(positions.watchedInterval, const Duration(seconds: 30));
      expect(timer.createdCount, 0);

      await positions.emit(
        const Coordinates(latitude: -7.21, longitude: -35.9),
      );
      await positions.emit(
        const Coordinates(latitude: -7.21, longitude: -35.9),
      );

      // Every fix, even parked: the stream already keeps the GPS awake, and a
      // skipped fix would only bring the silence release closer.
      expect(api.calls.map((call) => call.latitude), [-7.21, -7.21]);
      expect(api.calls.first.routeId, 'r1');
      expect(sent, [sentAt, sentAt]);
    });

    test('the service notification replaces the in-app ongoing one', () {
      startBackground();

      expect(notification.shows, 0);
    });

    test('a failed send is swallowed and records nothing', () async {
      startBackground();
      api.error = StateError('no signal');

      await positions.emit(
        const Coordinates(latitude: -7.21, longitude: -35.9),
      );

      expect(sent, isEmpty);
      expect(positions.cancelled, isFalse);
    });

    test('a stream error is swallowed — the stream keeps going', () async {
      startBackground();

      await positions.fail(StateError('GPS off'));
      await positions.emit(
        const Coordinates(latitude: -7.21, longitude: -35.9),
      );

      expect(api.calls, hasLength(1));
    });

    test('a 409 stops the stream', () async {
      startBackground();
      api.error = DioException(
        requestOptions: RequestOptions(path: '/worker-positions'),
        response: Response<void>(
          requestOptions: RequestOptions(path: '/worker-positions'),
          statusCode: 409,
        ),
      );

      await positions.emit(
        const Coordinates(latitude: -7.21, longitude: -35.9),
      );

      expect(positions.cancelled, isTrue);
    });

    test('stop() cancels the stream', () {
      startBackground().stop();

      expect(positions.cancelled, isTrue);
    });

    test('switching mode on the same route restarts the loop', () {
      startBackground().start('r1');

      expect(positions.cancelled, isTrue);
      expect(timer.createdCount, 1);
      expect(notification.shows, 1);
    });
  });
}

/// Records `show`/`hide` calls so a test can assert the persistent
/// location-collection notice tracks the reporter's lifecycle (RNF11).
class _FakeOngoingNotification implements OngoingNotification {
  int shows = 0;
  int hides = 0;

  @override
  Future<void> show() async => shows++;

  @override
  Future<void> hide() async => hides++;
}

class _FakeLocationService implements LocationService {
  Object? error;
  LocationPurpose? lastPurpose;
  int fixes = 0;

  /// Fixes handed out in order; once exhausted (or never set) the worker
  /// stays parked at the default spot.
  List<Coordinates> route = [];

  @override
  Future<Coordinates> getCurrentPosition({
    required LocationPurpose purpose,
  }) async {
    lastPurpose = purpose;
    fixes++;
    // ignore: only_throw_errors — a fake replaying whatever the test injects.
    if (error != null) throw error!;
    if (route.isNotEmpty) return route.removeAt(0);
    return const Coordinates(latitude: -7.21, longitude: -35.90);
  }
}

class _ReportCall {
  _ReportCall({
    required this.routeId,
    required this.latitude,
    required this.longitude,
    required this.reportedAt,
  });
  final String routeId;
  final double latitude;
  final double longitude;
  final DateTime reportedAt;
}

class _RecordingMonitoringApi implements MonitoringApi {
  final List<_ReportCall> calls = [];
  int attempts = 0;
  Object? error;

  @override
  Future<void> reportPosition({
    required String routeId,
    required double latitude,
    required double longitude,
    required DateTime reportedAt,
    double? accuracyM,
  }) async {
    attempts++;
    // ignore: only_throw_errors — a fake replaying whatever the test injects.
    if (error != null) throw error!;
    calls.add(
      _ReportCall(
        routeId: routeId,
        latitude: latitude,
        longitude: longitude,
        reportedAt: reportedAt,
      ),
    );
  }

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

/// Captures the callback [PositionReporter] hands to `Timer.periodic` so a
/// test can fire ticks synchronously instead of waiting on a real clock.
class _FakeTimer {
  void Function(Timer)? tickCallback;
  int createdCount = 0;
  bool cancelled = false;
  Duration? lastInterval;

  Timer create(Duration interval, void Function(Timer) onTick) {
    createdCount++;
    lastInterval = interval;
    cancelled = false;
    tickCallback = onTick;
    return _NoopTimer(
      onCancel: () {
        cancelled = true;
        tickCallback = null;
      },
    );
  }

  /// Runs one tick and drains the microtask queue so the async `_tick`
  /// completes before the test asserts.
  Future<void> tick() async {
    tickCallback?.call(_NoopTimer());
    await Future<void>.delayed(Duration.zero);
  }
}

class _NoopTimer implements Timer {
  _NoopTimer({this.onCancel});
  final void Function()? onCancel;

  @override
  void cancel() => onCancel?.call();

  @override
  bool get isActive => true;

  @override
  int get tick => 0;
}

/// Hands the reporter a stream the test drives fix by fix, standing in for
/// the Android foreground-service stream.
class _FakePositionSource implements PositionSource {
  final _fixes = StreamController<Coordinates>();
  Duration? watchedInterval;
  bool cancelled = false;

  @override
  Stream<Coordinates> watch({required Duration interval}) {
    watchedInterval = interval;
    _fixes.onCancel = () => cancelled = true;
    return _fixes.stream;
  }

  Future<void> emit(Coordinates fix) async {
    _fixes.add(fix);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> fail(Object error) async {
    _fixes.addError(error);
    await Future<void>.delayed(Duration.zero);
  }
}
