/// How the app reports the worker's position during a route (spec
/// 2026-10-20-alocacao-automatica §7.3).
enum LocationMode {
  /// "Always" granted: an Android foreground service keeps reporting with the
  /// screen locked.
  background,

  /// Only "while in use": positions go out while the app is open, and the
  /// server works from the last one it got.
  foregroundOnly,
}

/// The OS location/notification permissions, behind this project's interface
/// so `resolveLocationMode` is testable without `permission_handler`.
abstract class PermissionPort {
  /// Asks for "while in use" location; true when granted. Answers without a
  /// prompt when it already was.
  Future<bool> requestWhileInUse();

  Future<bool> isAlwaysGranted();

  /// Asks for "always" location; true when granted.
  Future<bool> requestAlways();

  /// Android 13+: the silence warning and the service notice are
  /// notifications, which need their own runtime permission.
  Future<void> requestNotifications();
}

/// What the worker reads around the "always" request.
abstract class LocationModePrompts {
  /// Before the request: why "always" keeps their points.
  Future<void> explainBackground();

  /// After a refusal: what to do without it.
  Future<void> noteForegroundOnly();
}

/// Remembers, on the device, that the "always" question was already put —
/// it is asked once, never on every "Iniciar rota".
abstract class BackgroundAskStore {
  Future<bool> wasAsked();

  Future<void> markAsked();
}

/// The mode the current permissions allow, without asking anything — for a
/// route already `IN_PROGRESS` when the app (re)starts.
///
///     final mode = await currentLocationMode(permissions);
Future<LocationMode> currentLocationMode(PermissionPort permissions) async {
  return await permissions.isAlwaysGranted()
      ? LocationMode.background
      : LocationMode.foregroundOnly;
}

/// Settles the mode at "Iniciar rota": "while in use" first (the start needs
/// a fix anyway), then — once per device — an explanation and the "always"
/// request. A refusal ends in [LocationMode.foregroundOnly] and a one-time
/// note on what that means.
///
///     final mode = await resolveLocationMode(
///       permissions,
///       prompts: DialogLocationModePrompts(context),
///       asked: askStore,
///     );
Future<LocationMode> resolveLocationMode(
  PermissionPort permissions, {
  required LocationModePrompts prompts,
  required BackgroundAskStore asked,
}) async {
  final whileInUse = await permissions.requestWhileInUse();
  if (!whileInUse) return LocationMode.foregroundOnly;
  if (await permissions.isAlwaysGranted()) return LocationMode.background;
  if (await asked.wasAsked()) return LocationMode.foregroundOnly;
  // Marked before the prompts: an app killed mid-dialog must not ask again.
  await asked.markAsked();
  await permissions.requestNotifications();
  await prompts.explainBackground();
  if (await permissions.requestAlways()) return LocationMode.background;
  await prompts.noteForegroundOnly();
  return LocationMode.foregroundOnly;
}
