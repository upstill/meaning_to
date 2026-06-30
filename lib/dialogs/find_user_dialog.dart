import 'dart:async';
import 'package:flutter/material.dart';
import 'package:meaning_to/utils/api_client.dart';

/// Searches users by name or email and lets the caller pick one. Returns the
/// chosen user as `({String id, String name})`, or null if cancelled.
///
/// Results show NAMES only — a full email you already know will find the
/// person, but partial matches never reveal anyone's email.
class FindUserDialog extends StatefulWidget {
  const FindUserDialog({super.key});

  static Future<({String id, String name})?> show(BuildContext context) {
    return showDialog<({String id, String name})>(
      context: context,
      builder: (_) => const FindUserDialog(),
    );
  }

  @override
  State<FindUserDialog> createState() => _FindUserDialogState();
}

class _FindUserDialogState extends State<FindUserDialog> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<({String id, String name})> _results = [];
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _query = value;
    if (value.trim().length < 2) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(value));
  }

  Future<void> _search(String value) async {
    final results = await ApiClient.searchUsers(value);
    if (!mounted || value != _query) return; // stale
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send To User'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                hintText: 'Search by name or email…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(height: 240, child: _buildResults()),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildResults() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_query.trim().length < 2) {
      return const Center(
        child: Text(
          'Type at least two letters of a name,\nor a full email address.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    if (_results.isEmpty) {
      return const Center(
        child: Text('No matching users.',
            style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final user = _results[i];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.person_outline),
          title: Text(user.name),
          onTap: () => Navigator.of(context).pop(user),
        );
      },
    );
  }
}
