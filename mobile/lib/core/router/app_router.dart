import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../../features/auth/screens/phone_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/auth/screens/onboarding_screen.dart';
import '../../features/client/screens/client_home.dart';
import '../../features/client/screens/create_parcel_screen.dart';
import '../../features/client/screens/quote_screen.dart';
import '../../features/client/screens/parcel_detail_screen.dart';
import '../../features/client/screens/tracking_screen.dart';
import '../../features/client/screens/client_search_screen.dart';
import '../../features/client/screens/client_profile_screen.dart';
import '../../features/client/screens/favorite_addresses_screen.dart';
import '../../features/client/screens/notification_settings_screen.dart';
import '../../features/relay/screens/relay_home.dart';
import '../../features/relay/screens/relay_profile_screen.dart';
import '../../features/relay/screens/scan_in_screen.dart';
import '../../features/relay/screens/scan_out_screen.dart';
import '../../features/relay/screens/relay_wallet_screen.dart';
import '../../features/driver/screens/driver_home.dart';
import '../../features/driver/screens/mission_detail_screen.dart';
import '../../features/driver/screens/driver_wallet_screen.dart';
import '../../features/driver/screens/driver_performance_screen.dart';
import '../../features/admin/screens/admin_dashboard.dart';
import '../../features/admin/screens/admin_parcels_screen.dart';
import '../../features/admin/screens/admin_relays_screen.dart';
import '../../features/admin/screens/admin_payouts_screen.dart';
import '../../features/admin/screens/admin_users_screen.dart';
import '../../features/admin/screens/admin_applications_screen.dart';
import '../../features/admin/screens/admin_fleet_map_screen.dart';
import '../../features/admin/screens/admin_stale_parcels_screen.dart';
import '../../features/admin/screens/admin_finance_screen.dart';
import '../../features/admin/screens/admin_parcel_audit_screen.dart';
import '../../features/admin/screens/admin_anomalies_screen.dart';
import '../../features/admin/screens/admin_heatmap_screen.dart';
import '../../features/admin/screens/admin_promotions_screen.dart';
import '../../features/client/screens/partnership_screen.dart';
import '../../features/client/screens/client_loyalty_history_screen.dart';
import '../../features/admin/screens/admin_global_audit_screen.dart';
import '../../features/admin/screens/admin_legal_list_screen.dart';
import '../../features/admin/screens/admin_legal_edit_screen.dart';
import '../../shared/screens/legal_document_screen.dart';

// Import temporaire des écrans vides pour que ça compile
// Nous les créerons plus tard dans les dossiers features/
class PlaceholderScreen extends StatelessWidget {
  final String title;
  const PlaceholderScreen(this.title, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(child: Text('Écran: $title')),
  );
}

/// Notifier pour écouter les changements d'auth et rafraîchir GoRouter
class _GoRouterNotifier extends ChangeNotifier {
  _GoRouterNotifier(this._ref) {
    _ref.listen<AsyncValue<AuthState>>(
      authProvider,
      (previous, next) {
        if (previous?.valueOrNull?.status != next.valueOrNull?.status) {
          notifyListeners();
        }
      },
    );
  }
  final Ref _ref;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _GoRouterNotifier(ref);

