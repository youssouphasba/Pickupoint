// Utils pour le formatage des numeros de telephone.

/// Normalise un numéro saisi librement vers le format E.164.
String normalizePhone(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[^\d+]'), '');
  if (cleaned.startsWith('00')) return '+${cleaned.substring(2)}';
  if (cleaned.startsWith('+')) return cleaned;
  if (RegExp(r'^[37]\d{8}$').hasMatch(cleaned)) return '+221$cleaned';
  if (RegExp(r'^0[67]\d{8}$').hasMatch(cleaned)) {
    return '+33${cleaned.substring(1)}';
  }
  if (RegExp(r'^(221|33)\d+$').hasMatch(cleaned)) return '+$cleaned';
  return cleaned;
}

bool isSupportedPhone(String raw) {
  final normalized = normalizePhone(raw);
  if (RegExp(r'^\+221\d{9}$').hasMatch(normalized)) return true;
  return RegExp(r'^\+33\d{9}$').hasMatch(normalized);
}

/// Masque le milieu du numero : +221 77 XXX XX 45
String maskPhone(String phone) {
  if (phone.isEmpty) return phone;

  final cleaned = phone.replaceAll(' ', '');
  if (cleaned.length < 8) return phone;

  const visiblePrefix = 3;
  const visibleSuffix = 2;

  final start = cleaned.substring(0, visiblePrefix);
  final end = cleaned.substring(cleaned.length - visibleSuffix);
  final hiddenLength = cleaned.length - visiblePrefix - visibleSuffix;
  final hidden = 'X' * hiddenLength;

  return '$start $hidden $end';
}
