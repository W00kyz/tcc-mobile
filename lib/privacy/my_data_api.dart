import 'package:dio/dio.dart';

/// The signed-in user's personal data, aggregated by the backend for the
/// "Meus dados" transparency screen (LGPD, RNF10). Mirrors the
/// `GET /me/personal-data` response shape field for field, read-only.
///
///     final data = PersonalData.fromJson(json);
class PersonalData {
  const PersonalData({
    required this.profile,
    required this.fieldWorker,
    required this.consentHistory,
    required this.authEvents,
    required this.executionsSummary,
    required this.evidenceSummary,
    required this.positionsSummary,
    required this.notificationsSummary,
  });

  /// Parses the full aggregate. `field_worker` is null for an account not
  /// linked to a field-worker record; the `*_summary` blocks are always
  /// present even when their counts are zero.
  factory PersonalData.fromJson(Map<String, dynamic> json) {
    final fieldWorker = json['field_worker'] as Map<String, dynamic>?;
    return PersonalData(
      profile: Profile.fromJson(json['profile'] as Map<String, dynamic>),
      fieldWorker: fieldWorker == null
          ? null
          : FieldWorkerInfo.fromJson(fieldWorker),
      consentHistory: _list(json['consent_history'], ConsentEntry.fromJson),
      authEvents: _list(json['auth_events'], AuthEvent.fromJson),
      executionsSummary: TimeSpan.fromJson(
        json['executions_summary'] as Map<String, dynamic>,
      ),
      evidenceSummary: EvidenceSummary.fromJson(
        json['evidence_summary'] as Map<String, dynamic>,
      ),
      positionsSummary: TimeSpan.fromJson(
        json['positions_summary'] as Map<String, dynamic>,
      ),
      notificationsSummary: NotificationsSummary.fromJson(
        json['notifications_summary'] as Map<String, dynamic>,
      ),
    );
  }

  final Profile profile;

  /// Null when the account is not linked to a field-worker record.
  final FieldWorkerInfo? fieldWorker;
  final List<ConsentEntry> consentHistory;
  final List<AuthEvent> authEvents;
  final TimeSpan executionsSummary;
  final EvidenceSummary evidenceSummary;
  final TimeSpan positionsSummary;
  final NotificationsSummary notificationsSummary;
}

List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) fromJson) {
  final items = raw as List<dynamic>? ?? const [];
  return items
      .map((item) => fromJson(item as Map<String, dynamic>))
      .toList(growable: false);
}

DateTime? _dateOrNull(Object? raw) {
  final value = raw as String?;
  return value == null ? null : DateTime.parse(value);
}

class Profile {
  const Profile({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    required this.isActive,
    required this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    email: json['email'] as String,
    name: json['name'] as String,
    role: json['role'] as String,
    isActive: json['is_active'] as bool,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final String email;
  final String name;
  final String role;
  final bool isActive;
  final DateTime createdAt;
}

class FieldWorkerInfo {
  const FieldWorkerInfo({
    required this.id,
    required this.fullName,
    required this.contractorCompanyId,
    required this.serviceTypeIds,
  });

  factory FieldWorkerInfo.fromJson(Map<String, dynamic> json) =>
      FieldWorkerInfo(
        id: json['id'] as String,
        fullName: json['full_name'] as String,
        contractorCompanyId: json['contractor_company_id'] as String,
        serviceTypeIds: (json['service_type_ids'] as List<dynamic>? ?? const [])
            .map((id) => id as String)
            .toList(growable: false),
      );

  final String id;
  final String fullName;
  final String contractorCompanyId;
  final List<String> serviceTypeIds;
}

class ConsentEntry {
  const ConsentEntry({required this.noticeVersion, required this.acceptedAt});

  factory ConsentEntry.fromJson(Map<String, dynamic> json) => ConsentEntry(
    noticeVersion: json['notice_version'] as int,
    acceptedAt: DateTime.parse(json['accepted_at'] as String),
  );

  final int noticeVersion;
  final DateTime acceptedAt;
}

class AuthEvent {
  const AuthEvent({
    required this.event,
    required this.ipAddress,
    required this.createdAt,
  });

  factory AuthEvent.fromJson(Map<String, dynamic> json) => AuthEvent(
    event: json['event'] as String,
    ipAddress: json['ip_address'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String event;
  final String? ipAddress;
  final DateTime createdAt;
}

/// A `{ total, first_at, last_at }` block — shared by the executions and the
/// positions summaries, which have the same shape.
class TimeSpan {
  const TimeSpan({
    required this.total,
    required this.firstAt,
    required this.lastAt,
  });

  factory TimeSpan.fromJson(Map<String, dynamic> json) => TimeSpan(
    total: json['total'] as int,
    firstAt: _dateOrNull(json['first_at']),
    lastAt: _dateOrNull(json['last_at']),
  );

  final int total;
  final DateTime? firstAt;
  final DateTime? lastAt;
}

class EvidenceSummary {
  const EvidenceSummary({required this.totalItems, required this.totalBytes});

  factory EvidenceSummary.fromJson(Map<String, dynamic> json) =>
      EvidenceSummary(
        totalItems: json['total_items'] as int,
        totalBytes: json['total_bytes'] as int,
      );

  final int totalItems;
  final int totalBytes;
}

class NotificationsSummary {
  const NotificationsSummary({required this.total, required this.unread});

  factory NotificationsSummary.fromJson(Map<String, dynamic> json) =>
      NotificationsSummary(
        total: json['total'] as int,
        unread: json['unread'] as int,
      );

  final int total;
  final int unread;
}

/// The seam over `GET /me/personal-data` — keeps the screen's tests off the
/// real HTTP client (CLAUDE.md — Dependencies: wrap third-party libs behind a
/// thin interface).
// ignore: one_member_abstracts
abstract class MyDataApi {
  Future<PersonalData> fetch();
}

class DioMyDataApi implements MyDataApi {
  DioMyDataApi(this._dio);

  final Dio _dio;

  @override
  Future<PersonalData> fetch() async {
    final response = await _dio.get<Map<String, dynamic>>('/me/personal-data');
    return PersonalData.fromJson(response.data!);
  }
}
