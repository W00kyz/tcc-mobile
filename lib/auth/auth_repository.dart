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

  /// The user id (`sub` claim) behind this session, or '' for a token that is
  /// not a readable JWT. Keys per-user data on the device (route snapshot).
  String get userId => _decodeClaims(accessToken)?['sub'] as String? ?? '';

  /// True when the backend's login response flagged that this user still owes
  /// consent to the current data-processing notice (LGPD, RNF10). The router
  /// guard holds such a session on `/consentimento` until it is cleared.
  final bool consentRequired;

  Session copyWith({String? accessToken, bool? consentRequired}) => Session(
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken,
    role: role,
    consentRequired: consentRequired ?? this.consentRequired,
  );
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

/// The seam DioAuthRepository is tested behind (docs/CLAUDE.base.md —
/// Dependencies: "wrap third-party libs behind a thin interface").
abstract class AuthRepository {
  Future<Session> login({required String email, required String password});

  /// A new access token for [refreshToken]. Throws [SessionExpiredException]
  /// when the server refuses it; a [DioException] without response means the
  /// device is offline.
  Future<String> refreshAccessToken(String refreshToken);

  /// RF03: asks the server to e-mail a reset link. The server answers the same
  /// whether or not the e-mail is registered.
  Future<void> requestPasswordReset(String email);
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

  @override
  Future<String> refreshAccessToken(String refreshToken) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      return response.data!['access_token'] as String;
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
