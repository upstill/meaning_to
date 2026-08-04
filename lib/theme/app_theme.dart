import 'package:flutter/material.dart';
import 'package:meaning_to/theme/design.dart';

/// The single light theme for RouzMe, built entirely from [Design] tokens.
///
/// This is wiring, not decisions: app bar, buttons, cards, inputs, dialogs and
/// list tiles all pull from [Design] (lib/theme/design.dart), so to restyle the
/// app you edit Design — not this file. Screens that don't hardcode colours
/// inherit the "Refined Blue" look automatically.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: Design.primary,
      primary: Design.primary,
      onPrimary: Design.onPrimary,
      secondary: Design.brand,
      error: Design.danger,
      surface: Design.surface,
      brightness: Brightness.light,
    );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Design.radiusMd),
    );
    final buttonTextStyle = TextStyle(
      fontSize: Design.fontButton,
      fontWeight: Design.weightSemibold,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Design.background,
      canvasColor: Design.background,
      dividerColor: Design.border,
      dividerTheme: const DividerThemeData(
        color: Design.border,
        thickness: Design.dividerThickness,
        space: 1,
      ),
      textTheme: Typography.blackMountainView.apply(
        bodyColor: Design.text,
        displayColor: Design.text,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: Design.primary,
        foregroundColor: Design.onPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Design.onPrimary,
          fontSize: Design.fontAppBarTitle,
          fontWeight: Design.weightSemibold,
        ),
      ),

      cardTheme: CardThemeData(
        color: Design.surface,
        elevation: 0,
        margin: Design.cardMargin,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Design.radiusMd),
          side: const BorderSide(color: Design.border),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Design.primary,
          foregroundColor: Design.onPrimary,
          elevation: 0,
          padding: Design.buttonPadding,
          shape: buttonShape,
          textStyle: buttonTextStyle,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Design.primary,
          foregroundColor: Design.onPrimary,
          padding: Design.buttonPadding,
          shape: buttonShape,
          textStyle: buttonTextStyle,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Design.primary,
          side: const BorderSide(color: Design.primary),
          padding: Design.buttonPadding,
          shape: buttonShape,
          textStyle: buttonTextStyle,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Design.primary,
          textStyle: buttonTextStyle,
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Design.primary,
        foregroundColor: Design.onPrimary,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Design.surface,
        isDense: true,
        contentPadding: Design.inputPadding,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Design.radiusInput),
          borderSide: const BorderSide(color: Design.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Design.radiusInput),
          borderSide: const BorderSide(color: Design.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Design.radiusInput),
          borderSide: const BorderSide(
              color: Design.primary, width: Design.inputFocusBorderWidth),
        ),
        hintStyle: const TextStyle(color: Design.textFaint),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: Design.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Design.radiusLg),
        ),
        titleTextStyle: const TextStyle(
          color: Design.text,
          fontSize: Design.fontDialogTitle,
          fontWeight: Design.weightBold,
        ),
        contentTextStyle: const TextStyle(
            color: Design.text, fontSize: Design.fontBody, height: 1.4),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Design.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(Design.radiusSheet)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Design.text,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Design.radiusInput),
        ),
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: Design.textMuted,
        textColor: Design.text,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: Design.surfaceMuted,
        side: const BorderSide(color: Design.border),
        labelStyle: const TextStyle(color: Design.text),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Design.radiusSm),
        ),
      ),
    );
  }
}
