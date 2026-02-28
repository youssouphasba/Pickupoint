# Plan Implémentation Frontend Flutter — PickuPoint Mobile

> **Pour l'implémenteur** : Ce fichier contient le plan complet pour créer l'application Flutter PickuPoint.
> Certains fichiers ont déjà été créés (voir section "Fichiers déjà créés"). Commencer par `flutter create .` si le projet n'existe pas encore.

---

## Contexte

Application Flutter unique (iOS + Android), role-based routing.
Après connexion OTP → l'app détecte le rôle → affiche le bon dashboard.
Backend FastAPI disponible sur `10.0.2.2:8001` (émulateur Android) ou `localhost:8001` (iOS simulateur).
API documentée via `/docs` Swagger.

---

## Fichiers déjà créés

Les fichiers suivants ont été générés et sont présents dans `/mobile/` :

- `pubspec.yaml` — dépendances complètes
- `lib/core/theme/app_theme.dart` — couleurs & thème Material3
- `lib/core/api/api_endpoints.dart` — toutes les URLs constantes
- `lib/core/api/api_client.dart` — client Dio avec intercepteur auth
- `lib/core/models/user.dart` — modèle User
- `lib/core/models/parcel.dart` — modèles Parcel, ParcelEvent, QuoteResponse
- `lib/core/models/relay_point.dart` — modèle RelayPoint
- `lib/core/models/delivery_mission.dart` — modèle DeliveryMission
- `lib/core/models/wallet.dart` — modèles Wallet, WalletTransaction, PayoutRequest
- `lib/core/auth/token_storage.dart` — FlutterSecureStorage wrapper
- `lib/core/auth/auth_provider.dart` — Riverpod AuthNotifier + AuthState

**Reste à créer** : tout ce qui est listé dans les étapes 2 à 7 ci-dessous.

---

## 1. Structure complète du projet

```
pickupoint/
└── mobile/
    ├── pubspec.yaml                          ✅ FAIT
    ├── lib/
    │   ├── main.dart                         # entry point, ProviderScope
    │   ├── app.dart                          # MaterialApp.router + go_router
    │   │
    │   ├── core/
    │   │   ├── api/
    │   │   │   ├── api_client.dart           ✅ FAIT
    │   │   │   └── api_endpoints.dart        ✅ FAIT
    │   │   ├── auth/
    │   │   │   ├── auth_provider.dart        ✅ FAIT
    │   │   │   └── token_storage.dart        ✅ FAIT
    │   │   ├── models/
    │   │   │   ├── user.dart                 ✅ FAIT
    │   │   │   ├── parcel.dart               ✅ FAIT
    │   │   │   ├── relay_point.dart          ✅ FAIT
    │   │   │   ├── delivery_mission.dart     ✅ FAIT
    │   │   │   └── wallet.dart               ✅ FAIT
    │   │   ├── router/
    │   │   │   └── app_router.dart           # go_router + role guards
    │   │   └── theme/
    │   │       └── app_theme.dart            ✅ FAIT
    │   │
    │   ├── features/
    │   │   ├── auth/
    │   │   │   ├── screens/
    │   │   │   │   ├── phone_screen.dart
    │   │   │   │   └── otp_screen.dart
    │   │   │   └── providers/
    │   │   │       └── auth_notifier.dart    # re-exporte auth_provider
    │   │   │
    │   │   ├── client/
    │   │   │   ├── screens/
    │   │   │   │   ├── client_home.dart
    │   │   │   │   ├── create_parcel_screen.dart
    │   │   │   │   ├── quote_screen.dart
    │   │   │   │   ├── parcel_detail_screen.dart
    │   │   │   │   └── tracking_screen.dart
    │   │   │   └── providers/
    │   │   │       └── client_provider.dart
    │   │   │
    │   │   ├── relay/
    │   │   │   ├── screens/
    │   │   │   │   ├── relay_home.dart
    │   │   │   │   ├── scan_in_screen.dart
    │   │   │   │   ├── scan_out_screen.dart
    │   │   │   │   └── relay_wallet_screen.dart
    │   │   │   └── providers/
    │   │   │       └── relay_provider.dart
    │   │   │
    │   │   ├── driver/
    │   │   │   ├── screens/
    │   │   │   │   ├── driver_home.dart
    │   │   │   │   ├── mission_detail_screen.dart
    │   │   │   │   ├── delivery_screen.dart
    │   │   │   │   └── driver_wallet_screen.dart
    │   │   │   └── providers/
    │   │   │       └── driver_provider.dart
    │   │   │
    │   │   └── admin/
    │   │       ├── screens/
    │   │       │   ├── admin_dashboard.dart
    │   │       │   ├── admin_parcels_screen.dart
    │   │       │   ├── admin_relays_screen.dart
    │   │       │   └── admin_payouts_screen.dart
    │   │       └── providers/
    │   │           └── admin_provider.dart
    │   │
    │   └── shared/
    │       ├── widgets/
    │       │   ├── parcel_status_badge.dart
    │       │   ├── timeline_widget.dart
    │       │   ├── otp_input.dart
    │       │   ├── bottom_nav.dart
    │       │   └── loading_button.dart
    │       └── utils/
    │           ├── date_format.dart
    │           └── currency_format.dart
    │
    └── test/
        └── widget_test.dart
```

