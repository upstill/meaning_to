import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────────────────
///  RouzMe design decisions — the SINGLE place to change the app's look.
/// ─────────────────────────────────────────────────────────────────────────
///
/// Everything visual and tunable lives here: the colour palette, corner radii,
/// spacing scale, type sizes/weights, and per-component knobs. To restyle the
/// app, edit the values in this file — `AppTheme` (lib/theme/app_theme.dart)
/// and `AppButtons` (lib/utils/app_buttons.dart) derive everything from these,
/// and screens reference them via [AppColors] (a thin alias kept for
/// convenience). Scheme in force: "Refined Blue" (one brand blue does the
/// primary work; green = success only, red = destructive, amber = highlight).
///
/// Keep this file free of widget-building logic — it holds decisions (values),
/// not wiring. The wiring lives in app_theme.dart.
class Design {
  Design._();

  // ── BRAND / PRIMARY ──────────────────────────────────────────────────────
  static const Color primary = Color(0xFF1E6FE0); // buttons, links, app bar
  static const Color primaryDark = Color(0xFF1557B0); // pressed / gradients
  static const Color brand = Color(0xFF2196F3); // matches the app icon
  static const Color onPrimary = Colors.white; // text/icons on primary

  // ── SEMANTIC ACCENTS ─────────────────────────────────────────────────────
  static const Color success = Color(0xFF2E9E5B); // 'done' states only
  static const Color danger = Color(0xFFE5484D); // delete / destructive
  static const Color highlight = Color(0xFFF5A623); // snag / unseen badge

  // ── SURFACES / NEUTRALS ──────────────────────────────────────────────────
  static const Color background = Color(0xFFF7F8FA); // scaffold
  static const Color surface = Colors.white; // cards, sheets, dialogs
  static const Color surfaceMuted = Color(0xFFEFF1F4); // chips / subtle fills
  static const Color border = Color(0xFFE3E6EB);

  // ── TEXT ─────────────────────────────────────────────────────────────────
  static const Color text = Color(0xFF1A1F2B); // primary text / headlines
  static const Color textMuted = Color(0xFF5B6472); // subtitles / secondary
  static const Color textFaint = Color(0xFF9AA1AD); // hints / disabled

  // ── TINTED FILLS (icon-button backgrounds, banners) ──────────────────────
  static Color get primaryTint => primary.withOpacity(0.10);
  static Color get successTint => success.withOpacity(0.12);
  static Color get dangerTint => danger.withOpacity(0.10);
  static Color get highlightTint => highlight.withOpacity(0.15);

  // ── SHAPE (corner radii, in logical px) ──────────────────────────────────
  static const double radiusSm = 8; // chips, small controls
  static const double radiusMd = 12; // buttons, cards (the default)
  static const double radiusLg = 16; // dialogs
  static const double radiusInput = 10; // text fields
  static const double radiusSheet = 20; // bottom-sheet top corners

  // ── SPACING SCALE (in logical px) ────────────────────────────────────────
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;

  // ── TYPOGRAPHY ───────────────────────────────────────────────────────────
  // Sizes
  static const double fontAppBarTitle = 20;
  static const double fontDialogTitle = 18;
  static const double fontSectionTitle = 18; // e.g. bottom-sheet headers
  static const double fontButton = 15;
  static const double fontBody = 15;
  static const double fontPursuitMenuTitle = 21; // pursuit-switcher list rows
  // Weights
  static const FontWeight weightSemibold = FontWeight.w600;
  static const FontWeight weightBold = FontWeight.w700;

  // ── COMPONENT KNOBS ──────────────────────────────────────────────────────
  static const EdgeInsets buttonPadding =
      EdgeInsets.symmetric(horizontal: 20, vertical: 12);
  static const EdgeInsets inputPadding =
      EdgeInsets.symmetric(horizontal: 14, vertical: 12);
  static const EdgeInsets cardMargin = EdgeInsets.symmetric(vertical: 6);
  static const double inputFocusBorderWidth = 1.5;
  static const double dividerThickness = 1;
}
