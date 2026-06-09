import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/supabase/supabase_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/notifications/notification_service.dart';
import 'features/subscription/revenue_cat_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  await initNotifications();

  // Initialise RevenueCat + FCM si un utilisateur est déjà connecté
  final currentUser = supabase.auth.currentUser;
  if (currentUser != null) {
    try {
      await initRevenueCat(currentUser.id);
    } catch (_) {}
    // Sauvegarde le token FCM du parent (non bloquant)
    saveFCMToken(currentUser.id);
  }

  runApp(const ProviderScope(child: TiipeeApp()));
}

class TiipeeApp extends ConsumerWidget {
  const TiipeeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Tiipee',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