---

## 2. Thème & Couleurs (déjà dans `app_theme.dart`)

```dart
class AppColors {
  static const primary     = Color(0xFF1A73E8); // bleu PickuPoint
  static const secondary   = Color(0xFFFF6B00); // orange accent
  static const success     = Color(0xFF2E7D32); // vert livré
  static const warning     = Color(0xFFF57C00); // orange en transit
  static const error       = Color(0xFFC62828); // rouge échec
  static const purple      = Color(0xFF6A1B9A); // violet out_for_delivery
  static const background  = Color(0xFFF5F5F5);
  static const surface     = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF212121);
}
```

---

## 3. main.dart et app.dart

### `lib/main.dart`
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: PickuPointApp()));
}
```

### `lib/app.dart`
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class PickuPointApp extends ConsumerWidget {
  const PickuPointApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'PickuPoint',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
```

---

## 4. Navigation role-based — `lib/core/router/app_router.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../../features/auth/screens/phone_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/client/screens/client_home.dart';
import '../../features/client/screens/create_parcel_screen.dart';
import '../../features/client/screens/quote_screen.dart';
import '../../features/client/screens/parcel_detail_screen.dart';
import '../../features/client/screens/tracking_screen.dart';
import '../../features/relay/screens/relay_home.dart';
import '../../features/relay/screens/scan_in_screen.dart';
import '../../features/relay/screens/scan_out_screen.dart';
import '../../features/relay/screens/relay_wallet_screen.dart';
import '../../features/driver/screens/driver_home.dart';
import '../../features/driver/screens/mission_detail_screen.dart';
import '../../features/driver/screens/driver_wallet_screen.dart';
import '../../features/admin/screens/admin_dashboard.dart';
import '../../features/admin/screens/admin_parcels_screen.dart';
import '../../features/admin/screens/admin_relays_screen.dart';
import '../../features/admin/screens/admin_payouts_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/auth/phone',
    refreshListenable: /* écouter authProvider */ null,
    redirect: (context, state) {
      final auth = authState.valueOrNull;
      final isLoggedIn = auth?.status == AuthStatus.authenticated;
      final isAuthRoute = state.fullPath?.startsWith('/auth') ?? false;
      final isUnknown = auth?.status == AuthStatus.unknown;

      if (isUnknown) return null; // attendre la résolution
      if (!isLoggedIn && !isAuthRoute) return '/auth/phone';
      if (isLoggedIn && isAuthRoute) {
        return switch (auth!.user?.role) {
          'relay_agent' => '/relay',
          'driver'      => '/driver',
          'admin'       => '/admin',
          _             => '/client',
        };
      }
      return null;
    },
    routes: [
      // ── Auth ──────────────────────────────────────────────
      GoRoute(path: '/auth/phone', builder: (_, __) => const PhoneScreen()),
      GoRoute(path: '/auth/otp',   builder: (_, state) {
        final phone = state.extra as String? ?? '';
        return OtpScreen(phone: phone);
      }),

      // ── Client ────────────────────────────────────────────
      ShellRoute(
        builder: (_, __, child) => ClientShell(child: child),
        routes: [
          GoRoute(path: '/client', builder: (_, __) => const ClientHome()),
          GoRoute(path: '/client/create', builder: (_, __) => const CreateParcelScreen()),
          GoRoute(path: '/client/quote',  builder: (_, s) => QuoteScreen(data: s.extra as Map<String, dynamic>)),
          GoRoute(path: '/client/parcel/:id', builder: (_, s) => ParcelDetailScreen(id: s.pathParameters['id']!)),
          GoRoute(path: '/track/:code', builder: (_, s) => TrackingScreen(code: s.pathParameters['code']!)),
        ],
      ),

      // ── Relay ─────────────────────────────────────────────
      ShellRoute(
        builder: (_, __, child) => RelayShell(child: child),
        routes: [
          GoRoute(path: '/relay',          builder: (_, __) => const RelayHome()),
          GoRoute(path: '/relay/scan-in',  builder: (_, __) => const ScanInScreen()),
          GoRoute(path: '/relay/scan-out', builder: (_, __) => const ScanOutScreen()),
          GoRoute(path: '/relay/wallet',   builder: (_, __) => const RelayWalletScreen()),
        ],
      ),

      // ── Driver ────────────────────────────────────────────
      ShellRoute(
        builder: (_, __, child) => DriverShell(child: child),
        routes: [
          GoRoute(path: '/driver',             builder: (_, __) => const DriverHome()),
          GoRoute(path: '/driver/mission/:id', builder: (_, s) => MissionDetailScreen(id: s.pathParameters['id']!)),
          GoRoute(path: '/driver/wallet',      builder: (_, __) => const DriverWalletScreen()),
        ],
      ),

      // ── Admin ─────────────────────────────────────────────
      ShellRoute(
        builder: (_, __, child) => AdminShell(child: child),
        routes: [
          GoRoute(path: '/admin',          builder: (_, __) => const AdminDashboard()),
          GoRoute(path: '/admin/parcels',  builder: (_, __) => const AdminParcelsScreen()),
          GoRoute(path: '/admin/relays',   builder: (_, __) => const AdminRelaysScreen()),
          GoRoute(path: '/admin/payouts',  builder: (_, __) => const AdminPayoutsScreen()),
        ],
      ),
    ],
  );
});

