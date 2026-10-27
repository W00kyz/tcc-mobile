import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:route_monitor/api/api_client.dart';

/// Where a field worker's self-registration stands (spec
/// 2026-10-20-alocacao-automatica §5.2), as the backend spells it.
enum WorkerStatus {
  pendingApproval('PENDING_APPROVAL'),
  approved('APPROVED'),
  rejected('REJECTED');

  const WorkerStatus(this.apiValue);

  final String apiValue;

  static WorkerStatus? fromApi(String? value) {
    for (final status in values) {
      if (status.apiValue == value) return status;
    }
    return null;
  }
}

/// What login and refresh say about the worker behind a session: approval
/// status, the manager's rejection reason, and whether they were deactivated.
/// All null for a non-worker — and for a session stored before the backend
/// sent it, which a 403 `WORKER_NOT_APPROVED` refreshes.
class WorkerStanding {
  const WorkerStanding({this.status, this.rejectionReason, this.active});

  /// Reads the `worker_status`, `rejection_reason` and `worker_active` keys
  /// that login, refresh and the stored session share.
  factory WorkerStanding.fromJson(Map<String, dynamic> json) => WorkerStanding(
    status: WorkerStatus.fromApi(json['worker_status'] as String?),
    rejectionReason: json['rejection_reason'] as String?,
    active: json['worker_active'] as bool?,
  );

  final WorkerStatus? status;
  final String? rejectionReason;
  final bool? active;

  /// True when the worker may not work yet (or anymore): the router holds
  /// such a session on `/aguardando-aprovacao`.
  bool get blocksWork =>
      status != null && (status != WorkerStatus.approved || active == false);

  Map<String, Object?> toJson() => {
    'worker_status': status?.apiValue,
    'rejection_reason': rejectionReason,
    'worker_active': active,
  };
}

class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.role,
    this.consentRequired = false,
    this.workerStanding = const WorkerStanding(),
  });

  final String accessToken;
  final String refreshToken;
  final String role;

  /// The user id (`sub` claim) behind this session, or '' for a token that is
  /// not a readable JWT. Keys per-user data on the device (route snapshot).
  String get userId => _decodeClaims(accessToken)?['sub'] as String? ?? '';

  /// True when the backend's login response flagged that this user still owes
  /// consent to the current data-processing notice (LGPD, RNF10). The router
  /// guard holds such a session on `/consentimento` until it is cleared.
  final bool consentRequired;

  final WorkerStanding workerStanding;

  Session copyWith({
    String? accessToken,
    bool? consentRequired,
    WorkerStanding? workerStanding,
  }) => Session(
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken,
    role: role,
    consentRequired: consentRequired ?? this.consentRequired,
    workerStanding: workerStanding ?? this.workerStanding,
  );
}

/// A refresh's answer: the new access token and the worker standing as of
/// now, so an approval made after login reaches the app without a new login.
/// [consentRequired] likewise brings a privacy notice published after login;
/// null when the server did not say (the session keeps what it had).
class RefreshedAccess {
  const RefreshedAccess({
    required this.accessToken,
    this.workerStanding = const WorkerStanding(),
    this.consentRequired,
  });

  final String accessToken;
  final WorkerStanding workerStanding;
  final bool? consentRequired;
}

/// A contractor company a worker can join at sign-up.
class CompanyOption {
  const CompanyOption({required this.id, required this.name});

  final String id;
  final String name;
}

class InvalidCredentialsException implements Exception {
  const InvalidCredentialsException();
}

/// The refresh token itself was refused (expired after 7 days, user
/// deactivated): only a new login can continue. Distinct from a network
/// failure, which leaves the session as it is.
class SessionExpiredException implements Exception {
  const SessionExpiredException();
}

/// Sign-up refused: the e-mail already belongs to an account.
class EmailTakenException implements Exception {
  const EmailTakenException();
}

/// Sign-up refused: the privacy notice accepted is no longer the current one.
class NoticeOutdatedException implements Exception {
  const NoticeOutdatedException();
}

/// Sign-up refused: the company chosen no longer exists (removed between
/// loading the list and sending).
class UnknownCompanyException implements Exception {
  const UnknownCompanyException();
}

/// Sign-up refused: the server's validation rejected a field (422).
class InvalidRegistrationException implements Exception {
  const InvalidRegistrationException();
}

