// The constructor forwards public named params to private fields: a private
// field can't be an initializing formal while its param name stays public,
// and these params stay public so callers and tests can inject fakes (same
// idiom as sync_worker.dart).
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';

import 'package:route_monitor/execution/room_resolution.dart'
    show haversineMeters;
import 'package:route_monitor/monitoring/monitoring_api.dart';
import 'package:route_monitor/monitoring/ongoing_notification.dart';
import 'package:route_monitor/routing/location_service.dart';

/// Builds the periodic timer that drives each report tick. Injected so tests
/// can capture the callback and fire ticks deterministically instead of
/// waiting on a real clock (docs/CLAUDE.md — Tests: "Nunca tocar (...) o
/// relógio (...) Injetar a costura (...) por parâmetro").
typedef PeriodicTimerFactory =
    Timer Function(Duration interval, void Function(Timer) onTick);

/// Reports the device's GPS position to the backend on a fixed interval while
/// a route is `IN_PROGRESS` (spec §2 Ruling 5, RNF11). Fire-and-forget: a
/// dropped fix does not matter — the next tick covers it — so this never
/// touches the outbox.
///
///     final reporter = PositionReporter(location: gps, api: monitoringApi)
///       ..start('route-1');
///     // ... later, when the route ends:
///     reporter.stop();
class PositionReporter {
  PositionReporter({
    required LocationService location,
    required MonitoringApi api,
    required OngoingNotification notification,
    Duration interval = const Duration(seconds: 60),
    PeriodicTimerFactory createTimer = Timer.periodic,
  }) : _location = location,
       _api = api,
       _notification = notification,
       _interval = interval,
       _createTimer = createTimer;

  final LocationService _location;
  final MonitoringApi _api;
  final OngoingNotification _notification;
  final Duration _interval;
  final PeriodicTimerFactory _createTimer;

  Timer? _timer;
  String? _routeId;

  /// RNF22 — battery saving while the worker is parked (cleaning one room
  /// takes ~30 min). A fix within [_stationaryRadiusM] of the last reported
  /// one means "still here": the next ticks are skipped without even waking
  /// the GPS, doubling the gap each time (1, 2, 4 min…) up to one fix every
  /// `interval * (_maxSkippedTicks + 1)` — 5 min at the default 60 s. Any
  /// real move resets to the base cadence.
  static const _stationaryRadiusM = 25.0;
  static const _maxSkippedTicks = 4;
  Coordinates? _lastReported;
  int _stationaryStreak = 0;
  int _ticksToSkip = 0;

  /// Starts reporting for [routeId]. A no-op if already running for the same
  /// route; restarts (new timer, new route) if running for a different one.
  void start(String routeId) {
    if (_timer != null && _routeId == routeId) return;
    stop();
    _routeId = routeId;
    _lastReported = null;
    _stationaryStreak = 0;
    _ticksToSkip = 0;
    _timer = _createTimer(_interval, (_) => unawaited(_tick()));
    // LGPD transparency (RNF11): the persistent notice goes up only when the
    // loop actually (re)starts, never on the same-route no-op above.
    unawaited(_notification.show());
  }

  /// Cancels the timer. Safe to call when not running.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _routeId = null;
    // Idempotent — safe when the loop was never running.
    unawaited(_notification.hide());
  }

  void dispose() => stop();

  void _adjustCadence(Coordinates position) {
    final previous = _lastReported;
    _lastReported = position;
    final parked =
        previous != null &&
        haversineMeters(
              previous.latitude,
              previous.longitude,
              position.latitude,
              position.longitude,
            ) <
            _stationaryRadiusM;
    _stationaryStreak = parked ? _stationaryStreak + 1 : 0;
    // Skipped ticks per streak: 1, 3, 4, 4… (capped).
    _ticksToSkip = parked
        ? math.min((1 << _stationaryStreak) - 1, _maxSkippedTicks)
        : 0;
  }

  Future<void> _tick() async {
    final routeId = _routeId;
    if (routeId == null) return;
    if (_ticksToSkip > 0) {
      _ticksToSkip--;
      return;
    }
    try {
      final position = await _location.getCurrentPosition(
        purpose: LocationPurpose.tracking,
      );
      await _api.reportPosition(
        routeId: routeId,
        latitude: position.latitude,
        longitude: position.longitude,
        reportedAt: DateTime.now().toUtc(),
      );
      _adjustCadence(position);
    } on DioException catch (error) {
      // 409 = the backend rejected the fix because the route is no longer the
      // worker's or no longer `IN_PROGRESS` (spec §2 Ruling 5) — reporting can
      // never succeed again for this route, so stop. Any other HTTP failure is
      // transient (auth blip, 5xx): swallow it and keep ticking.
      if (error.response?.statusCode == 409) stop();
    } on Object {
      // Transient GPS/permission/network error — swallow, the next tick
      // retries (fire-and-forget, spec §2 Ruling 5).
    }
  }
}
