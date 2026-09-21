import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/shared/utils/phone_utils.dart';

void main() {
  test('normalizePhone converts Senegal local numbers to E.164', () {
    expect(normalizePhone('77 123 45 67'), '+221771234567');
    expect(normalizePhone('+221 77 123 45 67'), '+221771234567');
    expect(normalizePhone('70 123 45 67'), '+221701234567');
    expect(normalizePhone('76 123 45 67'), '+221761234567');
    expect(isSupportedPhone('+221701234567'), true);
    expect(isSupportedPhone('+221751234567'), true);
    expect(isSupportedPhone('+221761234567'), true);
    expect(isSupportedPhone('+221781234567'), true);
  });

  test('maskPhone keeps only prefix and suffix visible', () {
    expect(maskPhone('+221771234567'), '+22 XXXXXXXX 67');
  });
}
