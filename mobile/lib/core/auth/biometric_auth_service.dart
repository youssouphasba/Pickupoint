import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'token_storage.dart';

final biometricAuthServiceProvider = Provider<BiometricAuthService>(
    (ref) => BiometricAuthService(TokenStorage()));

class BiometricStorageException implements Exception {
  const BiometricStorageException();

  @override
  String toString() =>
      'La connexion biométrique doit être réactivée sur cet appareil. Connectez-vous avec votre PIN.';
}

class BiometricAuthService {
  BiometricAuthService(this._storage);

  final TokenStorage _storage;
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } on PlatformException {
      return false;
    } on LocalAuthException {
      return false;
    }
  }

  Future<bool> canUseForPhone(String phone) async {
    if (phone.trim().isEmpty) return false;
    final supported = await isSupported();
    if (!supported) return false;

    return _readCredentials(() async {
      final savedPhone = await _storage.getBiometricPhone();
      final savedPin = await _storage.getBiometricPin();
      return savedPhone == phone && savedPin != null && savedPin.isNotEmpty;
    });
  }

  bool _isDecryptionFailure(PlatformException error) {
    final message = '${error.message} ${error.details}'.toLowerCase();
    return message.contains('badpaddingexception') ||
        message.contains('bad_decrypt') ||
        message.contains('failed to unwrap key') ||
        message.contains('keypermanentlyinvalidatedexception');
  }

  Future<T> _readCredentials<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on PlatformException catch (error) {
      if (!_isDecryptionFailure(error)) rethrow;
      try {
        await _storage.clearBiometricCredentials();
      } catch (_) {}
      throw const BiometricStorageException();
    }
  }

  Future<String?> getPinAfterAuthentication() async {
    final authenticated = await _auth.authenticate(
      localizedReason: 'Confirmez votre identité pour ouvrir Denkma.',
      biometricOnly: false,
      persistAcrossBackgrounding: true,
    );
    if (!authenticated) return null;
    return _readCredentials(_storage.getBiometricPin);
  }

  Future<bool> authenticateForSetup() => _auth.authenticate(
        localizedReason:
            'Confirmez votre identité pour activer la connexion biométrique.',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

  Future<void> saveCredentials({
    required String phone,
    required String pin,
  }) async {
    try {
      await _storage.saveBiometricCredentials(phone: phone, pin: pin);
    } on PlatformException catch (error) {
      if (_isDecryptionFailure(error)) {
        throw const BiometricStorageException();
      }
      rethrow;
    }
  }

  Future<void> disable() => _storage.clearBiometricCredentials();

  Future<void> updatePinIfEnabled(String phone, String pin) async {
    if (await canUseForPhone(phone)) {
      await saveCredentials(phone: phone, pin: pin);
    }
  }
}
