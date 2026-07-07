import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows a persistent error popup (instead of a disappearing snackbar) with a
/// Copy button so the user can grab the full message. Selectable text as well.
Future<void> showErrorDialog(
  BuildContext context,
  String message, {
  String title = 'Something went wrong',
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      var copied = false;
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: SelectableText(
              message,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          actions: [
            TextButton.icon(
              icon: Icon(copied ? Icons.check : Icons.copy, size: 18),
              label: Text(copied ? 'Copied' : 'Copy'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: message));
                setState(() => copied = true);
              },
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    },
  );
}
