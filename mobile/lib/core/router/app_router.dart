import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../../features/auth/screens/phone_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/auth/screens/pin_login_screen.dart';
import '../../features/auth/screens/setup_profile_screen.dart';
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
import '../../features/driver/screens/driver_profile_screen.dart';
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

String? _extractReferralCode(Uri uri) {
  final queryRef =
      (uri.queryParameters['ref'] ?? uri.queryParameters['code'] ?? '')
          .trim()
          .toUpperCase();
  if (queryRef.isNotEmpty) {
    return queryRef;
  }

  final segments = uri.pathSegments
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (segments.length >= 4 &&
      segments[0] == 'api' &&
      segments[1] == 'users' &&
      segments[2] == 'referral') {
    return segments[3].toUpperCase();
  }
  if (segments.length >= 2 && segments[0] == 'referral') {
    return segments[1].toUpperCase();
  }
  if (segments.length >= 3 &&
      segments[0] == 'app' &&
      segments[1] == 'referral') {
    return segments[2].toUpperCase();
  }
  return null;
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
      final isLegalRoute = state.fullPath?.startsWith('/legal') ?? false;
      final isUnknown = auth?.status == AuthStatus.unknown;
      final referralCode = _extractReferralCode(state.uri);

      if (isUnknown) return null; // attendre la résolution
      if (referralCode != null) {
        if (!isLoggedIn) {
          final currentRef =
              state.uri.queryParameters['ref']?.trim().toUpperCase();
          if (state.matchedLocation != '/auth/phone' ||
              currentRef != referralCode) {
            return Uri(
              path: '/auth/phone',
              queryParameters: {'ref': referralCode},
            ).toString();
          }
        } else {
          return switch (auth!.effectiveRole) {
            'relay_agent' => '/relay',
            'driver' => '/driver',
            'admin' => '/admin',
            _ => '/client',
          };
        }
      }
      if (isLegalRoute) {
        return null; // autoriser l'accès aux CGU/Privacy à tout moment
      }
      if (!isLoggedIn && !isAuthRoute) return '/auth/phone';
      if (isLoggedIn && isAuthRoute) {
        return switch (auth!.effectiveRole) {
          'relay_agent' => '/relay',
          'driver' => '/driver',
          'admin' => '/admin',
          _ => '/client',
        };
      }

      return null;
    },
    routes: [
      // ── Public / Communs ────────────────────────────────────────
      GoRoute(
          path: '/legal/:docType',
          builder: (_, s) =>
              LegalDocumentScreen(docType: s.pathParameters['docType']!)),
      GoRoute(
        path: '/referral/:code',
        redirect: (_, s) => Uri(
          path: '/auth/phone',
          queryParameters: {'ref': s.pathParameters['code']!},
        ).toString(),
      ),
      GoRoute(
        path: '/app/referral/:code',
        redirect: (_, s) => Uri(
          path: '/auth/phone',
          queryParameters: {'ref': s.pathParameters['code']!},
        ).toString(),
      ),
      GoRoute(
        path: '/api/users/referral/:code',
        redirect: (_, s) => Uri(
          path: '/auth/phone',
          queryParameters: {'ref': s.pathParameters['code']!},
        ).toString(),
      ),

      // ── Auth ──────────────────────────────────────────────
      GoRoute(
        path: '/auth/phone',
        builder: (_, state) => PhoneScreen(
          initialReferralCode: state.uri.queryParameters['ref'],
        ),
      ),
      GoRoute(
          path: '/auth/pin',
          builder: (_, state) {
            final data = state.extra as Map<String, dynamic>;
            return PinLoginScreen(phone: data['phone'] as String);
          }),
      GoRoute(
          path: '/auth/otp',
          builder: (_, state) {
            final data = state.extra as Map<String, dynamic>;
            return OtpScreen(
              phone: data['phone'] as String,
              verificationId: data['verificationId'] as String?,
              referralCode: data['referral_code'] as String?,
            );
          }),
      GoRoute(
          path: '/auth/setup',
          builder: (_, state) {
            final data = state.extra as Map<String, dynamic>;
            return SetupProfileScreen(
              registrationToken: data['registration_token'] as String,
              initialReferralCode: data['referral_code'] as String?,
            );
          }),

      // ── Client ────────────────────────────────────────────
      ShellRoute(
        builder: (_, __, child) => ClientShell(child: child),
        routes: [
          GoRoute(path: '/client', builder: (_, __) => const ClientHome()),
          GoRoute(
              path: '/client/search',
              builder: (_, __) => const ClientSearchScreen()),
          GoRoute(
              path: '/client/profile',
              builder: (_, __) => const ClientProfileScreen()),
          GoRoute(
              path: '/client/create',
              builder: (_, __) => const CreateParcelScreen()),
          GoRoute(
              path: '/client/quote',
              builder: (_, s) {
                final extra = s.extra;
                final data = extra is Map<String, dynamic>
                    ? extra
                    : extra is Map
                        ? extra.map((key, value) => MapEntry(key.toString(), value))
                        : const <String, dynamic>{};
                return QuoteScreen(data: data);
              }),
          GoRoute(
              path: '/client/parcel/:id',
              builder: (_, s) =>
                  ParcelDetailScreen(id: s.pathParameters['id']!)),
          GoRoute(
              path: '/track/:code',
              builder: (_, s) =>
                  TrackingScreen(code: s.pathParameters['code']!)),
          GoRoute(
              path: '/client/partnership',
              builder: (_, __) => const PartnershipScreen()),
          GoRoute(
              path: '/client/loyalty-history',
              builder: (_, __) => const ClientLoyaltyHistoryScreen()),
          GoRoute(
              path: '/client/favorites',
              builder: (_, __) => const FavoriteAddressesScreen()),
          GoRoute(
              path: '/client/notifications',
              builder: (_, __) => const NotificationSettingsScreen()),
        ],
      ),

      // ── Relay ─────────────────────────────────────────────
      ShellRoute(
        builder: (_, __, child) => RelayShell(child: child),
        routes: [
          GoRoute(path: '/relay', builder: (_, __) => const RelayHome()),
          GoRoute(
              path: '/relay/profile',
              builder: (_, __) => const RelayProfileScreen()),
          GoRoute(
              path: '/relay/scan-in', builder: (_, __) => const ScanInScreen()),
          GoRoute(
              path: '/relay/scan-out',
              builder: (_, s) {
                final extra = s.extra as Map<String, dynamic>?;
                return ScanOutScreen(
                  prefilledParcelId: extra?['parcelId'] as String?,
                  prefilledTrackingCode: extra?['trackingCode'] as String?,
                  prefilledRecipientName: extra?['recipientName'] as String?,
                  prefilledRecipientPhone: extra?['recipientPhone'] as String?,
                );
              }),
          GoRoute(
              path: '/relay/wallet',
              builder: (_, __) => const RelayWalletScreen()),
        ],
      ),

      // ── Driver ────────────────────────────────────────────
      ShellRoute(
        builder: (_, __, child) => DriverShell(child: child),
        routes: [
          GoRoute(path: '/driver', builder: (_, __) => const DriverHome()),
          GoRoute(
              path: '/driver/mission/:id',
              builder: (_, s) =>
                  MissionDetailScreen(id: s.pathParameters['id']!)),
          GoRoute(
              path: '/driver/wallet',
              builder: (_, __) => const DriverWalletScreen()),
          GoRoute(
              path: '/driver/profile',
              builder: (_, __) => const DriverProfileScreen()),
          GoRoute(
              path: '/driver/performance',
              builder: (_, __) => const DriverPerformanceScreen()),
        ],
      ),

      // ── Admin ─────────────────────────────────────────────
      ShellRoute(
        builder: (_, __, child) => AdminShell(child: child),
        routes: [
          GoRoute(path: '/admin', builder: (_, __) => const AdminDashboard()),
          GoRoute(
              path: '/admin/parcels',
              builder: (_, __) => const AdminParcelsScreen()),
          GoRoute(
              path: '/admin/relays',
              builder: (_, __) => const AdminRelaysScreen()),
          GoRoute(
              path: '/admin/payouts',
              builder: (_, __) => const AdminPayoutsScreen()),
          GoRoute(
              path: '/admin/users',
              builder: (_, __) => const AdminUsersScreen()),
          GoRoute(
              path: '/admin/applications',
              builder: (_, __) => const AdminApplicationsScreen()),
          GoRoute(
              path: '/admin/fleet',
              builder: (_, __) => const AdminFleetMapScreen()),
          GoRoute(
              path: '/admin/stale',
              builder: (_, __) => const AdminStaleParcelsScreen()),
          GoRoute(
              path: '/admin/finance',
              builder: (_, __) => const AdminFinanceScreen()),
          GoRoute(
              path: '/admin/anomalies',
              builder: (_, __) => const AdminAnomaliesScreen()),
          GoRoute(
              path: '/admin/heatmap',
              builder: (_, __) => const AdminHeatmapScreen()),
          GoRoute(
              path: '/admin/promotions',
              builder: (_, __) => const AdminPromotionsScreen()),
          GoRoute(
              path: '/admin/audit-log',
              builder: (_, __) => const AdminGlobalAuditScreen()),
          GoRoute(
              path: '/admin/parcels/:id/audit',
              builder: (_, s) =>
                  AdminParcelAuditScreen(id: s.pathParameters['id']!)),
          GoRoute(
              path: '/admin/legal',
              builder: (_, __) => const AdminLegalListScreen()),
          GoRoute(
              path: '/admin/legal/:docType/edit',
              builder: (_, s) =>
                  AdminLegalEditScreen(docType: s.pathParameters['docType']!)),
        ],
      ),
    ],
  );
});

