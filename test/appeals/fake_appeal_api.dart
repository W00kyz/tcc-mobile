import 'package:route_monitor/appeals/appeal_api.dart';

/// One `POST /appeals` the fake received.
typedef AppealFiling = ({
  String routeStopId,
  String reason,
  String? note,
  DateTime? claimedExecutedAt,
  String idempotencyKey,
});

/// Serves [eligibleStops] and [myAppeals], records every filing, and throws
/// [fileError] on `file` when set.
class RecordingAppealApi implements AppealApi {
  RecordingAppealApi({
    this.eligibleStops = const [],
    this.myAppeals = const [],
  });

  List<AppealableStop> eligibleStops;
  List<FiledAppeal> myAppeals;
  Exception? fileError;
  final List<AppealFiling> filed = [];

  @override
  Future<List<AppealableStop>> eligible() async => eligibleStops;

  @override
  Future<List<FiledAppeal>> mine() async => myAppeals;

  @override
  Future<void> file({
    required String routeStopId,
    required String reason,
    required String? note,
    required DateTime? claimedExecutedAt,
    required String idempotencyKey,
  }) async {
    final error = fileError;
    if (error != null) throw error;
    filed.add((
      routeStopId: routeStopId,
      reason: reason,
      note: note,
      claimedExecutedAt: claimedExecutedAt,
      idempotencyKey: idempotencyKey,
    ));
  }
}
