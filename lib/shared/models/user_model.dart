enum UserRole { parent, child }

class AppUser {
  final String id;
  final String familyId;
  final UserRole role;
  final String name;
  final String? avatarUrl;
  final String? inviteCode; // pour les enfants

  const AppUser({
    required this.id,
    required this.familyId,
    required this.role,
    required this.name,
    this.avatarUrl,
    this.inviteCode,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        familyId: (json['family_id'] as String?) ?? '',
        role: json['role'] == 'parent' ? UserRole.parent : UserRole.child,
        name: (json['name'] as String?) ?? 'Utilisateur',
        avatarUrl: json['avatar_url'] as String?,
        inviteCode: json['invite_code'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'family_id': familyId,
        'role': role.name,
        'name': name,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (inviteCode != null) 'invite_code': inviteCode,
      };
}
