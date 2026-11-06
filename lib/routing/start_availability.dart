import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/route_repository.dart';

/// What the start button shows: `enabled` to press it, `countdown` while the
/// workday is about to open, `hint` — why it is off — when there is no
/// countdown to say it.
typedef StartAvailability = ({bool enabled, Duration? countdown, String? hint});

/// The countdown only shows in the last minutes before the opening.
const Duration _countdownWindow = Duration(minutes: 5);

/// Whether the worker may start (or resume) the route now, read from the
/// server clock: `deviceNow` plus [MyDay.serverOffset], never the device
/// clock alone. The server decides for real; this only models the button.
///
///     final a = startAvailability(day, deviceNow: DateTime.now());
///     // a.enabled == false, a.countdown == Duration(minutes: 4, seconds: 32)
StartAvailability startAvailability(
  MyDay day, {
  required DateTime deviceNow,
}) {
  final route = day.route;
  final canStart = route == null || route.status == 'PAUSED';
  if (!day.serviceDay || !canStart) return _off(null);
  if (day.workdayOver) return _off(AppStrings.routeWorkdayOver);
  // A paused route resumes whenever: the opening only holds a first start.
  final opensAt = route == null ? day.startOpensAt : null;
  if (opensAt == null) return _on();
  final left = opensAt.difference(deviceNow.toUtc().add(day.serverOffset));
  if (left <= Duration.zero) return _on();
  if (left > _countdownWindow) return _off(AppStrings.routeStartNotOpenYet);
  return (enabled: false, countdown: left, hint: null);
}

StartAvailability _on() => (enabled: true, countdown: null, hint: null);

StartAvailability _off(String? hint) =>
    (enabled: false, countdown: null, hint: hint);
