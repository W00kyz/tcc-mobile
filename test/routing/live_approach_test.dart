import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_monitor/routing/approach_api.dart';
import 'package:route_monitor/routing/live_approach.dart';

import 'fake_approach_api.dart';

/// A clock the test moves by hand.
class _ManualClock {
  DateTime now = DateTime.utc(2026, 10, 28, 13);

  void advance(Duration by) => now = now.add(by);
}

const _stopAt = LatLng(-7.2150, -35.9095);
const _target = ApproachTarget(stopId: 's2', position: _stopAt);
const _here = LatLng(-7.2140, -35.9090);
// About 33 m north of [_here]; [_nudged] about 11 m.
const _moved = LatLng(-7.2137, -35.9090);
const _nudged = LatLng(-7.2139, -35.9090);

ApproachLeg _streetLeg({String stopId = 's2'}) => ApproachLeg(
  routeStopId: stopId,
  points: const [_here, LatLng(-7.2145, -35.9093), _stopAt],
  distanceM: 140,
  durationS: 100,
);

void main() {
  late FakeApproachApi api;
  late _ManualClock clock;
  late ApproachTracker tracker;

  setUp(() {
    api = FakeApproachApi(leg: _streetLeg());
    clock = _ManualClock();
    tracker = ApproachTracker(api: api, target: _target, now: () => clock.now);
  });

  group('ApproachTracker', () {
    test('the first position fetches and keeps the street path', () async {
      expect(tracker.isDue(_here), isTrue);

      final approach = await tracker.fetch(_here);

      expect(approach.approximate, isFalse);
      expect(approach.points, _streetLeg().points);
      // The stop itself, so the map can bridge a snapped street end.
      expect(approach.destination, _target.position);
      expect(api.calls, [(_here.latitude, _here.longitude)]);
    });

    test('never fetches twice within 15 s, however far the move', () async {
      await tracker.fetch(_here);

      clock.advance(const Duration(seconds: 14));

      expect(tracker.isDue(_moved), isFalse);
      clock.advance(const Duration(seconds: 1));
      expect(tracker.isDue(_moved), isTrue);
    });

    test('after 15 s only a move past 25 m fetches again', () async {
      await tracker.fetch(_here);
      clock.advance(const Duration(minutes: 5));

      expect(tracker.isDue(_nudged), isFalse);
      expect(tracker.isDue(_moved), isTrue);
    });

    test('a fetch in flight blocks another', () async {
      final pending = tracker.fetch(_here);

      expect(tracker.isDue(_moved), isFalse);
      await pending;
    });

    test(
      'offline with no path yet: a dashed straight line to the stop',
      () async {
        api.error = DioException(requestOptions: RequestOptions());

        final approach = await tracker.fetch(_here);

        expect(approach.approximate, isTrue);
        expect(approach.points, [_here, _stopAt]);
      },
    );

    test('a failure keeps the last good street path', () async {
      final good = await tracker.fetch(_here);
      api.error = StateError('503 OSRM_UNAVAILABLE');
      clock.advance(const Duration(seconds: 30));

      final approach = await tracker.fetch(_moved);

      expect(approach, same(good));
      expect(tracker.current(_moved), same(good));
    });

    test(
      'a path to another stop (an unsynced check-out) is not drawn',
      () async {
        api.leg = _streetLeg(stopId: 's1');

        final approach = await tracker.fetch(_here);

        expect(approach.approximate, isTrue);
        expect(approach.points, [_here, _stopAt]);
      },
    );

    test('no PENDING stop on the server (204): a straight line', () async {
      api.leg = null;

      final approach = await tracker.fetch(_here);

      expect(approach.approximate, isTrue);
    });
  });

  group('liveApproachProvider', () {
    ProviderContainer containerWith(FakeApproachApi api) {
      final container = ProviderContainer(
        overrides: [
          approachApiProvider.overrideWithValue(api),
          approachClockProvider.overrideWithValue(() => clock.now),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('no position: no live approach and no request', () async {
      final container = containerWith(api);
      final sub = container.listen(liveApproachProvider(_target), (_, _) {});
      addTearDown(sub.close);

      await pumpEventQueue();

      expect(sub.read(), isNull);
      expect(api.calls, isEmpty);
    });

    test('a position draws a straight line, then the street path', () async {
      final container = containerWith(api);
      final sub = container.listen(liveApproachProvider(_target), (_, _) {});
      addTearDown(sub.close);

      container.read(workerPositionProvider.notifier).update(_here);
      expect(sub.read()?.approximate, isTrue);
      await pumpEventQueue();

      expect(sub.read()?.approximate, isFalse);
      expect(sub.read()?.points, _streetLeg().points);
    });

    test('a small move inside 15 s asks nothing more', () async {
      final container = containerWith(api);
      final sub = container.listen(liveApproachProvider(_target), (_, _) {});
      addTearDown(sub.close);
      final position = container.read(workerPositionProvider.notifier)
        ..update(_here);
      await pumpEventQueue();
      position.update(_moved);
      await pumpEventQueue();

      expect(api.calls, hasLength(1));
      expect(sub.read()?.approximate, isFalse);
    });
  });
}
