import 'dart:async';

import 'package:route_monitor/routing/route_repository.dart';

/// A stop in batch [batchNumber] (default 1), PENDING unless told otherwise.
RouteStopSummary stopWith({
  required String id,
  int orderIndex = 1,
  int batchNumber = 1,
  String status = 'PENDING',
  String? releaseReason,
  String? servicePointName,
  double latitude = -7.21,
  double longitude = -35.91,
}) => RouteStopSummary(
  id: id,
  orderIndex: orderIndex,
  batchNumber: batchNumber,
  status: status,
  releaseReason: releaseReason,
  servicePointName: servicePointName ?? 'Ponto $id',
  latitude: latitude,
  longitude: longitude,
);

/// Today's route `r1`, IN_PROGRESS on batch [currentBatch] unless told
/// otherwise.
RouteSummary routeWith({
  required List<RouteStopSummary> stops,
  String status = 'IN_PROGRESS',
  int currentBatch = 1,
}) => RouteSummary(
  id: 'r1',
  fieldWorkerName: 'João',
  routeDate: DateTime(2026, 10, 20),
  status: status,
  startedAt: DateTime.utc(2026, 10, 20, 11),
  currentBatch: currentBatch,
  stops: stops,
);

/// A service day holding [route] (none yet when null).
MyDay myDayWith(RouteSummary? route, {bool serviceDay = true}) => MyDay(
  serviceDay: serviceDay,
  route: route,
  positionIntervalSeconds: 60,
  silenceWarningMinutes: 30,
  silenceReleaseMinutes: 45,
);

/// In-memory [RouteRepository]: serves [day], records every allocation call
/// and answers it through [allocate] — by default the current route handed
/// back unchanged, the server's answer to a retry while a stop is still open.
class FakeRouteRepository implements RouteRepository {
  FakeRouteRepository([MyDay? day]) : day = day ?? myDayWith(null);

  MyDay day;

  /// When set, every [fetchMyDay] throws it instead.
  Exception? fetchError;
  int fetchCount = 0;

  /// `start` or `nextBatch:<routeId>`, in call order.
  final List<String> allocationCalls = [];
  ({double lat, double lng})? lastPosition;

  /// The server's answer to the next start/next-batch call; it may throw a
  /// refusal or update [day] to what a later `GET /routes/me` returns.
  FutureOr<AllocationResult> Function()? allocate;

  @override
  Future<MyDay> fetchMyDay() async {
    fetchCount++;
    final error = fetchError;
    if (error != null) throw error;
    return day;
  }

  @override
  Future<AllocationResult> startOrResume({
    required double lat,
    required double lng,
    required DateTime capturedAt,
  }) => _allocate('start', lat, lng);

  @override
  Future<AllocationResult> nextBatch(
    String routeId, {
    required double lat,
    required double lng,
    required DateTime capturedAt,
  }) => _allocate('nextBatch:$routeId', lat, lng);

  Future<AllocationResult> _allocate(
    String call,
    double lat,
    double lng,
  ) async {
    allocationCalls.add(call);
    lastPosition = (lat: lat, lng: lng);
    final answer = allocate;
    if (answer != null) return answer();
    return AllocationResult(route: day.route!, poolEmpty: false);
  }
}
