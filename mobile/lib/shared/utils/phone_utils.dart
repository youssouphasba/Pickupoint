// Utils pour le formatage des numeros de telephone.

/// Normalise un numero senegalais saisi librement vers le format E.164 (+221XXXXXXXXX).
/// Gere : "77 123 45 67", "0077 123 45 67", "+221 77 123 45 67", "77-123-45-67".
String normalizePhone(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[\s\-\.]'), '');
  if (cleaned.startsWith('+221')) return cleaned;
  if (cleaned.startsWith('00221')) return '+${cleaned.substring(2)}';
  if (RegExp(r'^[73]\d{8}$').hasMatch(cleaned)) return '+221$cleaned';
  return cleaned;
}

/// Masque le milieu du numero : +221 77 XXX XX 45
String maskPhone(String phone) {
  if (phone.isEmpty) return phone;

  // Nettoyage basique, utile si le numero a des espaces.
  final cleaned = phone.replaceAll(' ', '');
  if (cleaned.length < 8) return phone;

  const visiblePrefix = 3;
  const visibleSuffix = 2;

  // Ex: +22177 XXXXX 45
  final start = cleaned.substring(0, visiblePrefix);
  final end = cleaned.substring(cleaned.length - visibleSuffix);
  final hiddenLength = cleaned.length - visiblePrefix - visibleSuffix;
  final hidden = 'X' * hiddenLength;

  return '$start $hidden $end';
}
