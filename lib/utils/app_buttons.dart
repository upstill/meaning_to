import 'package:flutter/material.dart';
import 'package:meaning_to/theme/app_colors.dart';

/// Semantic button styles for RouzMe ("Refined Blue" scheme).
///
/// Roles (use these — not raw colors):
///   • primary     — the ONE main action per view (Save, Go, Accept, Snag). Filled blue.
///   • secondary   — an alternative action alongside a primary. Outlined blue.
///   • neutral     — Cancel / Back / dismiss. Plain grey text, no fill.
///   • destructive — Delete / irreversible. Red text (outlined when it needs weight).
///   • success     — genuine "done!" confirmations ONLY. Filled green (used sparingly).
///
/// Legacy names (`goForth`, `finalize`, `cancel`) are kept as aliases so existing
/// call sites compile; `finalize` now maps to the single primary blue (no more
/// blue-vs-green split). New code should use the semantic names above.
class AppButtons {
  // ---- Palette (kept for direct references; sourced from tokens) ----
  static const Color primaryBg = AppColors.primary;
  static const Color primaryFg = AppColors.onPrimary;
  static const Color successBg = AppColors.success;
  static const Color successFg = Colors.white;
  static const Color dangerBg = AppColors.danger;
  static const Color dangerFg = Colors.white;
  static const Color neutralFg = AppColors.textMuted;

  // Legacy aliases (do not use in new code).
  static const Color finalizeBg = AppColors.primary; // was green -> now primary
  static const Color finalizeFg = AppColors.onPrimary;
  static const Color goForthBg = AppColors.primary;
  static const Color goForthFg = AppColors.onPrimary;
  static const Color cancelBg = AppColors.textMuted;
  static const Color cancelFg = Colors.white;

  static const _radius = 12.0;
  static final _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(_radius),
  );
  static const _pad = EdgeInsets.symmetric(horizontal: 20, vertical: 12);

  // ---- Filled (ElevatedButton) ----
  static ButtonStyle primary() => ElevatedButton.styleFrom(
        backgroundColor: primaryBg,
        foregroundColor: primaryFg,
        elevation: 0,
        padding: _pad,
        shape: _shape,
      );

  static ButtonStyle success() => ElevatedButton.styleFrom(
        backgroundColor: successBg,
        foregroundColor: successFg,
        elevation: 0,
        padding: _pad,
        shape: _shape,
      );

  static ButtonStyle destructive() => ElevatedButton.styleFrom(
        backgroundColor: dangerBg,
        foregroundColor: dangerFg,
        elevation: 0,
        padding: _pad,
        shape: _shape,
      );

  // ---- Outlined ----
  static ButtonStyle secondary() => OutlinedButton.styleFrom(
        foregroundColor: primaryBg,
        side: const BorderSide(color: primaryBg),
        padding: _pad,
        shape: _shape,
      );

  static ButtonStyle destructiveOutlined() => OutlinedButton.styleFrom(
        foregroundColor: dangerBg,
        side: const BorderSide(color: dangerBg),
        padding: _pad,
        shape: _shape,
      );

  // ---- Text (neutral / low-emphasis) ----
  static ButtonStyle neutral() => TextButton.styleFrom(
        foregroundColor: neutralFg,
        padding: _pad,
      );

  static ButtonStyle destructiveText() => TextButton.styleFrom(
        foregroundColor: dangerBg,
        padding: _pad,
      );

  // ---- Icon buttons ----
  static ButtonStyle iconPrimary() => IconButton.styleFrom(
        backgroundColor: AppColors.primaryTint,
        foregroundColor: primaryBg,
      );

  static ButtonStyle iconDestructive() => IconButton.styleFrom(
        backgroundColor: AppColors.dangerTint,
        foregroundColor: dangerBg,
      );

  // ---- Legacy aliases (map onto the new semantic roles) ----
  static ButtonStyle finalize() => primary();
  static ButtonStyle goForth() => primary();
  static ButtonStyle cancel() => neutral();
  static ButtonStyle finalizeOutlined() => secondary();
  static ButtonStyle goForthOutlined() => secondary();
  static ButtonStyle cancelOutlined() => OutlinedButton.styleFrom(
        foregroundColor: neutralFg,
        side: const BorderSide(color: AppColors.border),
        padding: _pad,
        shape: _shape,
      );
  static ButtonStyle iconGoForth() => iconPrimary();
  static ButtonStyle iconFinalize() => iconPrimary();
  static ButtonStyle iconCancel() => IconButton.styleFrom(
        backgroundColor: AppColors.surfaceMuted,
        foregroundColor: neutralFg,
      );
}
