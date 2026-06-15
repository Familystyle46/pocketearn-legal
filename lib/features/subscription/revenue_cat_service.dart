import 'dart:io';
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/supabase/supabase_service.dart';

// Clés RevenueCat — https://app.revenuecat.com
// Android : clé publique SDK du projet Tiipee (goog_...).
// iOS : clé publique SDK App Store du projet Tiipee (appl_...).
const _revenueCatAndroidKey = 'goog_AvGxpExPAvOuBQbSrLwLwJzRIYb';
const _revenueCatIosKey     = 'appl_dSBxcpFOpUcCfAnAyjPOwvCFUfd';

const kProductMonthly = 'tiipee_monthly'; // ID du produit dans Play Store / App Store
const kProductYearly = 'tiipee_yearly';
const kEntitlementPremium = 'premium';

Future<void> initRevenueCat(String userId) async {
  await Purchases.setLogLevel(LogLevel.debug);
  final config = PurchasesConfiguration(
    Platform.isAndroid ? _revenueCatAndroidKey : _revenueCatIosKey,
  )..appUserID = userId;
  await Purchases.configure(config);
}

final subscriptionProvider = FutureProvider<bool>((ref) async {
  try {
    // Garde : si le SDK n'est pas configuré (ex. juste après login avant init),
    // ne PAS appeler getCustomerInfo — sur iOS c'est un fatalError non
    // rattrapable qui crashe l'app. On bascule sur le fallback Supabase.
    if (!await Purchases.isConfigured) {
      return checkTrialAccess();
    }
    final info = await Purchases.getCustomerInfo();
    return info.entitlements.active.containsKey(kEntitlementPremium);
  } catch (_) {
    // Fallback : vérifie le trial côté Supabase
    return checkTrialAccess();
  }
});

/// Prix affichés sur le paywall — RÉELS et localisés (jamais codés en dur),
/// récupérés depuis l'offering RevenueCat (= vrai prix de chaque store).
class PaywallPrices {
  final String monthly; // ex. "3,99 €"
  final String yearly; // ex. "39,99 €"
  final String yearlyPerMonth; // ex. "3,33 €"
  final int savingsPercent; // ex. 16

  const PaywallPrices({
    required this.monthly,
    required this.yearly,
    required this.yearlyPerMonth,
    required this.savingsPercent,
  });

  /// Valeurs de repli si l'offering ne charge pas (offline, sandbox…).
  /// Alignées sur le tarif voulu : mensuel 3,99 € / annuel 39,99 €.
  static const fallback = PaywallPrices(
    monthly: '3,99 €',
    yearly: '39,99 €',
    yearlyPerMonth: '3,33 €',
    savingsPercent: 16,
  );
}

/// Lit les prix réels depuis RevenueCat. Le paywall doit afficher ÇA, jamais
/// des constantes — sinon le prix affiché peut différer du prix débité.
final paywallPricesProvider = FutureProvider<PaywallPrices>((ref) async {
  try {
    if (!await Purchases.isConfigured) return PaywallPrices.fallback;
    final offerings = await Purchases.getOfferings();
    final monthly = offerings.current?.monthly?.storeProduct;
    final yearly = offerings.current?.annual?.storeProduct;
    if (monthly == null || yearly == null) return PaywallPrices.fallback;

    final perMonthValue = yearly.price / 12.0;
    final perMonthStr = NumberFormat.simpleCurrency(
      locale: 'fr_FR',
      name: yearly.currencyCode,
    ).format(perMonthValue);

    // Économie de l'annuel vs mensuel (en %), bornée à [0, 99].
    var savings = 0;
    if (monthly.price > 0) {
      savings = ((1 - perMonthValue / monthly.price) * 100).round().clamp(0, 99);
    }

    return PaywallPrices(
      monthly: monthly.priceString,
      yearly: yearly.priceString,
      yearlyPerMonth: perMonthStr,
      savingsPercent: savings,
    );
  } catch (_) {
    return PaywallPrices.fallback;
  }
});

/// Vérifie l'accès côté Supabase : trial 7 jours ou abonnement actif.
Future<bool> checkTrialAccess() async {
  final user = await getCurrentUser();
  if (user == null) return false;
  final rows = await supabase
      .from('families')
      .select('subscription_status, trial_started_at')
      .eq('id', user.familyId)
      .limit(1);
  if ((rows as List).isEmpty) return false;
  final data = rows.first;
  if (data['subscription_status'] == 'active') return true;
  if (data['subscription_status'] == 'trial') {
    final started = DateTime.parse(data['trial_started_at'] as String);
    return DateTime.now().difference(started).inDays < 7; // trial 7 jours
  }
  return false;
}

/// Retourne les jours restants de trial (0 si expiré ou abonné).
Future<int> trialDaysLeft() async {
  final user = await getCurrentUser();
  if (user == null) return 0;
  final rows = await supabase
      .from('families')
      .select('subscription_status, trial_started_at')
      .eq('id', user.familyId)
      .limit(1);
  if ((rows as List).isEmpty) return 0;
  final data = rows.first;
  if (data['subscription_status'] == 'active') return 0;
  if (data['subscription_status'] == 'trial') {
    final started = DateTime.parse(data['trial_started_at'] as String);
    final elapsed = DateTime.now().difference(started).inDays;
    return (7 - elapsed).clamp(0, 7);
  }
  return 0;
}

Future<bool> purchaseMonthly() async {
  try {
    final offerings = await Purchases.getOfferings();
    final pkg = offerings.current?.monthly;
    if (pkg == null) return false;
    await Purchases.purchasePackage(pkg);
    return true;
  } catch (e) {
    return false;
  }
}

Future<bool> purchaseYearly() async {
  try {
    final offerings = await Purchases.getOfferings();
    final pkg = offerings.current?.annual;
    if (pkg == null) return false;
    await Purchases.purchasePackage(pkg);
    return true;
  } catch (e) {
    return false;
  }
}

Future<void> restorePurchases() async {
  await Purchases.restorePurchases();
}
