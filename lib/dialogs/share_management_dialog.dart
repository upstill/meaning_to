import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/share_invitation.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/deep_link_generator.dart';

class ShareManagementDialog extends StatefulWidget {
  final Category category;

  const ShareManagementDialog({super.key, required this.category});

  static Future<void> show(BuildContext context, Category category) {
    return showDialog<void>(
      context: context,
      builder: (_) => ShareManagementDialog(category: category),
    );
  }

  @override
  State<ShareManagementDialog> createState() => _ShareManagementDialogState();
}

class _ShareManagementDialogState extends State<ShareManagementDialog> {
  List<ShareInvitation>? _invitations;
  bool _loading = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final invitations =
          await ApiClient.getShareInvitations(widget.category.id);
      if (mounted) {
        setState(() {
          _invitations = invitations;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createNew() async {
    setState(() => _creating = true);
    try {
      final token = await ApiClient.createShareInvitation(widget.category.id);
      final link = DeepLinkGenerator.generateInviteLink(token);
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New invite link copied to clipboard')),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create link: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _renew(ShareInvitation inv) async {
    try {
      await ApiClient.renewShareInvitation(inv.id);
      final link = DeepLinkGenerator.generateInviteLink(inv.id);
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link renewed and copied to clipboard')),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not renew: $e')),
        );
      }
    }
  }

  Future<void> _delete(ShareInvitation inv) async {
    try {
      await ApiClient.deleteShareInvitation(inv.id);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e')),
        );
      }
    }
  }

  void _copyLink(ShareInvitation inv) {
    final link = DeepLinkGenerator.generateInviteLink(inv.id);
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite link copied to clipboard')),
    );
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final now = DateTime.now();
    if (dt.year == now.year) return '${months[dt.month - 1]} ${dt.day}';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Widget _buildStatusChip(ShareInvitation inv) {
    final (label, color) = inv.isUsed
        ? ('Used', Colors.grey)
        : inv.isExpired
            ? ('Expired', Colors.red)
            : ('Active', Colors.green);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
    );
  }

  Widget _buildRow(ShareInvitation inv) {
    final String expiryText;
    final Color expiryColor;

    if (inv.expiresAt == null) {
      expiryText = 'No expiry';
      expiryColor = Colors.grey;
    } else if (inv.isExpired) {
      expiryText = 'Expired ${_formatDate(inv.expiresAt!)}';
      expiryColor = Colors.red;
    } else {
      expiryText = 'Expires ${_formatDate(inv.expiresAt!)}';
      expiryColor = Colors.green[700]!;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildStatusChip(inv),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    expiryText,
                    style: TextStyle(fontSize: 12, color: expiryColor),
                  ),
                ),
                Text(
                  'Created ${_formatDate(inv.createdAt)}',
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (inv.isActive)
                  TextButton.icon(
                    onPressed: () => _copyLink(inv),
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('Copy Link',
                        style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                    ),
                  ),
                if (!inv.isActive)
                  TextButton.icon(
                    onPressed: () => _renew(inv),
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Renew',
                        style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => _delete(inv),
                  icon: const Icon(Icons.delete_outline,
                      size: 14, color: Colors.red),
                  label: const Text('Delete',
                      style: TextStyle(fontSize: 12, color: Colors.red)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final invitations = _invitations;
    return AlertDialog(
      title: Text('Share "${widget.category.headline}"'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Each link can be used once and expires in 7 days. '
              'Recipients get read-only access to this Pursuit.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (invitations == null || invitations.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No share links yet.',
                  style: TextStyle(
                      color: Colors.grey, fontStyle: FontStyle.italic),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: invitations.length,
                  itemBuilder: (_, i) => _buildRow(invitations[i]),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        ElevatedButton.icon(
          onPressed: _creating ? null : _createNew,
          icon: _creating
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_link, size: 16),
          label: const Text('New Link'),
        ),
      ],
    );
  }
}