// Shells avec BottomNavigationBar par rôle
class ClientShell extends StatelessWidget {
  const ClientShell({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(body: child,
    bottomNavigationBar: BottomNavigationBar(items: const [
      BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Accueil'),
      BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Suivre'),
      BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
    ]),
  );
}

class RelayShell extends StatelessWidget {
  const RelayShell({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(body: child,
    bottomNavigationBar: BottomNavigationBar(items: const [
      BottomNavigationBarItem(icon: Icon(Icons.inventory), label: 'Stock'),
      BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Scanner'),
      BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Gains'),
    ]),
  );
}

class DriverShell extends StatelessWidget {
  const DriverShell({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(body: child,
    bottomNavigationBar: BottomNavigationBar(items: const [
      BottomNavigationBarItem(icon: Icon(Icons.local_shipping), label: 'Missions'),
      BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Gains'),
    ]),
  );
}

class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(body: child,
    bottomNavigationBar: BottomNavigationBar(items: const [
      BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
      BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: 'Colis'),
      BottomNavigationBarItem(icon: Icon(Icons.store), label: 'Relais'),
      BottomNavigationBarItem(icon: Icon(Icons.payments), label: 'Retraits'),
    ]),
  );
}
```

---

## 5. Auth — Écrans

### `lib/features/auth/screens/phone_screen.dart`

- Champ téléphone format E.164 (`+221XXXXXXXXX`)
- Validation : doit commencer par `+`
- Bouton "Recevoir mon code" → appelle `authProvider.requestOtp(phone)`
- En succès → `context.push('/auth/otp', extra: phone)`
- Afficher erreur Snackbar si échec

### `lib/features/auth/screens/otp_screen.dart`

- Reçoit `phone` en paramètre
- Widget `OtpInput` (6 cases, voir shared/widgets)
- Auto-submit quand 6 chiffres saisis
- Timer resend 60 secondes
- Appelle `authProvider.verifyOtp(phone, otp)`
- Succès → go_router redirige automatiquement (role-based redirect)
- Bouton "Renvoyer" actif après 60s

---

## 6. Shared Widgets

### `lib/shared/widgets/otp_input.dart`

```dart
// Widget avec 6 TextField connectés
// - autoFocus sur le premier
// - onChanged : focus suivant automatiquement
// - onCompleted(String code) callback quand les 6 sont remplis
class OtpInput extends StatefulWidget {
  const OtpInput({super.key, required this.onCompleted});
  final ValueChanged<String> onCompleted;
}
```

### `lib/shared/widgets/parcel_status_badge.dart`

```dart
// Badge coloré selon le statut
Color _colorForStatus(String status) => switch (status) {
  'created'              => Colors.grey,
  'dropped_at_origin_relay' | 'in_transit' | 'at_destination_relay' => AppColors.primary,
  'available_at_relay'   => AppColors.warning,
  'out_for_delivery'     => AppColors.purple,
  'delivered'            => AppColors.success,
  'delivery_failed'      => AppColors.error,
  'cancelled' || 'expired' => Colors.grey.shade700,
  _                      => Colors.grey,
};

// Label FR par statut
String _labelForStatus(String status) => switch (status) {
  'created'                 => 'Créé',
  'dropped_at_origin_relay' => 'Déposé au relais',
  'in_transit'              => 'En transit',
  'at_destination_relay'    => 'Au relais destination',
  'available_at_relay'      => 'Disponible au relais',
  'out_for_delivery'        => 'En livraison',
  'delivered'               => 'Livré',
  'delivery_failed'         => 'Échec livraison',
  'cancelled'               => 'Annulé',
  'expired'                 => 'Expiré',
  'returned'                => 'Retourné',
  _                         => status,
};
```

### `lib/shared/widgets/timeline_widget.dart`

```dart
// Liste verticale d'événements ParcelEvent
// Chaque item : icône + statut + date formatée + note éventuelle
// Tri : du plus récent au plus ancien
class TimelineWidget extends StatelessWidget {
  const TimelineWidget({super.key, required this.events});
  final List<ParcelEvent> events;
}
```

### `lib/shared/widgets/loading_button.dart`

```dart
// ElevatedButton avec CircularProgressIndicator quand isLoading=true
class LoadingButton extends StatelessWidget {
  const LoadingButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
}
```

### `lib/shared/utils/currency_format.dart`

```dart
// Formater en XOF
// ex: formatXof(15000) → "15 000 FCFA"
String formatXof(double amount) {
  final formatted = NumberFormat('#,###', 'fr_FR').format(amount);
  return '$formatted FCFA';
}
```

### `lib/shared/utils/date_format.dart`

```dart
// Formater en français
// ex: formatDate(dt) → "28 fév. 2026 à 14:30"
String formatDate(DateTime dt) =>
    DateFormat('d MMM yyyy à HH:mm', 'fr_FR').format(dt.toLocal());
```

---

## 7. Feature CLIENT

### `lib/features/client/providers/client_provider.dart`

```dart
// Providers Riverpod :
final parcelsProvider = FutureProvider<List<Parcel>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getParcels();
  return (res.data['items'] as List).map((e) => Parcel.fromJson(e)).toList();
});

final parcelProvider = FutureProvider.family<Parcel, String>((ref, id) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getParcel(id);
  return Parcel.fromJson(res.data);
});

final relayPointsProvider = FutureProvider<List<RelayPoint>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getRelayPoints();
  return (res.data['items'] as List).map((e) => RelayPoint.fromJson(e)).toList();
});
```

### `lib/features/client/screens/client_home.dart`

- AppBar : "Mes colis" + action logout
- FAB : "Envoyer un colis" → `/client/create`
- Liste colis groupés par statut avec `ParcelStatusBadge`
- Chips filtre statut (Tous / En cours / Livrés / Annulés)
- Pull-to-refresh (`RefreshIndicator`)
- État vide : illustration + "Aucun colis, envoyez votre premier colis"
- Shimmer loading pendant chargement

### `lib/features/client/screens/create_parcel_screen.dart`

Wizard 3 étapes avec `PageView` ou `Stepper` :

**Étape 1 — Mode de livraison**
- 2 choix : Relais → Relais | Relais → Domicile
- Description de chaque mode

**Étape 2 — Destination & Destinataire**
- Si RELAY_TO_RELAY :
  - Dropdown relais départ (liste `/api/relay-points`)
  - Dropdown relais arrivée
- Si RELAY_TO_HOME :
  - Dropdown relais départ
  - TextField adresse livraison
  - (Optionnel) Bouton "Épingler sur la carte"
- Champs : Nom destinataire, Téléphone destinataire

**Étape 3 — Détails colis**
- Poids estimé (kg) — Slider ou TextField
- Valeur déclarée (FCFA)
- Switch "Assurance" (+ info sur le coût)
- Bouton "Voir le devis" → `POST /api/parcels/quote` → push `/client/quote`

### `lib/features/client/screens/quote_screen.dart`

- Reçoit `QuoteResponse` + données du formulaire
- Affiche : Prix de base, Supplément poids, Assurance, **Total**
- Bouton "Confirmer et payer"
  - `POST /api/parcels` → crée le colis
  - Lance Flutterwave via `InAppWebView` (URL de paiement dans la réponse)
  - Après paiement → retour `ClientHome`

### `lib/features/client/screens/parcel_detail_screen.dart`

- `GET /api/parcels/{id}`
- Header : code tracking + `ParcelStatusBadge`
- Infos : relais départ, relais/adresse arrivée, destinataire, poids, prix
- `TimelineWidget` avec les événements
- Si `status == 'created'` : bouton "Annuler" (avec confirmation dialog)
- Si livreur assigné + position GPS : mini carte (Google Maps Widget ou simple lien)

### `lib/features/client/screens/tracking_screen.dart`

- Accessible sans auth (deep link `/track/:code`)
- `GET /api/tracking/{code}` (endpoint public)
- Affiche : statut actuel + `TimelineWidget`
- Barre de recherche pour chercher un autre code

---

## 8. Feature RELAY AGENT

### `lib/features/relay/providers/relay_provider.dart`

```dart
final relayStockProvider = FutureProvider<List<Parcel>>((ref) async {
  // récupère l'ID du relais depuis le profil user
  final user = ref.watch(authProvider).valueOrNull?.user;
  final relayId = user?.relayPointId; // champ à ajouter dans User si besoin
  final api = ref.watch(apiClientProvider);
  final res = await api.getRelayStock(relayId!);
  return (res.data['items'] as List).map((e) => Parcel.fromJson(e)).toList();
});
```

### `lib/features/relay/screens/relay_home.dart`

- AppBar : nom du relais + capacité (ex: "12/20 colis")
- Liste colis en stock avec statut
- Alerte visuelle pour colis > 5 jours (couleur rouge sur la carte)
- Boutons rapides en bas : "Scanner entrée" / "Scanner sortie"
- Pull-to-refresh

### `lib/features/relay/screens/scan_in_screen.dart`

- Utilise `mobile_scanner` pour lire le QR code du colis
- Le QR contient l'ID du colis (ou `parcel_id:signature`)
- Après scan : `POST /api/parcels/{id}/drop-at-relay`
- Feedback visuel : vert = succès (+ vibration), rouge = erreur
- Affiche les infos du colis scanné (destinataire, mode de livraison)
- Bouton pour saisie manuelle du code tracking

### `lib/features/relay/screens/scan_out_screen.dart`

- Scan QR du code client (ou saisie manuelle du code tracking)
- Dialog confirmation : infos du destinataire
- Saisie PIN à 4 chiffres du destinataire
- `POST /api/parcels/{id}/handout` avec le PIN
- Feedback succès/erreur

### `lib/features/relay/screens/relay_wallet_screen.dart`

- `GET /api/wallets/me` — affiche le solde en XOF
- Liste transactions (`GET /api/wallets/me/transactions`)
- Bouton "Demander un retrait" → Bottom sheet :
  - Montant (validation : ≤ solde)
  - Méthode : Wave / Orange Money / Free Money
  - Numéro de téléphone
  - `POST /api/wallets/me/payout`

---

## 9. Feature DRIVER (Livreur)

### `lib/features/driver/providers/driver_provider.dart`

```dart
final availableMissionsProvider = FutureProvider<List<DeliveryMission>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getAvailableMissions();
  return (res.data['items'] as List).map((e) => DeliveryMission.fromJson(e)).toList();
});

