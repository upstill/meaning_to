import 'package:flutter/material.dart';

/// A Home button for AppBar leading slots. Navigates all the way back
/// to the home screen. Optionally runs [onBeforeNavigate] first (e.g. to
/// autosave); if the callback returns false the navigation is cancelled.
class HomeButton extends StatelessWidget {
  /// Optional async callback invoked before navigating home.
  /// Return `true` to proceed, `false` to cancel navigation.
  final Future<bool> Function()? onBeforeNavigate;

  const HomeButton({super.key, this.onBeforeNavigate});

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
      icon: const Icon(Icons.home),
      tooltip: 'Home',
      onPressed: () => _goHome(context),
    );
  }
}
