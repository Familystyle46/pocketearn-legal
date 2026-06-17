import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/user_model.dart';
import '../../shared/models/configuration_model.dart';
import '../../shared/models/earning_model.dart';
import '../analytics/analytics_service.dart';
import 'supabase_config.dart';

export 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

final supabase = Supabase.instance.client;

Future<void> initSupabase() async {
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
}

// ── Auth ──────────────────────────────────────────────────────────────────────

Future<AuthResponse> signUp({
  required String email,
  required String password,
  required String name,
  required UserRole role,
}) async {
  final response = await supabase.auth.signUp(
    email: email,
    password: password,
    data: {'name': name, 'role': role.name},
  );
  return response;
}

Future<AuthResponse> signIn({
  required String email,
  required String password,
}) async {
  return supabase.auth.signInWithPassword(email: email, password: password);
}

Future<void> signOut() async {
  Analytics.setUser(id: null);
  await supabase.auth.signOut();
}

// ── Users ─────────────────────────────────────────────────────────────────────

Future<AppUser?> getCurrentUser() async {
  final authUser = supabase.auth.currentUser;
  if (authUser == null) return null;
  final data = await supabase
      .from('users')
      .select()
      .eq('id', authUser.id)
      .maybeSingle();
  if (data == null) return null;
  return AppUser.fromJson(data);
}

Future<List<AppUser>> getChildren(String familyId) async {
  final data = await supabase
      .from('users')
      .select()
      .eq('family_id', familyId)
      .eq('role', 'child');
  return (data as List).map((e) => AppUser.fromJson(e)).toList();
}

Future<AppUser?> joinFamilyByCode(String inviteCode) async {
  // Passe par une Edge Function (service role) car l'enfant n'est pas encore auth
  final response = await supabase.functions.invoke(
    'verify-invite-code',
    body: {'inviteCode': inviteCode.toUpperCase()},
  );
  if (response.status != 200) return null;
  final data = response.data as Map<String, dynamic>?;
  if (data == null || data['valid'] != true) return null;
  // Retourne un AppUser minimal pour confirmer que le code est valide
  return AppUser(
    id: '',
    familyId: '',
    role: UserRole.child,
    name: data['childName'] as String? ?? '',
  );
}

/// Crée un profil enfant via la Edge Function (appelée par le parent)
Future<String> createChild(String name) async {
  final response = await supabase.functions.invoke(
    'create-child',
    body: {'name': name},
  );
  if (response.status != 200) {
    final msg = response.data?['error'] ?? 'Erreur création enfant';
    throw Exception(msg);
  }
  return response.data['inviteCode'] as String;
}

/// Finalise le compte enfant : met à jour email+mdp du placeholder et
/// retourne la session Supabase pour connecter l'enfant directement.
Future<void> activateChild({
  required String inviteCode,
  required String email,
  required String password,
}) async {
  final response = await supabase.functions.invoke(
    'activate-child',
    body: {
      'inviteCode': inviteCode,
      'email': email,
      'password': password,
    },
  );
  if (response.status != 200) {
    final msg = response.data?['error'] ?? 'Erreur activation du compte';
    throw Exception(msg);
  }
  // La Edge Function a connecté l'enfant côté serveur ; on se connecte
  // côté client avec les tokens renvoyés.
  final accessToken  = response.data['access_token'] as String;
  final refreshToken = response.data['refresh_token'] as String;
  // setSession(refreshToken, accessToken:) rétablit la session côté client
  await supabase.auth.setSession(refreshToken, accessToken: accessToken);
}

/// Enregistre une session de pause écran
Future<void> saveSession({
  required String childId,
  required DateTime startAt,
  required DateTime endAt,
}) async {
  final durationSeconds = endAt.difference(startAt).inSeconds;
  if (durationSeconds < 60) return; // ignore les sessions < 1 minute

  await supabase.from('screen_sessions').insert({
    'child_id': childId,
    'start_at': startAt.toIso8601String(),
    'end_at': endAt.toIso8601String(),
    'duration_seconds': durationSeconds,
    'verified_at': DateTime.now().toIso8601String(), // auto-vérifié (timer volontaire)
  });
  // Le trigger PostgreSQL calcule automatiquement les gains
}

