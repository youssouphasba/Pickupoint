import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'token_storage.dart';

class BiometricAuthService {
  BiometricAuthService(this._storage);

  final TokenStorage _storage;
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> canUseForPhone(String phone) async {
    final supported = await isSupported();
    if (!supported) return false;

    final savedPhone = await _storage.getBiometricPhone();
    final savedPin = await _storage.getBiometricPin();
    return savedPhone == phone && savedPin != null && savedPin.isNotEmpty;
  }

  Future<String?> getPinAfterAuthentication() async {
    final authenticated = await _auth.authenticate(
      localizedReason: 'Confirmez votre identité pour ouvrir Denkma.',
      biometricOnly: false,
      persistAcrossBackgrounding: true,
    );
    if (!authenticated) return null;
    return _storage.getBiometricPin();
  }

  Future<void> saveCredentials({
    required String phone,
    required String pin,
  }) {
    return _storage.saveBiometricCredentials(phone: phone, pin: pin);
  }

  Future<void> disable() => _storage.clearBiometricCredentials();
}
