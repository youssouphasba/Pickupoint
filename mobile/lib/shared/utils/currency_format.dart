import 'package:intl/intl.dart';

/// Formater un montant en XOF (FCFA)
/// ex: formatXof(15000) → "15 000 FCFA"
String formatXof(double amount) {
  final formatted = NumberFormat('#,###', 'fr_FR').format(amount);
  return '$formatted FCFA';
}
