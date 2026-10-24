import 'package:dio/dio.dart';
import 'package:route_monitor/api/api_client.dart' show apiErrorCode;

/// A released stop of the worker's that they may still contest — an item of
/// `GET /appeals/eligible` (spec 2026-10-20-alocacao-automatica §7.5).
class AppealableStop {
  const AppealableStop({
    required this.routeStopId,
    required this.servicePointName,
    required this.buildingName,
    required this.floorLabel,
    required this.releaseReason,
    required this.deadline,
  });

  factory AppealableStop.fromJson(Map<String, dynamic> json) => AppealableStop(
    routeStopId: json['route_stop_id'] as String,
    servicePointName: json['service_point_name'] as String,
    buildingName: json['building_name'] as String,
    floorLabel: json['floor_label'] as String,
    releaseReason: json['release_reason'] as String,
    deadline: DateTime.parse(json['deadline'] as String),
  );

  final String routeStopId;
  final String servicePointName;
  final String buildingName;
  final String floorLabel;
  final String releaseReason;

  /// The last instant the server accepts the appeal.
  final DateTime deadline;
}

/// One of the worker's own appeals and its decision — an item of
/// `GET /appeals/mine`, reduced to what "Meus recursos" shows.
class FiledAppeal {
  const FiledAppeal({
    required this.id,
    required this.servicePointName,
    required this.buildingName,
    required this.status,
    required this.filedAt,
    this.reviewedByName,
    this.reviewNote,
  });

  factory FiledAppeal.fromJson(Map<String, dynamic> json) => FiledAppeal(
    id: json['id'] as String,
    servicePointName: json['service_point_name'] as String,
    buildingName: json['building_name'] as String,
    status: json['status'] as String,
    filedAt: DateTime.parse(json['filed_at'] as String),
    reviewedByName: json['reviewed_by_name'] as String?,
    reviewNote: json['review_note'] as String?,
  );

  final String id;
  final String servicePointName;
  final String buildingName;

  /// `PENDING` | `ACCEPTED` | `REJECTED`.
  final String status;
  final DateTime filedAt;

  /// Who decided and what they wrote; null while `PENDING` (the note may be
  /// null on a decision too).
  final String? reviewedByName;
  final String? reviewNote;
}

/// 409 `NOT_APPEALABLE`: the server refused the appeal; [reasonCode] says why
/// (`NOT_OWNER`, `NOT_RELEASED`, `REASON_NOT_APPEALABLE`,
/// `ALREADY_CHECKED_OUT`, `ALREADY_APPEALED`, `WINDOW_EXPIRED`).
final class NotAppealableException implements Exception {
  const NotAppealableException(this.reasonCode);

  final String reasonCode;

  @override
  String toString() =>
      'NotAppealableException: appeal refused with NOT_APPEALABLE '
      '($reasonCode); expected a released stop of this worker, still within '
      'the appeal window.';
}

/// The worker's side of the appeals API. All three endpoints require an
/// approved worker.
abstract class AppealApi {
  /// `GET /appeals/eligible`, latest release first.
  Future<List<AppealableStop>> eligible();

  /// `POST /appeals` — idempotent on [idempotencyKey]: a retry after a lost
  /// answer files nothing twice. Throws [NotAppealableException] on a 409
  /// `NOT_APPEALABLE`.
  ///
  ///     await api.file(routeStopId: id, reason: 'NO_SIGNAL', note: null,
  ///         claimedExecutedAt: checkInAt, idempotencyKey: uuid);
  Future<void> file({
    required String routeStopId,
    required String reason,
    required String? note,
    required DateTime? claimedExecutedAt,
    required String idempotencyKey,
  });

  /// `GET /appeals/mine`, pending first.
  Future<List<FiledAppeal>> mine();
}

class DioAppealApi implements AppealApi {
  DioAppealApi(this._dio);

  final Dio _dio;

  @override
  Future<List<AppealableStop>> eligible() async {
    final response = await _dio.get<List<dynamic>>('/appeals/eligible');
    return response.data!
        .map((raw) => AppealableStop.fromJson(raw as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> file({
    required String routeStopId,
    required String reason,
    required String? note,
    required DateTime? claimedExecutedAt,
    required String idempotencyKey,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/appeals',
        data: {
          'route_stop_id': routeStopId,
          'reason': reason,
          'note': note,
          'claimed_executed_at': claimedExecutedAt?.toUtc().toIso8601String(),
          'idempotency_key': idempotencyKey,
        },
      );
    } on DioException catch (error) {
      final refusal = _refusalOf(error);
      if (refusal != null) throw refusal;
      rethrow;
    }
  }

  @override
  Future<List<FiledAppeal>> mine() async {
    final response = await _dio.get<List<dynamic>>('/appeals/mine');
    return response.data!
        .map((raw) => FiledAppeal.fromJson(raw as Map<String, dynamic>))
        .toList();
  }

  static NotAppealableException? _refusalOf(DioException error) {
    if (error.response?.statusCode != 409) return null;
    if (apiErrorCode(error) != 'NOT_APPEALABLE') return null;
    final detail = (error.response!.data as Map)['detail'] as Map;
    return NotAppealableException(detail['reason_code'] as String);
  }
}
