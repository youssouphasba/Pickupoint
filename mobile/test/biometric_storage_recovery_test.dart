import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pickupoint/core/auth/biometric_auth_service.dart';
import 'package:pickupoint/core/auth/token_storage.dart';
import 'package:pickupoint/shared/utils/error_utils.dart';

class _Storage extends TokenStorage {
  Object? readError;
  Object? writeError;
  bool clearFails = false;
  int biometricClears = 0;
  int tokenClears = 0;
  String? phone = '+221770000000';
  String? pin = '1234';

  @override
  Future<String?> getBiometricPhone() async {
    if (readError != null) throw readError!;
    return phone;
  }

  @override
  Future<String?> getBiometricPin() async => pin;

  @override
  Future<void> clearBiometricCredentials() async {
    biometricClears++;
    if (clearFails) throw StateError('unavailable');
    phone = null;
    pin = null;
    readError = null;
  }

  @override
  Future<void> clearTokens() async => tokenClears++;

  @override
  Future<void> saveBiometricCredentials({
    required String phone,
    required String pin,
  }) async {
    if (writeError != null) throw writeError!;
    this.phone = phone;
    this.pin = pin;
  }
}

class _Service extends BiometricAuthService {
  _Service(super.storage);

  @override
  Future<bool> isSupported() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final decryptionError = PlatformException(
    code: 'Exception encountered',
    message: 'read, javax.crypto.BadPaddingException: BAD_DECRYPT',
  );

  test('unreadable biometrics are cleared without clearing session', () async {
    final storage = _Storage()..readError = decryptionError;
    final service = _Service(storage);
    await expectLater(service.canUseForPhone('+221770000000'),
        throwsA(isA<BiometricStorageException>()));
    expect(storage.biometricClears, 1);
    expect(storage.tokenClears, 0);
    expect(await service.canUseForPhone('+221770000000'), isFalse);
    await service.saveCredentials(phone: '+221770000000', pin: '5678');
    expect(await service.canUseForPhone('+221770000000'), isTrue);
  });

  test('failed cleanup still produces actionable error', () async {
    final storage = _Storage()
      ..readError = decryptionError
      ..clearFails = true;
    await expectLater(_Service(storage).canUseForPhone('+221770000000'),
        throwsA(isA<BiometricStorageException>()));
    expect(storage.tokenClears, 0);
  });

  test('unrelated failure does not erase biometric credentials', () async {
    final storage = _Storage()
      ..readError = PlatformException(code: 'unavailable');
    await expectLater(_Service(storage).canUseForPhone('+221770000000'),
        throwsA(isA<PlatformException>()));
    expect(storage.biometricClears, 0);
  });

  test('write failure does not claim activation succeeded', () async {
    final storage = _Storage()..writeError = decryptionError;
    await expectLater(
        _Service(storage).saveCredentials(phone: '+221770000000', pin: '1234'),
        throwsA(isA<BiometricStorageException>()));
    expect(storage.tokenClears, 0);
  });

  test('UI never exposes platform stack traces', () {
    expect(friendlyError(decryptionError), isNot(contains('BAD_DECRYPT')));
    expect(
        friendlyError(decryptionError), isNot(contains('PlatformException')));
    expect(friendlyError(const BiometricStorageException()), contains('PIN'));
  });
}
