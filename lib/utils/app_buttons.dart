import 'package:flutter/material.dart';

class AppButtons {
  // Shared palette
  static const Color finalizeBg = Colors.green;
  static const Color finalizeFg = Colors.white;
  static const Color goForthBg = Colors.blue;
  static const Color goForthFg = Colors.white;
  static const Color cancelBg = Colors.grey;
  static const Color cancelFg = Colors.white;

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

  static ButtonStyle cancel() {
    return ElevatedButton.styleFrom(
      backgroundColor: cancelBg,
      foregroundColor: cancelFg,
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

  static ButtonStyle cancelOutlined() {
    return OutlinedButton.styleFrom(
      foregroundColor: cancelBg,
      side: const BorderSide(color: cancelBg),
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

  static ButtonStyle iconCancel() {
    return IconButton.styleFrom(
      backgroundColor: cancelBg.withOpacity(0.08),
      foregroundColor: cancelBg,
    );
  }
}
