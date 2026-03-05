import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        status:       status       ?? this.status,
        user:         user         ?? this.user,
        accessToken:  accessToken  ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        error:        error,
        activeView:   clearActiveView ? null : (activeView ?? this.activeView),
      );
}

/// Provider global de l'état d'authentification.
final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

/// Raccourci : provider de l'API client configuré avec le token courant.
final apiClientProvider = Provider<ApiClient>((ref) {
  final auth = ref.watch(authProvider).valueOrNull;
  return ApiClient(token: auth?.accessToken);
});

class AuthNotifier extends AsyncNotifier<AuthState> {
  final _storage = TokenStorage();

  @override
  Future<AuthState> build() async {
    return _tryLoadFromStorage();
  }

  /// Chargement automatique au démarrage.
  Future<AuthState> _tryLoadFromStorage() async {
    final accessToken  = await _storage.getAccessToken();
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
    } catch (_) {
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
      // Si erreur auth, on déconnecte
      if (e.toString().contains('401')) {
        await logout();
      }
    }
  }

  /// Étape 1 — demande OTP
  Future<void> requestOtp(String phone) async {
    state = const AsyncLoading();
    try {
      final client = ApiClient();
      await client.requestOtp({'phone': phone});
      // Revenir à unauthenticated pour afficher OtpScreen
      state = AsyncData(const AuthState(status: AuthStatus.unauthenticated));
    } catch (e) {
      state = AsyncData(AuthState(
        status: AuthStatus.unauthenticated,
        error: _extractError(e),
      ));
      rethrow;
    }
  }

  /// Étape 2 — vérification OTP → login
  Future<void> verifyOtp(String phone, String otp, {bool acceptedLegal = false}) async {
    state = const AsyncLoading();
    try {
      final client = ApiClient();
      final res = await client.verifyOtp({
        'phone': phone,
        'otp': otp,
        'accepted_legal': acceptedLegal,
      });
      final data = res.data as Map<String, dynamic>;

      final accessTokenRaw = data['access_token'];
      final refreshTokenRaw = data['refresh_token'];

      if (accessTokenRaw == null || refreshTokenRaw == null) {
        final errorMsg = data['detail'] ?? data['message'] ?? 'Formats de jetons absents de la réponse API.';
        throw Exception("Échec de connexion : \$errorMsg");
      }

      final accessToken  = accessTokenRaw.toString();
      final refreshToken = refreshTokenRaw.toString();
      
      final userData = data['user'];
      if (userData == null) {
        throw Exception("Profil utilisateur manquant dans la réponse API.");
      }

      final user = User.fromJson(userData as Map<String, dynamic>);

      await _storage.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

      state = AsyncData(AuthState(
        status: AuthStatus.authenticated,
        user: user,
        accessToken: accessToken,
        refreshToken: refreshToken,
      ));
    } catch (e) {
      state = AsyncData(AuthState(
        status: AuthStatus.unauthenticated,
        error: _extractError(e),
      ));
      rethrow;
    }
  }

  /// Mise à jour du profil (E-mail et Type)
  Future<void> updateProfile({String? email, String? userType, String? language}) async {
    final current = state.valueOrNull;
    if (current == null || !current.isAuthenticated) return;

    state = const AsyncLoading();
    try {
      final client = ApiClient(token: current.accessToken);
      final body = <String, dynamic>{};
      if (email != null) body['email'] = email;
      if (userType != null) body['user_type'] = userType;
      if (language != null) body['language'] = language;
      
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
    final current = state.valueOrNull;
    if (current?.refreshToken == null) return;

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
    } catch (_) {
      await logout();
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

  Future<void> logout() async {
    await _storage.clearTokens();
    state = AsyncData(const AuthState(status: AuthStatus.unauthenticated));
  }

  String _extractError(Object e) {
    return e.toString().replaceAll('Exception: ', '');
  }
}
