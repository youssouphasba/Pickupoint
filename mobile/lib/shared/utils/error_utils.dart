import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

/// Extrait un message d'erreur court et lisible à afficher à l'utilisateur.
String friendlyError(Object e) {
  // ── Dio (réponse API backend) ──
  if (e is DioException) {
    // Le backend renvoie { "detail": "..." } — on l'utilise directement
    final data = e.response?.data;
    if (data is Map) {
      final detail = data['detail'];
      if (detail != null) return detail.toString();
      final message = data['message'];
      if (message != null) return message.toString();
    }
    // Erreurs réseau sans réponse
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Délai de connexion dépassé. Vérifiez votre connexion internet.';
      case DioExceptionType.connectionError:
        return 'Impossible de joindre le serveur. Vérifiez votre connexion.';
      case DioExceptionType.cancel:
        return 'Requête annulée.';
      default:
        final code = e.response?.statusCode;
        if (code != null) {
          return 'Erreur serveur ($code). Réessayez.';
        }
        return 'Erreur de connexion. Réessayez.';
    }
  }

  // ── Firebase Auth ──
  if (e is fb.FirebaseAuthException) {
    return _firebaseMessage(e.code, e.message);
  }

  // ── Exception générique ──
  final s = e.toString();
  // Retire les préfixes techniques courants
  return s
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceFirst(RegExp(r'^FormatException:\s*'), '')
      .replaceFirst(RegExp(r'^\[[\w/\-]+\]\s*'), '');
}

String _firebaseMessage(String code, String? fallback) {
  switch (code) {
    case 'invalid-verification-code':
      return 'Code de vérification incorrect.';
    case 'invalid-verification-id':
      return 'Session de vérification expirée. Renvoyez le code.';
    case 'session-expired':
      return 'Session expirée. Renvoyez le code.';
    case 'too-many-requests':
      return 'Trop de tentatives. Réessayez dans quelques minutes.';
    case 'network-request-failed':
      return 'Pas de connexion internet.';
    case 'invalid-phone-number':
      return 'Numéro de téléphone invalide.';
    case 'quota-exceeded':
      return 'Limite de SMS atteinte. Réessayez plus tard.';
    case 'user-disabled':
      return 'Ce compte a été désactivé.';
    case 'credential-already-in-use':
      return 'Ce numéro est déjà utilisé par un autre compte.';
    default:
      return fallback?.replaceFirst(RegExp(r'^\[[\w/\-]+\]\s*'), '') ??
          'Erreur de vérification. Réessayez.';
  }
}
