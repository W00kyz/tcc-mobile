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
import 'package:route_monitor/monitoring/location_mode.dart';
import 'package:route_monitor/monitoring/monitoring_api.dart';
import 'package:route_monitor/monitoring/ongoing_notification.dart';
import 'package:route_monitor/monitoring/position_source.dart';
import 'package:route_monitor/routing/location_service.dart';

/// Builds the periodic timer that drives each report tick. Injected so tests
/// can capture the callback and fire ticks deterministically instead of
/// waiting on a real clock (docs/CLAUDE.md — Tests: "Nunca tocar (...) o
/// relógio (...) Injetar a costura (...) por parâmetro").
typedef PeriodicTimerFactory =
    Timer Function(Duration interval, void Function(Timer) onTick);

/// Reports the device's GPS position to the backend while a route is
/// `IN_PROGRESS` (spec §2 Ruling 5, RNF11), in one of two modes (spec
/// 2026-10-20-alocacao-automatica §7.3): [LocationMode.foregroundOnly] asks
/// for a fix on a timer, [LocationMode.background] posts each fix of the
/// [PositionSource] stream (an Android foreground service, screen locked).
/// Fire-and-forget: a dropped fix does not matter — the next one covers it —
/// so this never touches the outbox. Every successful send is handed to
/// `onPositionSent` (the silence watchdog's activity).
///
///     final reporter = PositionReporter(
///       location: gps,
///       positionSource: stream,
///       api: monitoringApi,
///       notification: notice,
///     )..start('route-1', mode: LocationMode.background);
///     // ... later, when the route ends:
///     reporter.stop();
class PositionReporter {
  PositionReporter({
    required LocationService location,
    required PositionSource positionSource,
    required MonitoringApi api,
    required OngoingNotification notification,
    void Function(DateTime sentAt)? onPositionSent,
    DateTime Function() now = DateTime.now,
    PeriodicTimerFactory createTimer = Timer.periodic,
  }) : _location = location,
       _positionSource = positionSource,
       _api = api,
       _notification = notification,
       _onPositionSent = onPositionSent,
       _now = now,
       _createTimer = createTimer;

  final LocationService _location;
  final PositionSource _positionSource;
  final MonitoringApi _api;
  final OngoingNotification _notification;
  final void Function(DateTime sentAt)? _onPositionSent;
  final DateTime Function() _now;
  final PeriodicTimerFactory _createTimer;

  Timer? _timer;
  StreamSubscription<Coordinates>? _stream;
  String? _routeId;
  LocationMode? _mode;
  Duration? _interval;

  /// RNF22 — battery saving while the worker is parked (cleaning one room
  /// takes ~30 min). A fix within [_stationaryRadiusM] of the last reported
  /// one means "still here": the next ticks are skipped without even waking
  /// the GPS, doubling the gap each time (1, 2, 4 min…) up to one fix every
  /// `interval * (_maxSkippedTicks + 1)` — 5 min at the default 60 s. Any
  /// real move resets to the base cadence. Foreground mode only: the
  /// background stream keeps the GPS awake regardless.
  static const _stationaryRadiusM = 25.0;
  static const _maxSkippedTicks = 4;
  Coordinates? _lastReported;
  int _stationaryStreak = 0;
  int _ticksToSkip = 0;

  /// Starts reporting for [routeId] in [mode], every [interval] (the
  /// server's `position_report_interval_seconds`). A no-op if already running
  /// the same way; restarts otherwise (another route, mode or interval).
  void start(
    String routeId, {
    LocationMode mode = LocationMode.foregroundOnly,
    Duration interval = const Duration(seconds: 60),
  }) {
    final running = _timer != null || _stream != null;
    if (running &&
        _routeId == routeId &&
        _mode == mode &&
        _interval == interval) {
      return;
    }
    stop();
    _routeId = routeId;
    _mode = mode;
    _interval = interval;
    if (mode == LocationMode.background) {
      // The foreground service posts its own fixed notification, which
      // replaces the in-app ongoing one (LGPD transparency either way).
      _stream = _positionSource
          .watch(interval: interval)
          .listen(
            (fix) => unawaited(_send(routeId, fix)),
            onError: _ignore,
            // The platform ended the stream (e.g. permission revoked): not
            // running any more, so the next start() subscribes again.
            onDone: () => _stream = null,
          );
      return;
    }
    _resetCadence();
    _timer = _createTimer(interval, (_) => unawaited(_tick()));
    // LGPD transparency (RNF11): the persistent notice goes up only when the
    // loop actually (re)starts, never on the same-route no-op above.
    unawaited(_notification.show());
  }

  /// Cancels the timer or the stream. Safe to call when not running.
  void stop() {
    _timer?.cancel();
    _timer = null;
    unawaited(_stream?.cancel());
    _stream = null;
    _routeId = null;
    // Idempotent — safe when the loop was never running.
    unawaited(_notification.hide());
  }

  void dispose() => stop();

  void _resetCadence() {
    _lastReported = null;
    _stationaryStreak = 0;
    _ticksToSkip = 0;
  }

  /// A transient stream error (GPS off, no fix) — the stream goes on, and
  /// the next fix retries (fire-and-forget, spec §2 Ruling 5).
  static void _ignore(Object error) {}

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
    final Coordinates position;
    try {
      position = await _location.getCurrentPosition(
        purpose: LocationPurpose.tracking,
      );
    } on Object {
      // Transient GPS/permission error — swallow, the next tick retries
      // (fire-and-forget, spec §2 Ruling 5).
      return;
    }
    if (await _send(routeId, position)) _adjustCadence(position);
  }

  /// Posts one fix; true when the server took it.
  Future<bool> _send(String routeId, Coordinates position) async {
    final sentAt = _now().toUtc();
    try {
      await _api.reportPosition(
        routeId: routeId,
        latitude: position.latitude,
        longitude: position.longitude,
        reportedAt: sentAt,
      );
    } on DioException catch (error) {
      // 409 = the backend rejected the fix because the route is no longer the
      // worker's or no longer `IN_PROGRESS` (spec §2 Ruling 5) — reporting can
      // never succeed again for this route, so stop. Any other HTTP failure is
      // transient (auth blip, 5xx): swallow it and keep going.
      if (error.response?.statusCode == 409) stop();
      return false;
    } on Object {
      // Transient network error — swallow, the next fix retries.
      return false;
    }
    _onPositionSent?.call(sentAt);
    return true;
  }
}
