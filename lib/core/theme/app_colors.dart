import 'package:flutter/material.dart';

// ── Palette PocketEarn ────────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  // Vert principal — énergie, argent, réussite
  static const emerald = Color(0xFF00C853);
  static const emeraldDark = Color(0xFF00A040);
  static const emeraldLight = Color(0xFFB9F6CA);

  // Dark mode enfant
  static const childBg = Color(0xFF0A0E1A);
  static const childSurface = Color(0xFF141927);
  static const childCard = Color(0xFF1E2538);
  static const childBorder = Color(0xFF2A3350);

  // Light mode parent (conservé pour compatibilité)
  static const parentBg = Color(0xFFF7F8FC);
  static const parentSurface = Color(0xFFFFFFFF);
  static const parentCard = Color(0xFFFFFFFF);

  // Dark mode parent — même esprit que l'enfant, teinte forêt
  static const parentDarkBg      = Color(0xFF0A1A0E);
  static const parentDarkSurface = Color(0xFF112215);
  static const parentDarkCard    = Color(0xFF172D1C);
  static const parentDarkBorder  = Color(0xFF1E3D24);

  // Textes
  static const textDark = Color(0xFF0A0E1A);
  static const textLight = Color(0xFFF0F4FF);
  static const textMuted = Color(0xFF8896B3);
  static const textSubtle = Color(0xFF4A5578);

  // Accents
  static const gold = Color(0xFFFFD700);
  static const amber = Color(0xFFFFAB00);
  static const rose = Color(0xFFFF4D6D);
  static const violet = Color(0xFF7C3AED);

  // Gradients
  static const gradientEmerald = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00C853), Color(0xFF00E676)],
  );

  static const gradientChildHeader = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0A0E1A), Color(0xFF141927)],
  );

  static const gradientParentCard = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF166534), Color(0xFF15803D)],
  );

  static const gradientGold = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFAB00), Color(0xFFFFD740)],
  );
}

// ── Thème enfant (dark) ───────────────────────────────────────────────────────
extension AppThemeExtension on BuildContext {
  bool get isChildMode =>
      Theme.of(this).brightness == Brightness.dark;
}
