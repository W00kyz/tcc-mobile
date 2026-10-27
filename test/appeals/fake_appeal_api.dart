import 'package:route_monitor/appeals/appeal_api.dart';

/// One `POST /appeals` the fake received.
typedef AppealFiling = ({
  String routeStopId,
  String reason,
  String? note,
  DateTime? claimedExecutedAt,
  String idempotencyKey,
});

/// Serves [eligibleStops] and [myAppeals], records every filing attempt —
/// before failing it with [fileError], when set — and counts the eligible
/// fetches.
class RecordingAppealApi implements AppealApi {
  RecordingAppealApi({
    this.eligibleStops = const [],
    this.myAppeals = const [],
  });

  List<AppealableStop> eligibleStops;
  List<FiledAppeal> myAppeals;

  /// Thrown by `file` after recording the attempt: an [Exception] such as a
  /// `DioException`, or an [Error] such as the `TypeError` of a refusal body
  /// that does not decode.
  Object? fileError;

  /// Every attempt, failed ones included.
  final List<AppealFiling> attempts = [];

  /// The attempts the server took.
  final List<AppealFiling> filed = [];
  int eligibleCalls = 0;

  @override
  Future<List<AppealableStop>> eligible() async {
    eligibleCalls++;
    return eligibleStops;
  }

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
    final filing = (
      routeStopId: routeStopId,
      reason: reason,
      note: note,
      claimedExecutedAt: claimedExecutedAt,
      idempotencyKey: idempotencyKey,
    );
    attempts.add(filing);
    final error = fileError;
    // A test double throws whatever failure the case needs.
    // ignore: only_throw_errors
    if (error != null) throw error;
    filed.add(filing);
  }
}
