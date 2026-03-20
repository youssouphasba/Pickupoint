import 'package:intl/intl.dart';

/// Formater une date en français
/// ex: formatDate(dt) → "28 fév. 2026 à 14:30"
String formatDate(DateTime dt) =>
    DateFormat('d MMM yyyy à HH:mm', 'fr_FR').format(dt.toLocal());
