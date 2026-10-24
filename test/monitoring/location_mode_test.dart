import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/monitoring/location_mode.dart';

void main() {
  late _FakePermissions permissions;
  late _RecordingPrompts prompts;
  late _InMemoryAskStore asked;

  setUp(() {
    permissions = _FakePermissions();
    prompts = _RecordingPrompts();
    asked = _InMemoryAskStore();
  });

  Future<LocationMode> resolve() =>
      resolveLocationMode(permissions, prompts: prompts, asked: asked);

  test(
    'explains, then asks for "always" once "while in use" is granted',
    () async {
      permissions.grantsAlways = true;

      final mode = await resolve();

      expect(mode, LocationMode.background);
      expect(prompts.calls, ['explainBackground']);
      expect(permissions.calls, [
        'requestWhileInUse',
        'isAlwaysGranted',
        'requestNotifications',
        'requestAlways',
      ]);
    },
  );

  test('a refusal falls back to foregroundOnly with a one-time note', () async {
    final mode = await resolve();

    expect(mode, LocationMode.foregroundOnly);
    expect(prompts.calls, ['explainBackground', 'noteForegroundOnly']);
  });

  test(
    'never asks twice: the second resolve neither prompts nor requests',
    () async {
      await resolve();
      prompts.calls.clear();
      permissions.calls.clear();

      final mode = await resolve();

      expect(mode, LocationMode.foregroundOnly);
      expect(prompts.calls, isEmpty);
      expect(permissions.calls, ['requestWhileInUse', 'isAlwaysGranted']);
    },
  );

  test('"always" already granted: background, no prompt', () async {
    permissions.alwaysGranted = true;

    final mode = await resolve();

    expect(mode, LocationMode.background);
    expect(prompts.calls, isEmpty);
    expect(asked.value, isFalse);
  });

  test(
    '"while in use" refused: foregroundOnly, "always" never asked',
    () async {
      permissions.grantsWhileInUse = false;

      final mode = await resolve();

      expect(mode, LocationMode.foregroundOnly);
      expect(permissions.calls, ['requestWhileInUse']);
      expect(prompts.calls, isEmpty);
      expect(asked.value, isFalse);
    },
  );

  test('currentLocationMode reads the permission without asking', () async {
    expect(await currentLocationMode(permissions), LocationMode.foregroundOnly);
    permissions.alwaysGranted = true;
    expect(await currentLocationMode(permissions), LocationMode.background);
    expect(permissions.calls, ['isAlwaysGranted', 'isAlwaysGranted']);
  });
}

class _FakePermissions implements PermissionPort {
  bool grantsWhileInUse = true;
  bool alwaysGranted = false;

  /// What the OS answers to the "always" request.
  bool grantsAlways = false;
  final List<String> calls = [];

  @override
  Future<bool> requestWhileInUse() async {
    calls.add('requestWhileInUse');
    return grantsWhileInUse;
  }

  @override
  Future<bool> isAlwaysGranted() async {
    calls.add('isAlwaysGranted');
    return alwaysGranted;
  }

  @override
  Future<bool> requestAlways() async {
    calls.add('requestAlways');
    alwaysGranted = grantsAlways;
    return grantsAlways;
  }

  @override
  Future<void> requestNotifications() async {
    calls.add('requestNotifications');
  }
}

class _RecordingPrompts implements LocationModePrompts {
  final List<String> calls = [];

  @override
  Future<void> explainBackground() async => calls.add('explainBackground');

  @override
  Future<void> noteForegroundOnly() async => calls.add('noteForegroundOnly');
}

class _InMemoryAskStore implements BackgroundAskStore {
  bool value = false;

  @override
  Future<bool> wasAsked() async => value;

  @override
  Future<void> markAsked() async => value = true;
}
