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
