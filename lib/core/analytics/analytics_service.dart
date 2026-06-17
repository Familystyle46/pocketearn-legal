import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Service centralisé Firebase Analytics.
///
/// 100 % additif : Firebase est déjà initialisé via `Firebase.initializeApp()`
/// dans `initNotifications()`. Analytics ne nécessite aucune init séparée — on
/// se contente d'utiliser l'instance et de logger des events.
///
/// - Events automatiques (sessions, première ouverture, rétention, pays, OS…)
///   sont collectés sans aucun code.
/// - On ajoute ici quelques events MÉTIER clés pour suivre le funnel
///   (essai → paywall → abonnement) et l'usage (enfant créé, versement demandé).
///
/// Tous les appels sont non bloquants et avalent leurs erreurs : l'analytics ne
/// doit JAMAIS faire planter ni ralentir l'app.
class Analytics {
  Analytics._();

  static final FirebaseAnalytics instance = FirebaseAnalytics.instance;

  /// Observer à brancher sur le routeur pour tracer les écrans automatiquement.
  static final FirebaseAnalyticsObserver observer =
      FirebaseAnalyticsObserver(analytics: instance);

  static Future<void> _log(String name, [Map<String, Object>? params]) async {
    try {
      await instance.logEvent(name: name, parameters: params);
    } catch (e) {
      // On n'interrompt jamais le flux applicatif pour de l'analytics.
      if (kDebugMode) debugPrint('[analytics] échec event "$name": $e');
    }
  }

  /// Associe les events à un identifiant (haché côté Firebase). À appeler après
  /// login/signup. `null` pour dissocier (déconnexion).
  static Future<void> setUser({String? id, String? role}) async {
    try {
      await instance.setUserId(id: id);
      if (role != null) await instance.setUserProperty(name: 'role', value: role);
    } catch (_) {}
  }

  // ── Funnel monétisation ────────────────────────────────────────────────────
  static Future<void> signUp(String method) =>
      _log('sign_up', {'method': method});

  static Future<void> login(String method) =>
      _log('login', {'method': method});

  static Future<void> trialStarted() => _log('trial_started');

  static Future<void> paywallViewed({required bool required}) =>
      _log('paywall_viewed', {'blocking': required});

  static Future<void> subscribe(String plan) =>
      _log('subscribe', {'plan': plan});

  static Future<void> subscribeRestored() => _log('subscribe_restored');

  // ── Usage produit ──────────────────────────────────────────────────────────
  static Future<void> childCreated() => _log('child_created');

  static Future<void> childJoined() => _log('child_joined');

  static Future<void> payoutRequested(int amountCents) =>
      _log('payout_requested', {'amount_cents': amountCents});

  static Future<void> payoutValidated(int amountCents) =>
      _log('payout_validated', {'amount_cents': amountCents});
}
