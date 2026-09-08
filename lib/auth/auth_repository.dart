import 'dart:convert';

import 'package:dio/dio.dart';

class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.role,
    this.consentRequired = false,
  });

  final String accessToken;
  final String refreshToken;
  final String role;

  /// True when the backend's login response flagged that this user still owes
  /// consent to the current data-processing notice (LGPD, RNF10). The router
  /// guard holds such a session on `/consentimento` until it is cleared.
  final bool consentRequired;

  Session copyWith({bool? consentRequired}) => Session(
    accessToken: accessToken,
    refreshToken: refreshToken,
    role: role,
    consentRequired: consentRequired ?? this.consentRequired,
  );
}

class InvalidCredentialsException implements Exception {
  const InvalidCredentialsException();
}

// A single-method interface is deliberate here, not an oversight: it is the
// seam DioAuthRepository is tested behind (docs/CLAUDE.base.md —
// Dependencies: "wrap third-party libs behind a thin interface").
// ignore: one_member_abstracts
abstract class AuthRepository {
  Future<Session> login({required String email, required String password});
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
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        throw const InvalidCredentialsException();
      }
      rethrow;
    }
  }
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
