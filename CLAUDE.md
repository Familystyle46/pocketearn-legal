# Tiipee — CLAUDE.md

## Stack
- Flutter/Dart + Riverpod + GoRouter
- Supabase (auth, PostgreSQL RLS, realtime, edge functions Deno/TS)
- Android native : Kotlin `ScreenMonitorService.kt` via EventChannel `com.tiipee/screen_events`
- iOS native : stub seulement (entitlement Apple FamilyControls requis)

## Supabase
- Project ID : `yphctchmugijwecscxmx`
- URL : `https://yphctchmugijwecscxmx.supabase.co`
- Config dans `lib/core/supabase/supabase_config.dart`
- Edge functions : `create-child`, `activate-child` (verify_jwt: false), `weekly-recap`

## Structure lib/
```
core/         → supabase_service.dart, theme, routing
features/
  parent/     → parent_home_screen, child_detail_screen, child_config_screen, payout_screen
  child/      → child_home_screen, streak_badge_widget
  auth/       → onboarding, login, signup, join_family, role_selection
  screen_time/→ screen_time_service.dart (platform channel)
shared/
  models/     → user_model, configuration_model, earning_model
  providers/  → config_provider.dart  ← provider partagé pour ChildConfiguration
  widgets/    → app_button
```

## Règles métier
- Récompense = `base_weekly_cents` (garanti) + bonus (taux horaire × temps écran éteint, plafonné par `weekly_max_cents`)
- Plage horaire active : `active_hours_start` → `active_hours_end`
- Objectif quotidien : `daily_target_minutes`
- Earnings créés par trigger PostgreSQL à l'insert d'une `screen_session` avec `verified_at` non null

## Conventions
- Langue UI : français
- Thème parent : dark `#0A1A0E` / Thème enfant : dark avec `AppColors.childBg`
- Toujours invalider `configProvider(childId)` après upsert configuration
- Ne pas créer de provider local pour ChildConfiguration — utiliser `shared/providers/config_provider.dart`

## Ce qui manque
- Clés RevenueCat réelles dans `revenue_cat_service.dart`
- iOS Screen Time (en attente entitlement Apple)
- Store readiness (screenshots, onboarding, privacy policy)
