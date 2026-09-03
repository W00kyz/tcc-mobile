import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart' as cplus;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:route_monitor/sync/connectivity.dart';

import '../support/fake_connectivity.dart';

class _MockPlugin extends Mock implements cplus.Connectivity {}

void main() {
  group('ConnectivityPlusConnectivity', () {
    late _MockPlugin plugin;
    late StreamController<List<cplus.ConnectivityResult>> changes;

    setUp(() {
      plugin = _MockPlugin();
      changes = StreamController<List<cplus.ConnectivityResult>>.broadcast();
      when(
        () => plugin.onConnectivityChanged,
      ).thenAnswer((_) => changes.stream);
    });

    tearDown(() => changes.close());

    test('isOnline is false when the only result is none', () async {
      when(
        () => plugin.checkConnectivity(),
      ).thenAnswer((_) async => [cplus.ConnectivityResult.none]);

      expect(
        await ConnectivityPlusConnectivity(plugin: plugin).isOnline,
        isFalse,
      );
    });

    test('isOnline is true when any result is not none', () async {
      when(() => plugin.checkConnectivity()).thenAnswer(
        (_) async => [
          cplus.ConnectivityResult.none,
          cplus.ConnectivityResult.wifi,
        ],
      );

      expect(
        await ConnectivityPlusConnectivity(plugin: plugin).isOnline,
        isTrue,
      );
    });

    test(
      'onOnlineChanged emits true only on a none -> online transition',
      () async {
        final connectivity = ConnectivityPlusConnectivity(plugin: plugin);
        final emitted = <bool>[];
        final sub = connectivity.onOnlineChanged.listen(emitted.add);

        changes
          ..add([cplus.ConnectivityResult.none])
          ..add([cplus.ConnectivityResult.wifi])
          ..add([cplus.ConnectivityResult.mobile])
          ..add([cplus.ConnectivityResult.none])
          ..add([cplus.ConnectivityResult.wifi]);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(emitted, [true, true]);
      },
    );
  });

  group('FakeConnectivity', () {
    test('drives isOnline and the regained stream', () async {
      final fake = FakeConnectivity();
      addTearDown(fake.dispose);
      final emitted = <bool>[];
      fake.onOnlineChanged.listen(emitted.add);

      expect(await fake.isOnline, isFalse);
      fake.goOnline();
      await Future<void>.delayed(Duration.zero);

      expect(await fake.isOnline, isTrue);
      expect(emitted, [true]);
    });
  });
}
