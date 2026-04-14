import 'package:flutter/material.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shows a one-time popup explaining the rules of borrowed pursuits.
/// Safe to call on every borrow action — it tracks whether the user has
/// already seen the explanation and skips it after the first time.
Future<void> showBorrowExplanationIfNeeded(BuildContext context) async {
  final userId = AuthUtils.getCurrentUserId();
  if (userId == null) return;

  final prefs = await SharedPreferences.getInstance();
  final key = 'borrow_explained_$userId';
  if (prefs.getBool(key) ?? false) return;

  await prefs.setBool(key, true);

  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
          'Borrowed ${NamingUtils.categoriesName(plural: false, capitalize: true)}'),
      content: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 15, color: Colors.black),
          children: [
            TextSpan(
                text:
                    'When you borrow a ${NamingUtils.categoriesName(plural: false, capitalize: true)} you can read it, but not add or edit anything.'),
            const TextSpan(
                text:
                    "\n\nIf you'd like your own copy to work with, tap the Copy button next to the person's name (or the "),
            const TextSpan(
              text: 'Snag this Pursuit',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const TextSpan(text: " in the Menu)."),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Got It'),
        ),
      ],
    ),
  );
}
