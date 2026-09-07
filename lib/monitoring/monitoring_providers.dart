import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/api/api_client.dart';
import 'package:route_monitor/api/env.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/monitoring/monitoring_api.dart';
import 'package:route_monitor/monitoring/position_reporter.dart';
import 'package:route_monitor/routing/route_providers.dart'
    show locationServiceProvider;

/// Mirrors `executionApiProvider` — a fresh Dio bound to the current session's
/// bearer token, rebuilt whenever the session changes.
final monitoringApiProvider = Provider<MonitoringApi>((ref) {
  final session = ref.watch(sessionProvider);
  final dio = buildDio(
    baseUrl: apiBaseUrlFromEnvironment(),
    accessToken: session?.accessToken,
  );
  return DioMonitoringApi(dio);
});

/// The worker's in-app notification list (RF49). Plain `FutureProvider` — the
/// screen re-fetches via `ref.invalidate` after a `markRead`.
final notificationsProvider = FutureProvider<List<AppNotification>>((ref) {
  return ref.watch(monitoringApiProvider).fetchNotifications();
});

/// The unread-notification count behind the route-screen bell badge.
/// Invalidated alongside [notificationsProvider] after a `markRead`.
final unreadCountProvider = FutureProvider<int>((ref) {
  return ref.watch(monitoringApiProvider).unreadCount();
});

/// The app-wide position reporter. Long-lived (one timer, not one per screen);
/// `PositionReportingTrigger` calls `start`/`stop` as the visible route enters
/// and leaves `IN_PROGRESS`.
final positionReporterProvider = Provider<PositionReporter>((ref) {
  final reporter = PositionReporter(
    location: ref.watch(locationServiceProvider),
    api: ref.watch(monitoringApiProvider),
  );
  ref.onDispose(reporter.dispose);
  return reporter;
});
