import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/execution/execution_providers.dart'
    show apiBaseUrlProvider, appDatabaseProvider;
import 'package:route_monitor/local/background_ask_store.dart';
import 'package:route_monitor/monitoring/local_notification_scheduler.dart';
import 'package:route_monitor/monitoring/location_mode.dart';
import 'package:route_monitor/monitoring/location_mode_device.dart';
import 'package:route_monitor/monitoring/monitoring_api.dart';
import 'package:route_monitor/monitoring/ongoing_notification.dart';
import 'package:route_monitor/monitoring/position_reporter.dart';
import 'package:route_monitor/monitoring/position_source.dart';
import 'package:route_monitor/monitoring/silence_watchdog.dart';
import 'package:route_monitor/routing/route_providers.dart'
    show locationServiceProvider, myDayProvider;

/// Scoped to the signed-in user, not to the session: the position reporter
/// holds this client for the whole route, and a token refresh must not
/// rebuild — and so stop — it (`buildUserScopedSessionDio`).
final monitoringApiProvider = Provider<MonitoringApi>((ref) {
  final dio = buildUserScopedSessionDio(
    ref,
    baseUrl: ref.watch(apiBaseUrlProvider),
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
/// The persistent collection notice (RNF11). A dedicated provider so tests can
/// override it with a fake and never reach `flutter_local_notifications`.
final ongoingNotificationProvider = Provider<OngoingNotification>(
  (ref) => LocalOngoingNotification(),
);

/// The background mode's fix stream (spec 2026-10-20-alocacao-automatica
/// §7.3); overridden in tests.
final positionSourceProvider = Provider<PositionSource>(
  (ref) => GeolocatorPositionSource(),
);

final positionReporterProvider = Provider<PositionReporter>((ref) {
  final reporter = PositionReporter(
    location: ref.watch(locationServiceProvider),
    positionSource: ref.watch(positionSourceProvider),
    api: ref.watch(monitoringApiProvider),
    notification: ref.watch(ongoingNotificationProvider),
    // Read at each send, not watched: the watchdog is rebuilt when the
    // server's limits change, and that must not restart the reporter. A send
    // that lands after this reporter was disposed (another user) finds the
    // ref unmounted and reports nothing — reading it would throw.
    onPositionSent: (sentAt) {
      if (!ref.mounted) return;
      ref.read(silenceWatchdogProvider)?.onActivity(sentAt);
    },
  );
  ref.onDispose(reporter.dispose);
  return reporter;
});

final permissionPortProvider = Provider<PermissionPort>(
  (ref) => PermissionHandlerPort(),
);

final backgroundAskStoreProvider = Provider<BackgroundAskStore>(
  (ref) => DriftBackgroundAskStore(ref.watch(appDatabaseProvider)),
);

/// The mode the current permissions allow. "Iniciar rota" invalidates it
/// after asking (`resolveLocationMode`), and so does a resume — the worker
/// may have changed the permission in the system settings meanwhile.
final locationModeProvider = FutureProvider<LocationMode>(
  (ref) => currentLocationMode(ref.watch(permissionPortProvider)),
);

final localSchedulerProvider = Provider<LocalScheduler>(
  (ref) => LocalNotificationScheduler(),
);

/// The silence watchdog, with the limits `GET /routes/me` sent; null until
/// the first day is loaded. Rebuilt only when those limits or the signed-in
/// user change — never on a token refresh or a day reload, which would
/// cancel a warning scheduled with the screen locked.
final silenceWatchdogProvider = Provider<SilenceWatchdog?>((ref) {
  ref.watch(sessionProvider.select((session) => session?.userId));
  // `.value` keeps the last known day across a reload or a failed one.
  final limits = ref.watch(
    myDayProvider.select((day) {
      final value = day.value;
      if (value == null) return null;
      return (
        warning: value.silenceWarningMinutes,
        release: value.silenceReleaseMinutes,
      );
    }),
  );
  if (limits == null) return null;
  final watchdog = SilenceWatchdog(
    clock: DateTime.now,
    scheduler: ref.watch(localSchedulerProvider),
    warningMinutes: limits.warning,
    releaseMinutes: limits.release,
  );
  ref.onDispose(watchdog.stopWatching);
  return watchdog;
});
