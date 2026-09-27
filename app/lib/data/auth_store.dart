import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';

/// Keeps the login in the platform's encrypted storage. The app database is
/// plain SQLite, where a refresh token would be readable by anyone with the
/// file.
class AuthStore {
  AuthStore([this._storage = const FlutterSecureStorage()]);

  static const _key = 'auth';
  final FlutterSecureStorage _storage;

  Future<AuthTokens?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    return AuthTokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(AuthTokens tokens) =>
      _storage.write(key: _key, value: jsonEncode(tokens.toJson()));

  Future<void> clear() => _storage.delete(key: _key);
}
