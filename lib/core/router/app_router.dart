// lib/core/router/app_router.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../di/providers.dart';
import '../../ui/auth/login_page.dart';
import '../../ui/auth/onboarding_page.dart';
import '../../ui/shell/main_shell.dart';
import '../../ui/pos/checkout_page.dart';
import '../../ui/inventory/inventory_page.dart';
import '../../ui/customers/customers_page.dart';
import '../../ui/reports/reports_page.dart';
import '../../ui/settings/settings_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/pos',
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final user = Supabase.instance.client.auth.currentUser;
      final isLoggedIn = user != null;
      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/onboarding';

      if (!isLoggedIn && !isAuthRoute) return '/login';
      if (isLoggedIn && isAuthRoute) return '/pos';
      return null;
    },
    routes: [
      // ── Auth routes ──────────────────────────────────────
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),

      // ── Main app shell with bottom nav ───────────────────
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/pos',
            name: 'pos',
            builder: (context, state) {
              final store = ref.read(obxStoreProvider);
              final sync = ref.read(syncServiceProvider);
              final supabase = ref.read(supabaseProvider);
              final tenantId = ref.read(tenantIdProvider) ?? '';
              return CheckoutPage(
                store: store,
                syncService: sync,
                tenantId: tenantId,
                supabase: supabase,
              );
            },
          ),
          GoRoute(
            path: '/inventory',
            name: 'inventory',
            builder: (context, state) => const InventoryPage(),
          ),
          GoRoute(
            path: '/customers',
            name: 'customers',
            builder: (context, state) => const CustomersPage(),
          ),
          GoRoute(
            path: '/reports',
            name: 'reports',
            builder: (context, state) => const ReportsPage(),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) => const SettingsPage(),
          ),
        ],
      ),
    ],
  );
});