// Shells avec BottomNavigationBar par rôle
class ClientShell extends StatelessWidget {
  const ClientShell({super.key, required this.child});
  final Widget child;

  static const _tabs = ['/client', '/client/search', '/client/profile'];

  static int _calculateSelectedIndex(String location) {
    if (location.startsWith('/client/search')) return 1;
    if (location.startsWith('/client/profile')) return 2;
    return 0; // Default to Home for /client, /client/create, etc.
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    return _ShellScaffold(
      currentIndex: _calculateSelectedIndex(location),
      tabs: _tabs,
      currentLocation: location,
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _calculateSelectedIndex(location),
        onTap: (i) => context.go(_tabs[i]),
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
    if (location.startsWith('/relay/scan')) {
      idx = 1;
    } else if (location.startsWith('/relay/wallet')) {
      idx = 2;
    }

    return _ShellScaffold(
      currentIndex: idx,
      tabs: _tabs,
      currentLocation: location,
      body: child,
      bottomNavigationBar: BottomNavigationBar(
          currentIndex: idx,
          onTap: (i) => context.go(_tabs[i]),
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.inventory), label: 'Stock'),
            BottomNavigationBarItem(
                icon: Icon(Icons.qr_code_scanner), label: 'Scanner'),
            BottomNavigationBarItem(
                icon: Icon(Icons.account_balance_wallet), label: 'Gains'),
          ]),
    );
  }
}