/// Crée une demande de virement
Future<void> requestPayout({
  required String childId,
  required String parentId,
  required int amountCents,
}) async {
  await supabase.from('payouts').insert({
    'child_id': childId,
    'parent_id': parentId,
    'amount_cents': amountCents,
    'status': 'pending',
  });
  Analytics.payoutRequested(amountCents);
}

// ── Configuration ─────────────────────────────────────────────────────────────

Future<ChildConfiguration?> getConfiguration(String childId) async {
  final data = await supabase
      .from('configurations')
      .select()
      .eq('child_id', childId)
      .order('updated_at', ascending: false)
      .limit(1);
  if ((data as List).isEmpty) return null;
  return ChildConfiguration.fromJson(data.first);
}

Future<void> upsertConfiguration(ChildConfiguration config) async {
  final data = config.toJson();
  // upsert sur child_id (contrainte unique) — ignore l'id si vide
  if (config.id.isEmpty) data.remove('id');
  await supabase
      .from('configurations')
      .upsert(data, onConflict: 'child_id');
}

// ── Earnings ──────────────────────────────────────────────────────────────────

Future<int> getMonthlyBalance(String childId) async {
  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month, 1).toIso8601String();
  final data = await supabase
      .from('earnings')
      .select('amount_cents')
      .eq('child_id', childId)
      .gte('created_at', startOfMonth);
  return (data as List).fold<int>(
    0,
    (sum, e) => sum + (e['amount_cents'] as int),
  );
}

/// Somme des bonus gagnés depuis le lundi de la semaine courante.
Future<int> getWeeklyBonus(String childId) async {
  final now = DateTime.now();
  final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
  final startOfWeekStr = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day).toIso8601String();
  final data = await supabase
      .from('earnings')
      .select('amount_cents')
      .eq('child_id', childId)
      .gte('created_at', startOfWeekStr);
  return (data as List).fold<int>(0, (sum, e) => sum + (e['amount_cents'] as int));
}

Future<int> getTodayBalance(String childId) async {
  final today = DateTime.now();
  final startOfDay =
      DateTime(today.year, today.month, today.day).toIso8601String();
  final data = await supabase
      .from('earnings')
      .select('amount_cents')
      .eq('child_id', childId)
      .gte('created_at', startOfDay);
  return (data as List).fold<int>(
    0,
    (sum, e) => sum + (e['amount_cents'] as int),
  );
}

Future<List<Earning>> getRecentEarnings(String childId, {int limit = 30}) async {
  final data = await supabase
      .from('earnings')
      .select()
      .eq('child_id', childId)
      .order('created_at', ascending: false)
      .limit(limit);
  return (data as List).map((e) => Earning.fromJson(e)).toList();
}

// ── Payouts ───────────────────────────────────────────────────────────────────

Future<List<Payout>> getPendingPayouts(String parentId) async {
  final data = await supabase
      .from('payouts')
      .select()
      .eq('parent_id', parentId)
      .eq('status', 'pending')
      .order('created_at', ascending: false);
  return (data as List).map((e) => Payout.fromJson(e)).toList();
}

Future<void> validatePayout(String payoutId) async {
  final rows = await supabase
      .from('payouts')
      .update({'status': 'validated', 'paid_at': DateTime.now().toIso8601String()})
      .eq('id', payoutId)
      .select('amount_cents');
  final amount =
      (rows as List).isNotEmpty ? (rows.first['amount_cents'] as int? ?? 0) : 0;
  Analytics.payoutValidated(amount);
}

/// Retourne le total déjà versé à cet enfant depuis le début de la semaine courante.
/// Permet de calculer le "vrai" solde restant à verser.
Future<int> getWeeklyPaidOut(String childId) async {
  final now = DateTime.now();
  final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
  final startOfWeekStr = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day).toIso8601String();
  final data = await supabase
      .from('payouts')
      .select('amount_cents')
      .eq('child_id', childId)
      .eq('status', 'validated')
      .gte('paid_at', startOfWeekStr);
  return (data as List).fold<int>(0, (sum, e) => sum + (e['amount_cents'] as int? ?? 0));
}

// ── Stats hebdomadaires ───────────────────────────────────────────────────────

class DayStat {
  final DateTime date;
  final int durationMinutes;
  final int earnedCents;

  const DayStat({
    required this.date,
    required this.durationMinutes,
    required this.earnedCents,
  });