final myMissionsProvider = FutureProvider<List<DeliveryMission>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getMyMissions();
  return (res.data['items'] as List).map((e) => DeliveryMission.fromJson(e)).toList();
});
```

### `lib/features/driver/screens/driver_home.dart`

- 2 sections : "Missions disponibles" + "Mes missions en cours"
- Carte par mission : adresse livraison + gain en XOF
- Bouton "Accepter" sur les missions disponibles → `POST /api/deliveries/{id}/accept`
- Pull-to-refresh

### `lib/features/driver/screens/mission_detail_screen.dart`

- `GET /api/deliveries/{id}`
- Affiche : adresse livraison, nom/téléphone destinataire, gain
- Bouton "Ouvrir dans Maps" → `maps.google.com/?q=lat,lng`
- Bouton "Appeler" → `tel:+221XXXXXXXX`
- Bouton "Démarrer la livraison" → démarre timer GPS
- **GPS** : toutes les 30s → `PUT /api/deliveries/{id}/location` avec `{lat, lng}`
- Boutons finaux : "Livraison réussie" | "Signaler un échec"

### `lib/features/driver/screens/delivery_screen.dart`

**Succès** :
- Option A : Photo preuve (image_picker → base64 ou multipart)
- Option B : PIN 4 chiffres saisi par le destinataire
- `POST /api/parcels/{id}/deliver`

**Échec** :
- Liste de raisons : Absent / Adresse introuvable / Refus de réception / Autre
- Option : "Rediriger vers un relais" → sélectionner relais → `POST /api/parcels/{id}/redirect-relay`
- `POST /api/parcels/{id}/fail-delivery`

### `lib/features/driver/screens/driver_wallet_screen.dart`

Identique à `relay_wallet_screen.dart` — même UI, mêmes endpoints.

---

## 10. Feature ADMIN

### `lib/features/admin/providers/admin_provider.dart`

```dart
final dashboardProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getDashboard();
  return res.data as Map<String, dynamic>;
});

