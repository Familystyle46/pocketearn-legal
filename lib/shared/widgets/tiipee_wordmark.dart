import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Logotype Tiipee : « tiipee » avec les deux « ii » en or.
/// Réutilisable (onboarding, login, en-têtes…).
class TiipeeWordmark extends StatelessWidget {
  final double fontSize;
  final Color baseColor;

  const TiipeeWordmark({
    super.key,
    this.fontSize = 28,
    this.baseColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          height: 1,
        ),
        children: [
          TextSpan(text: 't', style: TextStyle(color: baseColor)),
          const TextSpan(text: 'ii', style: TextStyle(color: AppColors.gold)),
          TextSpan(text: 'pee', style: TextStyle(color: baseColor)),
        ],
      ),
    );
  }
}
