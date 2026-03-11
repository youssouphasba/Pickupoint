/// Utils pour le formatage des numéros de téléphone

/// Masque le milieu du numéro : +221 77 XXX XX 45
String maskPhone(String phone) {
  if (phone.isEmpty) return phone;
  // Nettoyage basique, utile si le numéro a des espaces
  final cleaned = phone.replaceAll(' ', '');
  if (cleaned.length < 8) return phone;
  
  final visiblePrefix = 3;
  final visibleSuffix = 2;
  
  // Ex: +22177 XXXXX 45
  final start = cleaned.substring(0, visiblePrefix);
  final end   = cleaned.substring(cleaned.length - visibleSuffix);
  final hiddenLength = cleaned.length - visiblePrefix - visibleSuffix;
  final hidden = 'X' * hiddenLength;
  
  return '$start $hidden $end';
}


/// Normalise un numéro au format international SN.
/// Retourne `null` si invalide.
String? normalizePhone(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'\s+'), '');
  if (cleaned.isEmpty) return null;

  if (cleaned.startsWith('+221') && cleaned.length == 13) {
    return cleaned;
  }

  if (cleaned.startsWith('221') && cleaned.length == 12) {
    return '+$cleaned';
  }

  // 9 chiffres locaux -> +221XXXXXXXXX
  if (RegExp(r'^\d{9}$').hasMatch(cleaned)) {
    return '+221$cleaned';
  }

  return null;
}
