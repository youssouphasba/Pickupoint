import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/shared/utils/phone_utils.dart';

void main() {
  test('normalizePhone converts Senegal local numbers to E.164', () {
    expect(normalizePhone('77 123 45 67'), '+221771234567');
    expect(normalizePhone('+221 77 123 45 67'), '+221771234567');
  });

  test('maskPhone keeps only prefix and suffix visible', () {
    expect(maskPhone('+221771234567'), '+22 XXXXXXXX 67');
  });
}