final adminParcelsProvider = FutureProvider.family<List<Parcel>, String?>((ref, status) async {
  final api = ref.watch(apiClientProvider);
  final res = await api.getAdminParcels(params: status != null ? {'status': status} : null);
  return (res.data['items'] as List).map((e) => Parcel.fromJson(e)).toList();
});
```

### `lib/features/admin/screens/admin_dashboard.dart`

- `GET /api/admin/dashboard`
- Grille de cartes KPI :
  - Colis du jour / Taux de succès / CA du mois
  - Relais actifs / Livreurs actifs
- Chaque carte : valeur en grand + label + couleur thématique

### `lib/features/admin/screens/admin_parcels_screen.dart`

- Liste paginée avec filtre statut (chips)
- Tap sur un colis → bottom sheet "Forcer le statut"
- `PUT /api/admin/parcels/{id}/status` avec le nouveau statut

### `lib/features/admin/screens/admin_relays_screen.dart`

- Liste des relais avec badge "Vérifié" / "Non vérifié"
- Bouton "Vérifier" sur les relais non vérifiés → `PUT /api/admin/relay-points/{id}/verify`
- Affiche : nom, ville, agent, capacité

### `lib/features/admin/screens/admin_payouts_screen.dart`

- Liste des demandes de retrait en attente
- Chaque item : montant, méthode, téléphone, date
- Bouton "Approuver" → `PUT /api/admin/wallets/payouts/{id}/approve`
- Bouton "Rejeter" → endpoint à prévoir

---

## 11. Configuration Android

Ajouter dans `android/app/src/main/AndroidManifest.xml` :
```xml
<!-- Permissions requises -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.VIBRATE" />
```

Dans `android/app/build.gradle` :
```groovy
android {
    defaultConfig {
        minSdkVersion 23  // requis pour flutter_secure_storage
    }
}
```

---

## 12. Ordre d'implémentation recommandé

```
Étape 1 (FAIT) — Setup de base
  ✅ pubspec.yaml, app_theme, api_endpoints, api_client

