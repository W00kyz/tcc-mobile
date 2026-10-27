import 'package:dio/dio.dart';

/// The consent state for the signed-in user: whether acceptance is still owed
/// and, when it is, the notice text to show (LGPD, RNF10).
class ConsentStatus {
  const ConsentStatus({
    required this.consentRequired,
    this.noticeTitle,
    this.noticeBody,
    this.noticeVersion,
  });

  final bool consentRequired;
  final String? noticeTitle;
  final String? noticeBody;
  final int? noticeVersion;
}

/// The privacy notice in force: what the sign-up screen shows and whose
/// [version] the sign-up sends back as accepted.
class PrivacyNotice {
  const PrivacyNotice({
    required this.version,
    required this.title,
    required this.body,
  });

  final int version;
  final String title;
  final String body;
}

abstract class ConsentRepository {
  Future<ConsentStatus> status();
  Future<void> accept();

  /// The current notice, readable before any account exists (sign-up).
  Future<PrivacyNotice> currentNotice();
}

class DioConsentRepository implements ConsentRepository {
  DioConsentRepository(this._dio);

  final Dio _dio;

  @override
  Future<ConsentStatus> status() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/auth/consent-status',
    );
    final body = response.data!;
    final notice = body['notice'] as Map<String, dynamic>?;
    return ConsentStatus(
      consentRequired: body['consent_required'] as bool? ?? false,
      noticeTitle: notice?['title'] as String?,
      noticeBody: notice?['body_markdown'] as String?,
      noticeVersion: notice?['version'] as int?,
    );
  }

  @override
  Future<void> accept() async {
    await _dio.post<void>('/auth/consent');
  }

  @override
  Future<PrivacyNotice> currentNotice() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/public/privacy-notice',
    );
    final body = response.data!;
    return PrivacyNotice(
      version: body['version'] as int,
      title: body['title'] as String,
      body: body['body_markdown'] as String,
    );
  }
}
