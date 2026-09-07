import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/monitoring/monitoring_api.dart';
import 'package:route_monitor/monitoring/position_reporter.dart';
import 'package:route_monitor/routing/location_service.dart';

void main() {
  late _FakeLocationService location;
  late _RecordingMonitoringApi api;
  late _FakeTimer timer;

  setUp(() {
    location = _FakeLocationService();
    api = _RecordingMonitoringApi();
    timer = _FakeTimer();
  });

  PositionReporter build() =>
      PositionReporter(location: location, api: api, createTimer: timer.create);

  test(
    'each tick reports the current position for the started route',
    () async {
      build().start('r1');

      await timer.tick();
      await timer.tick();
      await timer.tick();

      expect(api.calls, hasLength(3));
      for (final call in api.calls) {
        expect(call.routeId, 'r1');
        expect(call.latitude, -7.21);
        expect(call.longitude, -35.90);
      }
    },
  );

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
}

class _FakeLocationService implements LocationService {
  Object? error;

  @override
  Future<Coordinates> getCurrentPosition() async {
    // ignore: only_throw_errors — a fake replaying whatever the test injects.
    if (error != null) throw error!;
    return const Coordinates(latitude: -7.21, longitude: -35.90);
  }
}

class _ReportCall {
  _ReportCall({
    required this.routeId,
    required this.latitude,
    required this.longitude,
  });
  final String routeId;
  final double latitude;
  final double longitude;
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
      _ReportCall(routeId: routeId, latitude: latitude, longitude: longitude),
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

  Timer create(Duration interval, void Function(Timer) onTick) {
    createdCount++;
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
