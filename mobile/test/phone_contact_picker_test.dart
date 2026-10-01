import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pickupoint/core/contacts/phone_contact_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.denkma.app/contact_picker');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Android requests only the system phone picker and selected fields',
      () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {'name': ' Awa ', 'phone': ' +221 77 000 00 00 '};
    });
    final selection = await PhoneContactPicker.pick();
    expect(selection!.name, 'Awa');
    expect(selection.phone, '+221 77 000 00 00');
    expect(calls.single.method, 'pickPhone');
    expect(calls.single.arguments, isNull);
  });

  test('cancelling does not create or replace a contact', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await PhoneContactPicker.pick(), isNull);
  });

  test('selection without a phone is rejected', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => {'name': 'Awa'});
    await expectLater(
        PhoneContactPicker.pick(), throwsA(isA<PlatformException>()));
  });

  test('native picker errors remain recoverable', () async {
    messenger.setMockMethodCallHandler(channel,
        (_) async => throw PlatformException(code: 'picker_unavailable'));
    await expectLater(
        PhoneContactPicker.pick(), throwsA(isA<PlatformException>()));
    messenger.setMockMethodCallHandler(
        channel, (_) async => {'name': '', 'phone': '770000000'});
    expect((await PhoneContactPicker.pick())!.phone, '770000000');
  });
}
