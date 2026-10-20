import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:route_monitor/auth/auth_repository.dart';

/// Abstract so tests never touch the platform keychain (docs/CLAUDE.base.md — Tests).
///
/// Holds the whole [Session] (both tokens, role, consent flag), not just the
/// access token: Android may kill the app at any moment — opening the camera
/// for an evidence photo is the classic case — and the worker must be able to
/// reopen it and keep working without network (RF35, RNF21). Before this the
/// session lived only in memory, so a restart away from coverage meant a
/// login screen that could not be passed.
abstract class SessionStorage {
  Future<void> saveSession(Session session);
  Future<Session?> readSession();
  Future<void> clear();
}

Map<String, Object> _sessionToJson(Session session) => {
  'access_token': session.accessToken,
  'refresh_token': session.refreshToken,
  'role': session.role,
  'consent_required': session.consentRequired,
};

Session _sessionFromJson(Map<String, dynamic> json) => Session(
  accessToken: json['access_token'] as String,
  refreshToken: json['refresh_token'] as String,
  role: json['role'] as String,
  consentRequired: json['consent_required'] as bool? ?? false,
);

class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _sessionKey = 'session';
  // Written by builds before the session was persisted whole; cleared on
  // logout so no stale token outlives "Sair".
  static const _legacyAccessTokenKey = 'access_token';

  @override
  Future<void> saveSession(Session session) => _storage.write(
    key: _sessionKey,
    value: jsonEncode(_sessionToJson(session)),
  );

  @override
  Future<Session?> readSession() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null) return null;
    return _sessionFromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: _legacyAccessTokenKey);
  }
}

class InMemorySessionStorage implements SessionStorage {
  Session? _session;

  @override
  Future<void> saveSession(Session session) async => _session = session;

  @override
  Future<Session?> readSession() async => _session;

  @override
  Future<void> clear() async => _session = null;
}
