import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persiste les tokens JWT dans le keystore sécurisé de l'OS.
class TokenStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kLastPhone = 'last_account_phone';
  static const _kLastName = 'last_account_name';
  static const _kBiometricPhone = 'biometric_account_phone';
  static const _kBiometricPin = 'biometric_account_pin';

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: _kAccess, value: accessToken),
      _storage.write(key: _kRefresh, value: refreshToken),
    ]);
  }

  Future<String?> getAccessToken() => _storage.read(key: _kAccess);
  Future<String?> getRefreshToken() => _storage.read(key: _kRefresh);
  Future<String?> getLastPhone() => _storage.read(key: _kLastPhone);
  Future<String?> getLastName() => _storage.read(key: _kLastName);
  Future<String?> getBiometricPhone() => _storage.read(key: _kBiometricPhone);
  Future<String?> getBiometricPin() => _storage.read(key: _kBiometricPin);

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

  Future<void> saveBiometricCredentials({
    required String phone,
    required String pin,
  }) async {
    final normalizedPhone = phone.trim();
    final normalizedPin = pin.trim();
    if (normalizedPhone.isEmpty || normalizedPin.isEmpty) return;
    await Future.wait([
      _storage.write(key: _kBiometricPhone, value: normalizedPhone),
      _storage.write(key: _kBiometricPin, value: normalizedPin),
    ]);
  }

  Future<void> clearBiometricCredentials() async {
    await Future.wait([
      _storage.delete(key: _kBiometricPhone),
      _storage.delete(key: _kBiometricPin),
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