/// The seam DioAuthRepository is tested behind (docs/CLAUDE.base.md —
/// Dependencies: "wrap third-party libs behind a thin interface").
abstract class AuthRepository {
  Future<Session> login({required String email, required String password});

  /// A new access token for [refreshToken], with the current worker standing.
  /// Throws [SessionExpiredException] when the server refuses it; a
  /// [DioException] without response means the device is offline.
  Future<RefreshedAccess> refreshAccessToken(String refreshToken);

  /// RF03: asks the server to e-mail a reset link. The server answers the same
  /// whether or not the e-mail is registered.
  Future<void> requestPasswordReset(String email);

  /// The companies a worker can choose from at sign-up (no login needed).
  Future<List<CompanyOption>> publicCompanies();

  /// Self-registration of a field worker, accepting the privacy notice of
  /// [noticeVersion]; a manager approves the account before it can work.
  /// Throws [EmailTakenException], [NoticeOutdatedException],
  /// [UnknownCompanyException] or [InvalidRegistrationException].
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String companyId,
    required int noticeVersion,
  });
}

class DioAuthRepository implements AuthRepository {
  DioAuthRepository(this._dio);

  final Dio _dio;

  @override
  Future<Session> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      final body = response.data!;
      final accessToken = body['access_token'] as String;
      return Session(
        accessToken: accessToken,
        refreshToken: body['refresh_token'] as String,
        role: _decodeRoleClaim(accessToken),
        consentRequired: body['consent_required'] as bool? ?? false,
        workerStanding: WorkerStanding.fromJson(body),
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        throw const InvalidCredentialsException();
      }
      rethrow;
    }
  }

  @override
  Future<RefreshedAccess> refreshAccessToken(String refreshToken) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final body = response.data!;
      return RefreshedAccess(
        accessToken: body['access_token'] as String,
        workerStanding: WorkerStanding.fromJson(body),
        consentRequired: body['consent_required'] as bool?,
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        throw const SessionExpiredException();
      }
      rethrow;
    }
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    await _dio.post<void>(
      '/auth/password-reset/request',
      data: {'email': email},
    );
  }

  @override
  Future<List<CompanyOption>> publicCompanies() async {
    final response = await _dio.get<List<dynamic>>(
      '/public/contractor-companies',
    );
    return [
      for (final item in response.data!.cast<Map<String, dynamic>>())
        CompanyOption(id: item['id'] as String, name: item['name'] as String),
    ];
  }

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String companyId,
    required int noticeVersion,
  }) async {
    try {
      await _dio.post<void>(
        '/auth/register',
        data: {
          'name': name,
          'email': email,
          'password': password,
          'contractor_company_id': companyId,
          'privacy_notice_version': noticeVersion,
        },
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 409) {
        switch (apiErrorCode(error)) {
          case 'EMAIL_TAKEN':
            throw const EmailTakenException();
          case 'NOTICE_OUTDATED':
            throw const NoticeOutdatedException();
        }
      }
      if (status == 422) throw _registrationRefusal(error);
      rethrow;
    }
  }
}

/// A 422 from `/auth/register`: field validation answers FastAPI's list of
/// errors, while the one plain-string `detail` it can send is the unknown
/// company (backend `app/api/auth.py::register`).
Exception _registrationRefusal(DioException error) {
  final data = error.response?.data;
  final isUnknownCompany = data is Map && data['detail'] is String;
  return isUnknownCompany
      ? const UnknownCompanyException()
      : const InvalidRegistrationException();
}

/// Reads the `role` claim off the access token without verifying the
/// signature — the backend is the actual authority on every request; the
/// app only needs it to route.
String _decodeRoleClaim(String accessToken) {
  final parts = accessToken.split('.');
  final normalized = base64Url.normalize(parts[1]);
  final payload =
      jsonDecode(utf8.decode(base64Url.decode(normalized)))
          as Map<String, dynamic>;
  return payload['role'] as String;
}

/// The token's claims, or null when it is not a decodable JWT (test tokens).
Map<String, dynamic>? _decodeClaims(String accessToken) {
  final parts = accessToken.split('.');
  if (parts.length != 3) return null;
  try {
    final normalized = base64Url.normalize(parts[1]);
    return jsonDecode(utf8.decode(base64Url.decode(normalized)))
        as Map<String, dynamic>;
  } on FormatException {
    return null;
  }
}