  return GoRouter(
    initialLocation: '/auth/phone',
    refreshListenable: notifier,
    redirect: (context, state) {
      final auth = ref.read(authProvider).valueOrNull;
      final isLoggedIn = auth?.status == AuthStatus.authenticated;
      final isAuthRoute = state.fullPath?.startsWith('/auth') ?? false;
      final isUnknown = auth?.status == AuthStatus.unknown;

      if (isUnknown) return null; // attendre la résolution
      if (!isLoggedIn && !isAuthRoute) return '/auth/phone';
      if (isLoggedIn && isAuthRoute && !state.fullPath!.startsWith('/onboarding')) {
        if (auth!.user?.needsOnboarding == true) {
          return '/onboarding';
        }
        return switch (auth.effectiveRole) {
          'relay_agent' => '/relay',
          'driver'      => '/driver',
          'admin'       => '/admin',
          _             => '/client',
        };
      }

      // Si l'user est connecté mais navigue autre part, on vérifie s'il doit onboarding
      if (isLoggedIn && auth!.user?.needsOnboarding == true && !state.fullPath!.startsWith('/onboarding')) {
        return '/onboarding';
      }

      return null;
    },
    routes: [
      // ── Public / Communs ────────────────────────────────────────
      GoRoute(path: '/legal/:docType', builder: (_, s) => LegalDocumentScreen(docType: s.pathParameters['docType']!)),

      // ── Auth ──────────────────────────────────────────────
      GoRoute(path: '/auth/phone', builder: (_, __) => const PhoneScreen()),
      GoRoute(path: '/auth/otp',   builder: (_, state) {
        final data = state.extra as Map<String, dynamic>;
        return OtpScreen(
          phone: data['phone'] as String,
          acceptedLegal: data['accepted_legal'] as bool? ?? false,
        );
      }),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),

      // ── Client ────────────────────────────────────────────
      ShellRoute(
        builder: (_, __, child) => ClientShell(child: child),
        routes: [
          GoRoute(path: '/client', builder: (_, __) => const ClientHome()),
          GoRoute(path: '/client/search', builder: (_, __) => const ClientSearchScreen()),
          GoRoute(path: '/client/profile', builder: (_, __) => const ClientProfileScreen()),
          GoRoute(path: '/client/create', builder: (_, __) => const CreateParcelScreen()),
          GoRoute(path: '/client/quote',  builder: (_, s) => QuoteScreen(data: s.extra as Map<String, dynamic>)),
          GoRoute(path: '/client/parcel/:id', builder: (_, s) => ParcelDetailScreen(id: s.pathParameters['id']!)),
          GoRoute(path: '/track/:code', builder: (_, s) => TrackingScreen(code: s.pathParameters['code']!)),
          GoRoute(path: '/client/partnership', builder: (_, __) => const PartnershipScreen()),
          GoRoute(path: '/client/loyalty-history', builder: (_, __) => const ClientLoyaltyHistoryScreen()),
          GoRoute(path: '/client/favorites', builder: (_, __) => const FavoriteAddressesScreen()),
          GoRoute(path: '/client/notifications', builder: (_, __) => const NotificationSettingsScreen()),
        ],
      ),

      // ── Relay ─────────────────────────────────────────────
      ShellRoute(
        builder: (_, __, child) => RelayShell(child: child),
        routes: [
          GoRoute(path: '/relay',          builder: (_, __) => const RelayHome()),
          GoRoute(path: '/relay/profile',  builder: (_, __) => const RelayProfileScreen()),
          GoRoute(path: '/relay/scan-in',  builder: (_, __) => const ScanInScreen()),
          GoRoute(path: '/relay/scan-out', builder: (_, s) {
            final extra = s.extra as Map<String, dynamic>?;
            return ScanOutScreen(
              prefilledParcelId:       extra?['parcelId']       as String?,
              prefilledTrackingCode:   extra?['trackingCode']   as String?,
              prefilledRecipientName:  extra?['recipientName']  as String?,
              prefilledRecipientPhone: extra?['recipientPhone'] as String?,
            );
          }),
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
          GoRoute(path: '/driver/performance', builder: (_, __) => const DriverPerformanceScreen()),
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
          GoRoute(path: '/admin/users',         builder: (_, __) => const AdminUsersScreen()),
          GoRoute(path: '/admin/applications',  builder: (_, __) => const AdminApplicationsScreen()),
          GoRoute(path: '/admin/fleet',         builder: (_, __) => const AdminFleetMapScreen()),
          GoRoute(path: '/admin/stale',         builder: (_, __) => const AdminStaleParcelsScreen()),
          GoRoute(path: '/admin/finance',       builder: (_, __) => const AdminFinanceScreen()),
          GoRoute(path: '/admin/anomalies',     builder: (_, __) => const AdminAnomaliesScreen()),
          GoRoute(path: '/admin/heatmap',       builder: (_, __) => const AdminHeatmapScreen()),
          GoRoute(path: '/admin/promotions',    builder: (_, __) => const AdminPromotionsScreen()),
          GoRoute(path: '/admin/audit-log',     builder: (_, __) => const AdminGlobalAuditScreen()),
          GoRoute(path: '/admin/parcels/:id/audit', builder: (_, s) => AdminParcelAuditScreen(id: s.pathParameters['id']!)),
          GoRoute(path: '/admin/legal',         builder: (_, __) => const AdminLegalListScreen()),
          GoRoute(path: '/admin/legal/:docType/edit', builder: (_, s) => AdminLegalEditScreen(docType: s.pathParameters['docType']!)),
        ],
      ),
    ],
  );
});

// Shells avec BottomNavigationBar par rôle
class ClientShell extends StatelessWidget {
  const ClientShell({super.key, required this.child});
  final Widget child;

  static int _calculateSelectedIndex(String location) {
    if (location.startsWith('/client/search')) return 1;
    if (location.startsWith('/client/profile')) return 2;
    return 0; // Default to Home for /client, /client/create, etc.
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _calculateSelectedIndex(location),
        onTap: (i) {
          if (i == 0) context.go('/client');
          if (i == 1) context.go('/client/search');
          if (i == 2) context.go('/client/profile');
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Accueil'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Suivre'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}

class RelayShell extends StatelessWidget {
  const RelayShell({super.key, required this.child});
  final Widget child;

  static const _tabs = ['/relay', '/relay/scan-in', '/relay/wallet'];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    int idx = 0;
    if (location.startsWith('/relay/scan')) idx = 1;
    else if (location.startsWith('/relay/wallet')) idx = 2;

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx,
        onTap: (i) => context.go(_tabs[i]),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: 'Stock'),
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Scanner'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Gains'),
        ]
      ),
    );
  }
}

class DriverShell extends StatelessWidget {
  const DriverShell({super.key, required this.child});
  final Widget child;

  static const _tabs = ['/driver', '/driver/wallet'];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final idx = location.startsWith('/driver/wallet') ? 1 : 0;

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx,
        onTap: (i) => context.go(_tabs[i]),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.local_shipping), label: 'Missions'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Gains'),
        ]
      ),
    );
  }
}

class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.child});
  final Widget child;

  static const _tabs = [
    '/admin', '/admin/parcels', '/admin/applications', '/admin/users', '/admin/payouts',
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final idx = _tabs.indexWhere((t) => location.startsWith(t));
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx < 0 ? 0 : idx,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => context.go(_tabs[i]),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard),        label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2),      label: 'Colis'),
          BottomNavigationBarItem(icon: Icon(Icons.how_to_reg),       label: 'Candidatures'),
          BottomNavigationBarItem(icon: Icon(Icons.group),            label: 'Utilisateurs'),
          BottomNavigationBarItem(icon: Icon(Icons.payments),         label: 'Retraits'),
        ],
      ),
    );
  }
}
