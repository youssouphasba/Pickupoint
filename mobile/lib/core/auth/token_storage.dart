import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persiste les tokens JWT dans le keystore sécurisé de l'OS.
class TokenStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kAccess  = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kLastPhone = 'last_account_phone';
  static const _kLastName = 'last_account_name';

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: _kAccess, value: accessToken),
      _storage.write(key: _kRefresh, value: refreshToken),
    ]);
  }

  Future<String?> getAccessToken()  => _storage.read(key: _kAccess);
  Future<String?> getRefreshToken() => _storage.read(key: _kRefresh);
  Future<String?> getLastPhone() => _storage.read(key: _kLastPhone);
  Future<String?> getLastName() => _storage.read(key: _kLastName);

  Future<void> saveLastAccount({
    required String phone,
    String? name,
  }) async {
    final normalizedPhone = phone.trim();
    if (normalizedPhone.isEmpty) return;
    await Future.wait([
      _storage.write(key: _kLastPhone, value: normalizedPhone),
      if ((name ?? '').trim().isNotEmpty)
        _storage.write(key: _kLastName, value: name!.trim()),
    ]);
  }

  Future<void> clearLastAccount() async {
    await Future.wait([
      _storage.delete(key: _kLastPhone),
      _storage.delete(key: _kLastName),
    ]);
  }

  Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: _kAccess),
      _storage.delete(key: _kRefresh),
    ]);
  }

  Future<bool> hasTokens() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
