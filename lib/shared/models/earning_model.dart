class Earning {
  final String id;
  final String childId;
  final String? sessionId;
  final int amountCents;
  final DateTime createdAt;

  const Earning({
    required this.id,
    required this.childId,
    this.sessionId,
    required this.amountCents,
    required this.createdAt,
  });

  double get amountEuros => amountCents / 100;

  factory Earning.fromJson(Map<String, dynamic> json) => Earning(
        id: json['id'] as String,
        childId: json['child_id'] as String,
        sessionId: json['session_id'] as String?,
        amountCents: json['amount_cents'] as int,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class ScreenSession {
  final String id;
  final String childId;
  final DateTime startAt;
  final DateTime? endAt;
  final int durationSeconds;
  final bool verified;

  const ScreenSession({
    required this.id,
    required this.childId,
    required this.startAt,
    this.endAt,
    required this.durationSeconds,
    required this.verified,
  });

  Duration get duration => Duration(seconds: durationSeconds);

  factory ScreenSession.fromJson(Map<String, dynamic> json) => ScreenSession(
        id: json['id'] as String,
        childId: json['child_id'] as String,
        startAt: DateTime.parse(json['start_at'] as String),
        endAt: json['end_at'] != null
            ? DateTime.parse(json['end_at'] as String)
            : null,
        durationSeconds: json['duration_seconds'] as int,
        verified: json['verified_at'] != null,
      );
}

class Payout {
  final String id;
  final String childId;
  final String parentId;
  final int amountCents;
  final PayoutStatus status;
  final DateTime createdAt;

  const Payout({
    required this.id,
    required this.childId,
    required this.parentId,
    required this.amountCents,
    required this.status,
    required this.createdAt,
  });

  double get amountEuros => amountCents / 100;

  factory Payout.fromJson(Map<String, dynamic> json) => Payout(
        id: json['id'] as String,
        childId: json['child_id'] as String,
        parentId: json['parent_id'] as String,
        amountCents: json['amount_cents'] as int,
        status: PayoutStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => PayoutStatus.pending,
        ),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

enum PayoutStatus { pending, validated, paid }
