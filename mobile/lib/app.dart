import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class DenkmaApp extends ConsumerStatefulWidget {
  const DenkmaApp({super.key});

  @override
  ConsumerState<DenkmaApp> createState() => _DenkmaAppState();
}

class _DenkmaAppState extends ConsumerState<DenkmaApp>
    with WidgetsBindingObserver {
  bool _refreshingSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshSessionIfNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSessionIfNeeded();
    }
  }

  Future<void> _refreshSessionIfNeeded() async {
    if (_refreshingSession) return;
    final auth = ref.read(authProvider).valueOrNull;
    if (auth == null || !auth.isAuthenticated) return;
    _refreshingSession = true;
    try {
      await ref.read(authProvider.notifier).fetchMe();
    } finally {
      _refreshingSession = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Denkma',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
