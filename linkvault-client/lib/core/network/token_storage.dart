import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresAt,
    required this.refreshTokenExpiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessTokenExpiresAt;
  final DateTime refreshTokenExpiresAt;

  bool get shouldRefresh {
    final refreshWindow = DateTime.now().toUtc().add(
      const Duration(minutes: 1),
    );
    return !accessTokenExpiresAt.toUtc().isAfter(refreshWindow);
  }
}

abstract interface class TokenStorage {
  Future<TokenPair?> read();

  Future<void> save(TokenPair tokens);

  Future<void> clear();
}

class SecureTokenStorage implements TokenStorage {
  const SecureTokenStorage([this._storage = const FlutterSecureStorage()]);

  static const _accessTokenKey = 'linkvault.access_token';
  static const _refreshTokenKey = 'linkvault.refresh_token';
  static const _accessExpiresAtKey = 'linkvault.access_token_expires_at';
  static const _refreshExpiresAtKey = 'linkvault.refresh_token_expires_at';

  final FlutterSecureStorage _storage;

  @override
  Future<TokenPair?> read() async {
    final accessToken = await _storage.read(key: _accessTokenKey);
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    final accessExpiresAtRaw = await _storage.read(key: _accessExpiresAtKey);
    final refreshExpiresAtRaw = await _storage.read(key: _refreshExpiresAtKey);

    if (accessToken == null ||
        refreshToken == null ||
        accessExpiresAtRaw == null ||
        refreshExpiresAtRaw == null) {
      return null;
    }

    final accessExpiresAt = DateTime.tryParse(accessExpiresAtRaw);
    final refreshExpiresAt = DateTime.tryParse(refreshExpiresAtRaw);
    if (accessExpiresAt == null || refreshExpiresAt == null) {
      await clear();
      return null;
    }

    return TokenPair(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessTokenExpiresAt: accessExpiresAt,
      refreshTokenExpiresAt: refreshExpiresAt,
    );
  }

  @override
  Future<void> save(TokenPair tokens) async {
    await _storage.write(key: _accessTokenKey, value: tokens.accessToken);
    await _storage.write(key: _refreshTokenKey, value: tokens.refreshToken);
    await _storage.write(
      key: _accessExpiresAtKey,
      value: tokens.accessTokenExpiresAt.toIso8601String(),
    );
    await _storage.write(
      key: _refreshExpiresAtKey,
      value: tokens.refreshTokenExpiresAt.toIso8601String(),
    );
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _accessExpiresAtKey);
    await _storage.delete(key: _refreshExpiresAtKey);
  }
}
