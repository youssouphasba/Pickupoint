import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../api/api_client.dart';
import '../models/user.dart';
import 'token_storage.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.accessToken,
    this.refreshToken,
    this.error,
    this.activeView, // vue active : 'client' | 'driver' | 'relay_agent' | 'admin'
  });

  final AuthStatus status;
  final User? user;
  final String? accessToken;
  final String? refreshToken;
  final String? error;

  /// Vue courante affichée dans l'app.
  /// Par défaut = rôle réel de l'utilisateur.
  /// Un driver/relay_agent peut basculer en 'client' sans perdre son rôle.
  final String? activeView;

  /// Rôle effectif pour le routing : activeView ?? user.role ?? 'client'
  String get effectiveRole => activeView ?? user?.role ?? 'client';

  /// Vrai si l'utilisateur a un rôle professionnel (driver ou relay_agent)
  /// et peut donc basculer vers la vue client.
  bool get canSwitchToClient =>
      user?.role == 'driver' || user?.role == 'relay_agent';

  bool get isAuthenticated => status == AuthStatus.authenticated;

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    String? accessToken,
    String? refreshToken,
    String? error,
    String? activeView,
    bool clearActiveView = false,
  }) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        error: error,
        activeView: clearActiveView ? null : (activeView ?? this.activeView),
      );
}

/// Provider global de l'état d'authentification.
final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

/// Raccourci : provider de l'API client configuré avec le token courant.
final apiClientProvider = Provider<ApiClient>((ref) {
  final auth = ref.watch(authProvider).valueOrNull;
  return ApiClient(
    token: auth?.accessToken,
    refreshToken: () =>
        ref.read(authProvider.notifier).refreshAndGetAccessToken(),
  );
});

class AuthNotifier extends AsyncNotifier<AuthState> {
  final _storage = TokenStorage();

  @override
  Future<AuthState> build() async {
    return _tryLoadFromStorage();
  }

