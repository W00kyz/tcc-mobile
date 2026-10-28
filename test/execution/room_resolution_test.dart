import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/room_resolution.dart';
import 'package:route_monitor/routing/route_repository.dart';

RouteStopSummary _stop(
  String id, {
  required double latitude,
  required double longitude,
  String? name,
  String status = 'PENDING',
}) => RouteStopSummary(
  buildingId: 'b1',
  buildingName: 'Prédio',
  floorLabel: 'Térreo',
  id: id,
  orderIndex: 1,
  batchNumber: 1,
  status: status,
  servicePointName: name ?? 'Sala $id',
  latitude: latitude,
  longitude: longitude,
);

// The check-in GPS fix every resolveRoomLocally test below measures against.
const _lat = -7.21;
const _lng = -35.90;

void main() {
  group('haversineMeters', () {
    test('is zero for the same point', () {
      expect(haversineMeters(-7.21, -35.90, -7.21, -35.90), closeTo(0, 1e-6));
    });

    test('matches the backend fixture within one percent', () {
      // backend/tests/domain/execution/test_geo.py — ~111.3 m per 0.001 deg
      // of latitude near the equator.
      final d = haversineMeters(-7.2100, -35.9000, -7.2110, -35.9000);
      expect(d, closeTo(111.3, 111.3 * 0.01));
    });

    test('is symmetric', () {
      final a = haversineMeters(-7.21, -35.90, -7.22, -35.91);
      final b = haversineMeters(-7.22, -35.91, -7.21, -35.90);
      expect(a, closeTo(b, 1e-9));
    });
  });

  group('resolveRoomLocally', () {
    test('one pending stop within radius resolves automatically', () {
      final resolution = resolveRoomLocally(
        pendingStops: [
          _stop('near', latitude: -7.2101, longitude: -35.90), // ~11 m
          _stop('far', latitude: -7.25, longitude: -35.95),
        ],
        latitude: _lat,
        longitude: _lng,
      );

      expect(resolution, isA<ResolvedRoom>());
      expect((resolution as ResolvedRoom).routeStopId, 'near');
    });

    test('two pending stops within radius are ambiguous, nearest-first', () {
      final resolution = resolveRoomLocally(
        pendingStops: [
          _stop('mid', latitude: -7.2103, longitude: -35.90), // ~33 m
          _stop('close', latitude: -7.2101, longitude: -35.90), // ~11 m
        ],
        latitude: _lat,
        longitude: _lng,
      );

      expect(resolution, isA<AmbiguousRooms>());
      final candidates = (resolution as AmbiguousRooms).candidates;
      expect(candidates.map((c) => c.routeStopId), ['close', 'mid']);
      expect(candidates.first.distanceM, lessThan(candidates.last.distanceM!));
    });

    test(
      'nothing within radius but a lone pending stop still resolves',
      () {
        final resolution = resolveRoomLocally(
          pendingStops: [_stop('far', latitude: -7.25, longitude: -35.95)],
          latitude: _lat,
          longitude: _lng,
        );

        expect(resolution, isA<ResolvedRoom>());
        expect((resolution as ResolvedRoom).routeStopId, 'far');
      },
    );

    test(
      'nothing within radius with two pending stops is ambiguous over all '
      'of them, nearest-first',
      () {
        final resolution = resolveRoomLocally(
          pendingStops: [
            _stop('farther', latitude: -7.30, longitude: -35.95),
            _stop('nearer', latitude: -7.22, longitude: -35.90),
          ],
          latitude: _lat,
          longitude: _lng,
        );

        expect(resolution, isA<AmbiguousRooms>());
        expect(
          (resolution as AmbiguousRooms).candidates.map((c) => c.routeStopId),
          ['nearer', 'farther'],
        );
      },
    );

    test('no GPS with a lone pending stop resolves to it (distance null)', () {
      final resolution = resolveRoomLocally(
        pendingStops: [_stop('only', latitude: -7.2101, longitude: -35.90)],
        latitude: null,
        longitude: null,
      );

      expect(resolution, isA<ResolvedRoom>());
      expect((resolution as ResolvedRoom).routeStopId, 'only');
    });

    test('no GPS with two pending stops is ambiguous with null distances', () {
      final resolution = resolveRoomLocally(
        pendingStops: [
          _stop('a', latitude: -7.2101, longitude: -35.90, name: 'Sala 102'),
          _stop('b', latitude: -7.2102, longitude: -35.90, name: 'Sala 101'),
        ],
        latitude: null,
        longitude: null,
      );

      expect(resolution, isA<AmbiguousRooms>());
      final candidates = (resolution as AmbiguousRooms).candidates;
      expect(candidates.every((c) => c.distanceM == null), isTrue);
      // No distance to sort on — falls back to service-point name.
      expect(candidates.map((c) => c.servicePointName), [
        'Sala 101',
        'Sala 102',
      ]);
    });
  });
}
