import 'package:flutter/material.dart';

/// Central color tokens for RouzMe ("Refined Blue" scheme).
///
/// One brand blue does all the primary work; green is reserved for genuine
/// success, red for destructive actions, amber for highlight/snag. Neutrals
/// (slate greys) carry the rest of the UI. Prefer these tokens over raw
/// `Colors.*` literals so the palette stays consistent app-wide.
class AppColors {
  AppColors._();

  // Brand / primary
  static const Color primary = Color(0xFF1E6FE0); // buttons, links, app bar
  static const Color primaryDark = Color(0xFF1557B0); // pressed / emphasis
  static const Color brand = Color(0xFF2196F3); // matches the app icon
  static const Color onPrimary = Colors.white;

  // Semantic accents
  static const Color success = Color(0xFF2E9E5B); // 'done' states only
  static const Color danger = Color(0xFFE5484D); // delete / destructive
  static const Color highlight = Color(0xFFF5A623); // snag / unseen badge

  // Surfaces / neutrals
  static const Color background = Color(0xFFF7F8FA); // scaffold
  static const Color surface = Colors.white; // cards, sheets
  static const Color surfaceMuted = Color(0xFFEFF1F4); // subtle fills / chips
  static const Color border = Color(0xFFE3E6EB);

  // Text
  static const Color text = Color(0xFF1A1F2B); // primary text
  static const Color textMuted = Color(0xFF5B6472); // secondary / subtitles
  static const Color textFaint = Color(0xFF9AA1AD); // hints / disabled

  // Tinted fills (for icon-button backgrounds, chips, banners)
  static Color primaryTint = const Color(0xFF1E6FE0).withOpacity(0.10);
  static Color successTint = const Color(0xFF2E9E5B).withOpacity(0.12);
  static Color dangerTint = const Color(0xFFE5484D).withOpacity(0.10);
  static Color highlightTint = const Color(0xFFF5A623).withOpacity(0.15);
}
