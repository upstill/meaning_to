import 'package:flutter/material.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/naming.dart';

/// Lists the people the current user has allowed to send them Pursuits directly,
/// with a Remove (unfriend) action that blocks their future direct sends.
class AllowedSendersDialog extends StatefulWidget {
  const AllowedSendersDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const AllowedSendersDialog(),
    );
  }

  @override
  State<AllowedSendersDialog> createState() => _AllowedSendersDialogState();
}

class _AllowedSendersDialogState extends State<AllowedSendersDialog> {
  List<({String id, String name})> _senders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final senders = await ApiClient.listAllowedSenders();
    if (!mounted) return;
    setState(() {
      _senders = senders;
      _loading = false;
    });
  }

  Future<void> _revoke(({String id, String name}) sender) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${sender.name}?'),
        content: Text(
            '${sender.name} will no longer be able to send you '
            '${NamingUtils.categoriesName(plural: true)} directly.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ApiClient.revokeAllowedSender(sender.id);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final pursuits = NamingUtils.categoriesName(plural: true);
    return AlertDialog(
      title: const Text('Who can send me things'),
      content: SizedBox(
        width: 360,
        child: _loading
            ? const SizedBox(
                height: 120, child: Center(child: CircularProgressIndicator()))
            : _senders.isEmpty
                ? SizedBox(
                    height: 120,
                    child: Center(
                      child: Text(
                        'No one can send you $pursuits directly.\n\n'
                        'When you invite someone by email while sharing and they '
                        'accept, they\'ll appear here.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final s in _senders)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.person_outline),
                          title: Text(s.name),
                          trailing: IconButton(
                            icon: const Icon(Icons.block, color: Colors.red),
                            tooltip: 'Remove',
                            onPressed: () => _revoke(s),
                          ),
                        ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
