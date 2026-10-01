import 'package:flutter/services.dart';

class PhoneContactSelection {
  const PhoneContactSelection({required this.name, required this.phone});

  final String name;
  final String phone;
}

class PhoneContactPicker {
  static const _channel = MethodChannel('com.denkma.app/contact_picker');

  static Future<PhoneContactSelection?> pick() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('pickPhone');
    if (result == null) return null;
    final rawPhone = result['phone'];
    if (rawPhone is! String || rawPhone.trim().isEmpty) {
      throw PlatformException(code: 'contact_without_phone');
    }
    return PhoneContactSelection(
      name: result['name'] is String ? (result['name'] as String).trim() : '',
      phone: rawPhone.trim(),
    );
  }
}