Étape 2 (FAIT) — Modèles & Auth core
  ✅ user.dart, parcel.dart, relay_point.dart, delivery_mission.dart, wallet.dart
  ✅ token_storage.dart, auth_provider.dart

Étape 3 — Entry point & Router
  [ ] main.dart
  [ ] app.dart
  [ ] app_router.dart (avec les ShellRoutes et le redirect)

Étape 4 — Shared widgets
  [ ] otp_input.dart
  [ ] parcel_status_badge.dart
  [ ] timeline_widget.dart
  [ ] loading_button.dart
  [ ] date_format.dart
  [ ] currency_format.dart

Étape 5 — Auth screens
  [ ] phone_screen.dart
  [ ] otp_screen.dart

Étape 6 — Feature Client
  [ ] client_provider.dart
  [ ] client_home.dart
  [ ] create_parcel_screen.dart
  [ ] quote_screen.dart
  [ ] parcel_detail_screen.dart
  [ ] tracking_screen.dart

Étape 7 — Feature Relay
  [ ] relay_provider.dart
  [ ] relay_home.dart
  [ ] scan_in_screen.dart
  [ ] scan_out_screen.dart
  [ ] relay_wallet_screen.dart

Étape 8 — Feature Driver
  [ ] driver_provider.dart
  [ ] driver_home.dart
  [ ] mission_detail_screen.dart
  [ ] delivery_screen.dart
  [ ] driver_wallet_screen.dart