  /// Chargement automatique au démarrage.
  Future<AuthState> _tryLoadFromStorage() async {
    final accessToken = await _storage.getAccessToken();
    final refreshToken = await _storage.getRefreshToken();

    if (accessToken == null) {
      return const AuthState(status: AuthStatus.unauthenticated);
    }

    try {
      final client = ApiClient(token: accessToken);
      final res = await client.getMe();
      final user = User.fromJson(res.data as Map<String, dynamic>);
      return AuthState(
        status: AuthStatus.authenticated,
        user: user,
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
    } catch (e) {
      if (e is DioException &&
          e.response?.statusCode == 401 &&
          refreshToken != null) {
        try {
          final refreshClient = ApiClient();
          final refreshRes = await refreshClient.refreshToken(refreshToken);
          final data = refreshRes.data as Map<String, dynamic>;
          final newAccessRaw = data['access_token'];
          if (newAccessRaw == null) {
            throw Exception("Jeton d'accès manquant lors du rafraîchissement.");
          }
          final newAccess = newAccessRaw.toString();

          await _storage.saveTokens(
            accessToken: newAccess,
            refreshToken: refreshToken,
          );

          final meClient = ApiClient(token: newAccess);
          final meRes = await meClient.getMe();
          final user = User.fromJson(meRes.data as Map<String, dynamic>);
          return AuthState(
            status: AuthStatus.authenticated,
            user: user,
            accessToken: newAccess,
            refreshToken: refreshToken,
          );
        } catch (_) {}
      }
      await _storage.clearTokens();
      return const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  /// Recharge le profil utilisateur depuis le serveur
  Future<void> fetchMe() async {
    final current = state.valueOrNull;
    if (current == null || !current.isAuthenticated) return;

    try {
      final client = ApiClient(token: current.accessToken);
      final res = await client.getMe();
      final user = User.fromJson(res.data as Map<String, dynamic>);
      state = AsyncData(current.copyWith(user: user));
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        await refreshAccessToken();
        final refreshed = state.valueOrNull;
        if (refreshed == null || !refreshed.isAuthenticated) {
          return;
        }
        try {
          final retryClient = ApiClient(token: refreshed.accessToken);
          final retryRes = await retryClient.getMe();
          final retryUser =
              User.fromJson(retryRes.data as Map<String, dynamic>);
          state = AsyncData(refreshed.copyWith(user: retryUser));
        } catch (_) {
          await logout();
        }
      }
    }
  }

  // ── Firebase Phone Auth ──────────────────────────────────────────────────

  String? _firebaseVerificationId;

  /// Étape 1 Firebase — envoie le SMS via Firebase Auth
  Future<void> startFirebasePhoneAuth(
    String phone, {
    required void Function(String verificationId) onCodeSent,
    required void Function(String error) onError,
    required void Function(fb.PhoneAuthCredential credential) onAutoVerified,
  }) async {
    state = const AsyncLoading();
    await fb.FirebaseAuth.instance.setLanguageCode('fr');
    await fb.FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (fb.PhoneAuthCredential credential) {
        // Auto-verification Android
        onAutoVerified(credential);
      },
      verificationFailed: (fb.FirebaseAuthException e) {
        state = AsyncData(AuthState(
          status: AuthStatus.unauthenticated,
          error: e.message ?? 'Erreur Firebase',
        ));
        onError(e.message ?? 'Erreur de vérification');
      },
      codeSent: (String verificationId, int? resendToken) {
        _firebaseVerificationId = verificationId;
        state = const AsyncData(AuthState(status: AuthStatus.unauthenticated));
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _firebaseVerificationId = verificationId;
      },
    );
  }

  /// Étape 2 Firebase — vérifie le code SMS et connecte au backend Denkma
  Future<String?> verifyFirebaseOtp(String smsCode) async {
    if (_firebaseVerificationId == null) {
      throw Exception('Aucune vérification en cours');
    }
    state = const AsyncLoading();
    try {
      final credential = fb.PhoneAuthProvider.credential(
        verificationId: _firebaseVerificationId!,
        smsCode: smsCode,
      );
      return await signInWithFirebaseCredential(credential);
    } catch (e) {
      state = AsyncData(AuthState(
        status: AuthStatus.unauthenticated,
        error: _extractError(e),
      ));
      rethrow;
    }
  }

  /// Sign in with Firebase credential, then authenticate with Denkma backend.
  /// Returns registration_token if new user, null if logged in.
  Future<String?> signInWithFirebaseCredential(
      fb.PhoneAuthCredential credential) async {
    try {
      final userCredential =
          await fb.FirebaseAuth.instance.signInWithCredential(credential);
      final idToken = await userCredential.user?.getIdToken();
      if (idToken == null) {
        throw Exception('Impossible de récupérer le token Firebase');
      }

      // Envoyer l'ID token au backend Denkma
      final client = ApiClient();
      final res = await client.firebaseLogin(idToken);
      final data = res.data as Map<String, dynamic>;

      if (data['is_new_user'] == true) {
        state = const AsyncData(AuthState(status: AuthStatus.unauthenticated));
        return data['registration_token'] as String;
      }

      final sessionData = data['session'] as Map<String, dynamic>?;
      if (sessionData == null) {
        throw Exception("Session manquante dans la réponse API.");
      }
      await _handleTokenResponse(sessionData);
      return null;
    } catch (e) {
      state = AsyncData(AuthState(
        status: AuthStatus.unauthenticated,
        error: _extractError(e),
      ));
      rethrow;
    }
  }

  /// Étape Finale — Complete Registration
  Future<void> completeRegistration({
    required String token,
    required String name,
    required String pin,
    String? referralCode,
  }) async {
    state = const AsyncLoading();
    try {
      final client = ApiClient();
      final res = await client.completeRegistration({
        'registration_token': token,
        'name': name,
        'pin': pin,
        'accepted_legal': true,
        if (referralCode != null && referralCode.trim().isNotEmpty)
          'referral_code': referralCode.trim().toUpperCase(),
      });
      await _handleTokenResponse(res.data as Map<String, dynamic>);
    } catch (e) {
      state = AsyncData(AuthState(
          status: AuthStatus.unauthenticated, error: _extractError(e)));
      rethrow;
    }
  }

  /// Étape 2 bis — Connexion directe avec le PIN
  Future<void> loginPin(String phone, String pin) async {
    state = const AsyncLoading();
    try {
      final client = ApiClient();
      final res = await client.loginPin({'phone': phone, 'pin': pin});
      await _handleTokenResponse(res.data as Map<String, dynamic>);
    } catch (e) {
      state = AsyncData(AuthState(
          status: AuthStatus.unauthenticated, error: _extractError(e)));
      rethrow;
    }
  }

  Future<void> _handleTokenResponse(Map<String, dynamic> data) async {
    final accessTokenRaw = data['access_token'];
    final refreshTokenRaw = data['refresh_token'];

    if (accessTokenRaw == null || refreshTokenRaw == null) {
      final errorMsg = data['detail'] ??
          data['message'] ??
          'Formats absents de la réponse API.';
      throw Exception("Échec de connexion : $errorMsg");
    }

    final accessToken = accessTokenRaw.toString();
    final refreshToken = refreshTokenRaw.toString();

    final userData = data['user'];
    if (userData == null) throw Exception("Profil utilisateur manquant.");

    final user = User.fromJson(userData as Map<String, dynamic>);

    await _storage.saveTokens(
        accessToken: accessToken, refreshToken: refreshToken);
    await _storage.saveLastAccount(
      phone: user.phone,
      name: user.fullName,
    );

    state = AsyncData(AuthState(
      status: AuthStatus.authenticated,
      user: user,
      accessToken: accessToken,
      refreshToken: refreshToken,
    ));
  }

  /// Mise à jour du profil (E-mail et Type)
  Future<void> updateProfile(
      {String? email,
      String? userType,
      Map<String, dynamic>? notificationPrefs,
      String? language,
      String? bio}) async {
    final current = state.valueOrNull;
    if (current == null || !current.isAuthenticated) return;

    state = const AsyncLoading();
    try {
      final client = ApiClient(token: current.accessToken);
      final body = <String, dynamic>{};
      if (email != null) body['email'] = email;
      if (userType != null) body['user_type'] = userType;
      if (notificationPrefs != null) {
        body['notification_prefs'] = notificationPrefs;
      }
      if (language != null) body['language'] = language;
      if (bio != null) body['bio'] = bio;

      final res = await client.updateProfile(body);
      final updatedUser = User.fromJson(res.data as Map<String, dynamic>);

      state = AsyncData(current.copyWith(user: updatedUser));
    } catch (e) {
      state = AsyncData(current.copyWith(error: _extractError(e)));
      rethrow;
    }
  }

  /// Rafraîchit le token d'accès.
  Future<void> refreshAccessToken() async {
    await refreshAndGetAccessToken();
  }

  Future<String?> refreshAndGetAccessToken() async {
    final current = state.valueOrNull;
    if (current?.refreshToken == null) return null;

    try {
      final client = ApiClient();
      final res = await client.refreshToken(current!.refreshToken!);
      final data = res.data as Map<String, dynamic>;
      final newAccessRaw = data['access_token'];
      if (newAccessRaw == null) {
        throw Exception("Jeton d'accès manquant lors du rafraîchissement.");
      }
      final newAccess = newAccessRaw.toString();

      await _storage.saveTokens(
        accessToken: newAccess,
        refreshToken: current.refreshToken!,
      );

      state = AsyncData(current.copyWith(accessToken: newAccess));
      return newAccess;
    } catch (_) {
      await logout();
      return null;
    }
  }

  /// Bascule entre la vue professionnelle et la vue client.
  void switchView(String view) {
    final current = state.valueOrNull;
    if (current == null || !current.isAuthenticated) return;
    state = AsyncData(current.copyWith(activeView: view));
  }

  /// Met à jour la disponibilité du livreur localement après appel API.
  void updateUserAvailability(bool isAvailable) {
    final current = state.valueOrNull;
    if (current?.user == null) return;
    state = AsyncData(current!.copyWith(
      user: current.user!.copyWith(isAvailable: isAvailable),
    ));
  }

  Future<void> deleteAccount() async {
    final current = state.valueOrNull;
    if (current == null || !current.isAuthenticated) return;

    state = const AsyncLoading();
    try {
      final client = ApiClient(token: current.accessToken);
      await client.deleteAccount();
      await logout();
    } catch (e) {
      state = AsyncData(current.copyWith(error: _extractError(e)));
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await fb.FirebaseAuth.instance.signOut();
    } catch (_) {}
    await _storage.clearTokens();
    state = const AsyncData(AuthState(status: AuthStatus.unauthenticated));
  }

  String _extractError(Object e) {
    if (e is DioException) {
      if (e.response?.data != null && e.response!.data is Map) {
        final data = e.response!.data as Map;
        final detail = data['detail'];
        if (detail != null) return detail.toString();
        final message = data['message'];
        if (message != null) return message.toString();
      }
      return 'Erreur de connexion : ${e.response?.statusCode ?? e.message}';
    }
    return e.toString().replaceAll('Exception: ', '');
  }
}