  double get earnedEuros => earnedCents / 100;
  String get dayLabel {
    const labels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return labels[date.weekday - 1];
  }

  bool get isToday {
    final now = DateTime.now();
    return date.day == now.day &&
        date.month == now.month &&
        date.year == now.year;
  }
}

Future<List<DayStat>> getWeeklyStats(String childId) async {
  final data = await supabase.rpc(
    'get_weekly_stats',
    params: {'p_child_id': childId},
  );
  return (data as List).map((row) => DayStat(
    date: DateTime.parse(row['day_date']),
    durationMinutes: row['duration_minutes'] as int,
    earnedCents: row['earned_cents'] as int,
  )).toList();
}

// ── Temps d'écran (bien-être numérique) ───────────────────────────────────────
// Découplé de la chaîne de gains : alimente uniquement l'affichage parent.

/// Temps d'écran de la semaine courante (lun→dim), zero-fillé sur 7 jours.
/// Renvoie une map { date (jour) → minutes }.
Future<Map<DateTime, int>> getWeeklyScreenTime(String childId) async {
  final data = await supabase.rpc(
    'get_weekly_screen_time',
    params: {'p_child_id': childId},
  );
  final result = <DateTime, int>{};
  for (final row in (data as List)) {
    result[DateTime.parse(row['day_date'])] = row['screen_minutes'] as int;
  }
  return result;
}

/// Remonte le temps d'écran quotidien (depuis le device enfant) vers Supabase.
/// [days] : liste d'entrées {"day": "yyyy-MM-dd", "minutes": int}.
/// Upsert idempotent sur (child_id, day) — re-jouable sans effet de bord.
Future<void> upsertScreenTime(String childId, List<Map<String, dynamic>> days) async {
  if (days.isEmpty) return;
  final rows = days
      .map((d) => {
            'child_id': childId,
            'day': d['day'],
            'minutes': d['minutes'],
            'updated_at': DateTime.now().toIso8601String(),
          })
      .toList();
  await supabase.from('screen_time_daily').upsert(rows, onConflict: 'child_id,day');
}

/// iOS : règle les gains du jour à partir de l'usage mesuré (Family Controls).
/// Convertit l'usage en équivalent écran-éteint et applique la même formule
/// qu'Android, via la RPC sécurisée `settle_ios_screen_time` (idempotente).
/// [day] : "yyyy-MM-dd". Renvoie le bonus en cents réglé pour ce jour.
Future<int> settleIosScreenTime(String childId, String day, int usedMinutes) async {
  final res = await supabase.rpc('settle_ios_screen_time', params: {
    'p_child_id': childId,
    'p_day': day,
    'p_used_window_minutes': usedMinutes,
  });
  return (res as int?) ?? 0;
}

Future<int> getStreak(String childId) async {
  // Nombre de jours consécutifs avec au moins une session (en remontant depuis aujourd'hui)
  final data = await supabase
      .from('screen_sessions')
      .select('start_at')
      .eq('child_id', childId)
      .gte('start_at', DateTime.now().subtract(const Duration(days: 30)).toIso8601String())
      .order('start_at', ascending: false);

  if ((data as List).isEmpty) return 0;

  final days = data
      .map((r) => DateTime.parse(r['start_at']).toLocal())
      .map((d) => DateTime(d.year, d.month, d.day))
      .toSet()
      .toList()
    ..sort((a, b) => b.compareTo(a));

  int streak = 0;
  final today = DateTime.now();
  var expected = DateTime(today.year, today.month, today.day);

  for (final day in days) {
    if (day == expected) {
      // Le jour correspond exactement au jour attendu → on continue
      streak++;
      expected = expected.subtract(const Duration(days: 1));
    } else if (streak == 0 && day == expected.subtract(const Duration(days: 1))) {
      // Tolérance sur le premier jour : si aucune session aujourd'hui,
      // le streak commence hier
      streak++;
      expected = day.subtract(const Duration(days: 1));
    } else {
      break;
    }
  }
  return streak;
}

RealtimeChannel subscribeToChildBalance(
  String childId,
  void Function(int balanceCents) onUpdate,
) {
  return supabase
      .channel('earnings:$childId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'earnings',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'child_id',
          value: childId,
        ),
        callback: (_) async {
          final balance = await getMonthlyBalance(childId);
          onUpdate(balance);
        },
      )
      .subscribe();
}