Étape 9 — Feature Admin
  [ ] admin_provider.dart
  [ ] admin_dashboard.dart
  [ ] admin_parcels_screen.dart
  [ ] admin_relays_screen.dart
  [ ] admin_payouts_screen.dart

Étape 10 — Finitions
  [ ] AndroidManifest.xml permissions
  [ ] android/app/build.gradle minSdkVersion 23
  [ ] Icône app + splash screen
  [ ] Test sur émulateur Android
```

---

## 13. Règles importantes pour l'implémenteur

- `10.0.2.2` = localhost sur émulateur Android (pas `127.0.0.1`)
- iOS simulateur → utiliser `localhost` directement
- En prod → HTTPS obligatoire (mobile_scanner + geolocator l'exigent)
- `flutter_secure_storage` nécessite `minSdkVersion 23` sur Android
- Toujours `ref.watch` dans les widgets (UI réactive), `ref.read` dans les handlers d'événements
- Ne jamais appeler `Dio` directement depuis un widget — passer par le provider
- Toutes les dates en UTC (`DateTime.parse` retourne UTC par défaut depuis JSON)
- Devise : XOF (FCFA) — utiliser `formatXof()` partout

---

## 14. Vérification finale

```bash
cd pickupoint/mobile
flutter pub get
flutter run   # sur émulateur Android

# Parcours de test :
# 1. Écran téléphone → saisir +221701234567
# 2. Recevoir OTP (voir terminal backend en mode DEBUG)
# 3. Saisir OTP → login → redirection ClientHome
# 4. Créer un colis → voir le devis → payer
# 5. Admin : changer rôle → tester dashboard relais
# 6. Relais : scanner QR → drop-at-relay
# 7. Driver : accepter mission → livrer
```
