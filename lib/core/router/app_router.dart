import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../core/theme/app_colors.dart';

import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/role_selection_screen.dart';
import '../../features/auth/presentation/join_family_screen.dart';
import '../../features/parent/presentation/parent_home_screen.dart';
import '../../features/parent/presentation/child_config_screen.dart';
import '../../features/parent/presentation/child_detail_screen.dart';
import '../../features/parent/presentation/payout_screen.dart';
import '../../features/child/presentation/child_home_screen.dart';
import '../../features/subscription/paywall_screen.dart';
import '../../features/subscription/revenue_cat_service.dart'
    show kEntitlementPremium, checkTrialAccess;

// NOTE MVP+1 : ce provider est statique. Si l'état d'auth change en cours de
// session (ex: token expiré), le router ne se rafraîchit pas automatiquement.
// Solution future : passer une `refreshListenable` basée sur onAuthStateChange.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const _SplashRedirect(),
      ),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(
          path: '/role', builder: (_, __) => const RoleSelectionScreen()),
      GoRoute(
          path: '/join', builder: (_, __) => const JoinFamilyScreen()),
      GoRoute(
        path: '/parent',
        redirect: (context, state) async {
          // Gate trial/abonnement — seul le parent est bloqué
          final hasAccess = await _checkAccess();
          if (!hasAccess) return '/paywall?required=true';
          return null;
        },
        builder: (_, __) => const ParentHomeScreen(),
        routes: [
          GoRoute(
            path: 'child/:childId',
            builder: (_, state) =>
                ChildDetailScreen(childId: state.pathParameters['childId']!),
          ),
          GoRoute(
            path: 'config/:childId',
            builder: (_, state) =>
                ChildConfigScreen(childId: state.pathParameters['childId']!),
          ),
          GoRoute(
            path: 'payouts/:childId',
            builder: (_, state) =>
                PayoutScreen(childId: state.pathParameters['childId']!),
          ),
        ],
      ),
      GoRoute(path: '/child', builder: (_, __) => const ChildHomeScreen()),
      GoRoute(
        path: '/paywall',
        builder: (_, state) => PaywallScreen(
          isDismissible: state.uri.queryParameters['required'] != 'true',
        ),
      ),
    ],
  );
});

/// Vérifie si le parent a accès (trial valide ou abonné).
Future<bool> _checkAccess() async {
  try {
    // 1. Vérifier RevenueCat d'abord
    final info = await Purchases.getCustomerInfo();
    if (info.entitlements.active.containsKey(kEntitlementPremium)) return true;
  } catch (_) {}
  // 2. Fallback Supabase (trial 7j)
  return checkTrialAccess();
}

// Redirect initial : onboarding si première fois, sinon login ou app
class _SplashRedirect extends StatefulWidget {
  const _SplashRedirect();

  @override
  State<_SplashRedirect> createState() => _SplashRedirectState();
}

class _SplashRedirectState extends State<_SplashRedirect> {
  @override
  void initState() {
    super.initState();
    _redirect();
  }

  Future<void> _redirect() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      // Déjà connecté → va directement à l'app selon le rôle
      final data = await Supabase.instance.client
          .from('users')
          .select('role')
          .eq('id', session.user.id)
          .maybeSingle();
      if (!mounted) return;
      if (data == null) {
        // Profil absent en base → re-onboarding ou rôle à choisir
        context.go('/role');
      } else if (data['role'] == 'child') {
        context.go('/child');
      } else {
        context.go('/parent');
      }
      return;
    }

    // Pas connecté → onboarding si première fois, sinon login
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('onboarding_done') ?? false;
    if (!mounted) return;
    context.go(done ? '/login' : '/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.childBg,
      body: Center(
        child: Text('💰', style: TextStyle(fontSize: 48)),
      ),
    );
  }
}
