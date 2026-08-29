import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Abstract so tests never touch the platform keychain (docs/CLAUDE.base.md — Tests).
abstract class SessionStorage {
  Future<void> saveAccessToken(String token);
  Future<String?> readAccessToken();
  Future<void> clear();
}

class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _accessTokenKey = 'access_token';

  @override
  Future<void> saveAccessToken(String token) =>
      _storage.write(key: _accessTokenKey, value: token);

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  @override
  Future<void> clear() => _storage.delete(key: _accessTokenKey);
}

class InMemorySessionStorage implements SessionStorage {
  String? _token;

  @override
  Future<void> saveAccessToken(String token) async => _token = token;

  @override
  Future<String?> readAccessToken() async => _token;

  @override
  Future<void> clear() async => _token = null;
}