class DriverShell extends StatelessWidget {
  const DriverShell({super.key, required this.child});
  final Widget child;

  static const _tabs = ['/driver', '/driver/wallet', '/driver/profile'];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final int idx;
    if (location.startsWith('/driver/wallet')) {
      idx = 1;
    } else if (location.startsWith('/driver/profile') ||
        location.startsWith('/driver/performance')) {
      idx = 2;
    } else {
      idx = 0;
    }

    return _ShellScaffold(
      currentIndex: idx,
      tabs: _tabs,
      currentLocation: location,
      body: child,
      bottomNavigationBar: BottomNavigationBar(
          currentIndex: idx,
          type: BottomNavigationBarType.fixed,
          onTap: (i) => context.go(_tabs[i]),
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.local_shipping), label: 'Missions'),
            BottomNavigationBarItem(
                icon: Icon(Icons.account_balance_wallet), label: 'Gains'),
            BottomNavigationBarItem(
                icon: Icon(Icons.person_outline), label: 'Profil'),
          ]),
    );
  }
}

class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.child});
  final Widget child;

  static const _tabs = [
    '/admin',
    '/admin/parcels',
    '/admin/applications',
    '/admin/users',
    '/admin/payouts',
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final idx = _tabs.indexWhere((t) => location.startsWith(t));
    return _ShellScaffold(
      currentIndex: idx < 0 ? 0 : idx,
      tabs: _tabs,
      currentLocation: location,
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx < 0 ? 0 : idx,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => context.go(_tabs[i]),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2), label: 'Colis'),
          BottomNavigationBarItem(
              icon: Icon(Icons.how_to_reg), label: 'Candidatures'),
          BottomNavigationBarItem(
              icon: Icon(Icons.group), label: 'Utilisateurs'),
          BottomNavigationBarItem(
              icon: Icon(Icons.payments), label: 'Retraits'),
        ],
      ),
    );
  }
}

class _ShellScaffold extends StatefulWidget {
  const _ShellScaffold({
    required this.currentIndex,
    required this.tabs,
    required this.currentLocation,
    required this.body,
    required this.bottomNavigationBar,
  });

  final int currentIndex;
  final List<String> tabs;
  final String currentLocation;
  final Widget body;
  final Widget bottomNavigationBar;

  @override
  State<_ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends State<_ShellScaffold> {
  DateTime? _lastBackPressAt;

  void _handleBack() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return;
    }

    final safeIndex = widget.currentIndex.clamp(0, widget.tabs.length - 1);
    final currentTab = widget.tabs[safeIndex];
    if (widget.currentLocation != currentTab) {
      context.go(currentTab);
      return;
    }

    if (widget.currentIndex != 0) {
      context.go(widget.tabs.first);
      return;
    }

    final now = DateTime.now();
    final shouldExit = _lastBackPressAt != null &&
        now.difference(_lastBackPressAt!) < const Duration(seconds: 2);
    if (shouldExit) {
      SystemNavigator.pop();
      return;
    }

    _lastBackPressAt = now;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Appuyez encore une fois pour quitter l’application.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        body: widget.body,
        bottomNavigationBar: widget.bottomNavigationBar,
      ),
    );
  }
}
