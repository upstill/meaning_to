import 'package:flutter/material.dart';

class AppButtons {
  // Shared palette
  static const Color finalizeBg = Colors.green;
  static const Color finalizeFg = Colors.white;
  static const Color goForthBg = Colors.blue;
  static const Color goForthFg = Colors.white;

  // Elevated buttons
  static ButtonStyle finalize() {
    return ElevatedButton.styleFrom(
      backgroundColor: finalizeBg,
      foregroundColor: finalizeFg,
    );
  }

  static ButtonStyle goForth() {
    return ElevatedButton.styleFrom(
      backgroundColor: goForthBg,
      foregroundColor: goForthFg,
    );
  }

  // Outlined buttons
  static ButtonStyle finalizeOutlined() {
    return OutlinedButton.styleFrom(
      foregroundColor: finalizeBg,
      side: const BorderSide(color: finalizeBg),
    );
  }

  static ButtonStyle goForthOutlined() {
    return OutlinedButton.styleFrom(
      foregroundColor: goForthBg,
      side: const BorderSide(color: goForthBg),
    );
  }

  // Icon buttons (optional helpers)
  static ButtonStyle iconGoForth() {
    return IconButton.styleFrom(
      backgroundColor: goForthBg.withOpacity(0.08),
      foregroundColor: goForthBg,
    );
  }

  static ButtonStyle iconFinalize() {
    return IconButton.styleFrom(
      backgroundColor: finalizeBg.withOpacity(0.08),
      foregroundColor: finalizeBg,
    );
  }
}
