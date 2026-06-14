class ChildConfiguration {
  final String id;
  final String childId;
  final int baseWeeklyCents;      // socle garanti chaque semaine
  final int bonusHourlyRateCents; // taux du bonus par heure d'écran éteint
  final int bonusWeeklyMaxCents;  // plafond hebdo
  final int dailyMaxCents;        // plafond journalier
  final int activeHoursStart;
  final int activeHoursEnd;
  final int dailyTargetMinutes;
  final int paymentDay;           // 1=Lun … 7=Dim — jour à partir duquel le bouton versement apparaît

  const ChildConfiguration({
    required this.id,
    required this.childId,
    required this.baseWeeklyCents,
    required this.bonusHourlyRateCents,
    required this.bonusWeeklyMaxCents,
    required this.dailyMaxCents,
    required this.activeHoursStart,
    required this.activeHoursEnd,
    required this.dailyTargetMinutes,
    this.paymentDay = 5, // vendredi par défaut
  });

  double get baseWeeklyEuros => baseWeeklyCents / 100;
  double get bonusHourlyRateEuros => bonusHourlyRateCents / 100;
  double get bonusWeeklyMaxEuros => bonusWeeklyMaxCents / 100;
  double get dailyMaxEuros => dailyMaxCents / 100;
  double get weeklyMaxEuros => baseWeeklyEuros + dailyMaxEuros * 7;

  /// Vrai si aujourd'hui >= jour de paiement configuré
  bool get isPaymentDayReached => DateTime.now().weekday >= paymentDay;

  /// Vrai si l'heure actuelle est dans la plage où l'enfant gagne de l'argent.
  /// Gère le cas où la plage passe minuit (ex. 20h → 6h).
  bool get isWithinActiveHours {
    final h = DateTime.now().hour;
    if (activeHoursEnd > activeHoursStart) {
      return h >= activeHoursStart && h < activeHoursEnd;
    }
    // Plage qui passe minuit : active si après le début OU avant la fin.
    return h >= activeHoursStart || h < activeHoursEnd;
  }

  /// Plage horaire formatée pour l'affichage, ex. "17h–22h".
  String get activeHoursLabel => '${activeHoursStart}h–${activeHoursEnd}h';

  static const List<String> dayLabels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
  String get paymentDayLabel => dayLabels[paymentDay - 1];

  factory ChildConfiguration.fromJson(Map<String, dynamic> json) =>
      ChildConfiguration(
        id: json['id'] as String,
        childId: json['child_id'] as String,
        baseWeeklyCents: json['base_weekly_cents'] as int? ?? 2000,
        bonusHourlyRateCents: json['hourly_rate_cents'] as int,
        bonusWeeklyMaxCents: json['weekly_max_cents'] as int? ?? 2100,
        dailyMaxCents: json['daily_max_cents'] as int? ?? 300,
        activeHoursStart: json['active_hours_start'] as int,
        activeHoursEnd: json['active_hours_end'] as int,
        dailyTargetMinutes: json['daily_target_minutes'] as int,
        paymentDay: json['payment_day'] as int? ?? 5,
      );

  Map<String, dynamic> toJson() => {
        'child_id': childId,
        'base_weekly_cents': baseWeeklyCents,
        'hourly_rate_cents': bonusHourlyRateCents,
        'weekly_max_cents': bonusWeeklyMaxCents,
        'daily_max_cents': dailyMaxCents,
        'active_hours_start': activeHoursStart,
        'active_hours_end': activeHoursEnd,
        'daily_target_minutes': dailyTargetMinutes,
        'payment_day': paymentDay,
      };

  ChildConfiguration copyWith({
    int? baseWeeklyCents,
    int? bonusHourlyRateCents,
    int? bonusWeeklyMaxCents,
    int? dailyMaxCents,
    int? activeHoursStart,
    int? activeHoursEnd,
    int? dailyTargetMinutes,
    int? paymentDay,
  }) =>
      ChildConfiguration(
        id: id,
        childId: childId,
        baseWeeklyCents: baseWeeklyCents ?? this.baseWeeklyCents,
        bonusHourlyRateCents: bonusHourlyRateCents ?? this.bonusHourlyRateCents,
        bonusWeeklyMaxCents: bonusWeeklyMaxCents ?? this.bonusWeeklyMaxCents,
        dailyMaxCents: dailyMaxCents ?? this.dailyMaxCents,
        activeHoursStart: activeHoursStart ?? this.activeHoursStart,
        activeHoursEnd: activeHoursEnd ?? this.activeHoursEnd,
        dailyTargetMinutes: dailyTargetMinutes ?? this.dailyTargetMinutes,
        paymentDay: paymentDay ?? this.paymentDay,
      );
}
