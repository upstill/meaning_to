import 'package:flutter/material.dart';
import 'package:meaning_to/theme/design.dart';

/// Colour aliases for RouzMe.
///
/// These simply re-expose the palette from [Design] — the single source of all
/// design decisions (lib/theme/design.dart). Kept so screens can keep writing
/// `AppColors.primary`; to CHANGE a colour, edit [Design], not this file.
class AppColors {
  AppColors._();

  static const Color primary = Design.primary;
  static const Color primaryDark = Design.primaryDark;
  static const Color brand = Design.brand;
  static const Color onPrimary = Design.onPrimary;

  static const Color success = Design.success;
  static const Color danger = Design.danger;
  static const Color highlight = Design.highlight;

  static const Color background = Design.background;
  static const Color surface = Design.surface;
  static const Color surfaceMuted = Design.surfaceMuted;
  static const Color border = Design.border;

  static const Color text = Design.text;
  static const Color textMuted = Design.textMuted;
  static const Color textFaint = Design.textFaint;

  static Color get primaryTint => Design.primaryTint;
  static Color get successTint => Design.successTint;
  static Color get dangerTint => Design.dangerTint;
  static Color get highlightTint => Design.highlightTint;
}
