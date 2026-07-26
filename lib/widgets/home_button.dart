import 'package:flutter/material.dart';

/// A Home button for AppBar leading slots. Navigates all the way back
/// to the home screen. Optionally runs [onBeforeNavigate] first (e.g. to
/// autosave); if the callback returns false the navigation is cancelled.
class HomeButton extends StatelessWidget {
  /// Optional async callback invoked before navigating home.
  /// Return `true` to proceed, `false` to cancel navigation.
  final Future<bool> Function()? onBeforeNavigate;

  /// Explicit icon color. Needed on some light M3 AppBars where the inherited
  /// foreground color doesn't reach the icon on web (renders invisible).
  final Color? color;

  const HomeButton({super.key, this.onBeforeNavigate, this.color});

  Future<void> _goHome(BuildContext context) async {
    if (onBeforeNavigate != null) {
      final proceed = await onBeforeNavigate!();
      if (!proceed) return;
    }
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      // Color set on the Icon itself so it always wins over the AppBar's
      // IconTheme / IconButtonTheme (which can leave it invisible on web M3).
      icon: Icon(Icons.home, color: color),
      color: color,
      tooltip: 'Home',
      onPressed: () => _goHome(context),
    );
  }
}
