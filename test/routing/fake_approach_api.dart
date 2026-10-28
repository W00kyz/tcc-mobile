import 'package:route_monitor/routing/approach_api.dart';

/// A scripted [ApproachApi]: answers [leg] (null = 204), or throws [error]
/// when set, and records every position it was asked from.
class FakeApproachApi implements ApproachApi {
  FakeApproachApi({this.leg, this.error});

  ApproachLeg? leg;
  Object? error;
  final List<(double, double)> calls = [];

  @override
  Future<ApproachLeg?> fetchApproach({
    required double latitude,
    required double longitude,
  }) async {
    calls.add((latitude, longitude));
    final failure = error;
    // ignore: only_throw_errors — a fake replaying whatever the test injects.
    if (failure != null) throw failure;
    return leg;
  }
}
