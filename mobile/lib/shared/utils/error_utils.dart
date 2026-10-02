import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

String friendlyError(Object e) {
  if (e is LocalAuthException) {
    return switch (e.code) {
      LocalAuthExceptionCode.noBiometricsEnrolled ||
      LocalAuthExceptionCode.noCredentialsSet =>
        'Configurez une empreinte ou la reconnaissance faciale dans les réglages du téléphone, puis réessayez.',
      LocalAuthExceptionCode.userCanceled ||
      LocalAuthExceptionCode.systemCanceled ||
      LocalAuthExceptionCode.userRequestedFallback =>
        'Confirmation biométrique annulée. Vous pouvez utiliser votre PIN.',
      LocalAuthExceptionCode.temporaryLockout ||
      LocalAuthExceptionCode.biometricLockout =>
        'La biométrie est temporairement bloquée. Déverrouillez le téléphone avec son code, puis réessayez.',
      LocalAuthExceptionCode.authInProgress =>
        'Une confirmation biométrique est déjà en cours.',
      _ =>
        'La biométrie est momentanément indisponible. Réessayez ou utilisez votre PIN.',
    };
  }
  if (e is PlatformException) {
    return 'Cette fonctionnalité est momentanément indisponible sur cet appareil. Réessayez.';
  }
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String && detail.trim().isNotEmpty) return detail;
      if (detail is List) {
        return 'Vérifiez les informations saisies puis réessayez.';
      }
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
    }

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
        if (code == 401) {
          return 'Votre session doit être actualisée. Réessayez dans un instant.';
        }
        if (code != null) {
          return 'Erreur serveur ($code). Réessayez.';
        }
        return 'Erreur de connexion. Réessayez.';
    }
  }

  if (e is fb.FirebaseAuthException) {
    return _firebaseMessage(e.code, e.message);
  }

  return e
      .toString()
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
    case 'internal-error':
      return 'Le service de vérification est momentanément indisponible. Vérifiez le numéro et réessayez dans quelques instants.';
    case 'user-disabled':
      return 'Ce compte a été désactivé.';
    case 'credential-already-in-use':
      return 'Ce numéro est déjà utilisé par un autre compte.';
    default:
      return fallback?.replaceFirst(RegExp(r'^\[[\w/\-]+\]\s*'), '') ??
          'Erreur de vérification. Réessayez.';
  }
}
