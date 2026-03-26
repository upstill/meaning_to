import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/share_invitation.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/deep_link_generator.dart';
import 'package:share_plus/share_plus.dart';

class SharePursuitDialog extends StatefulWidget {
  final Category category;

  const SharePursuitDialog({super.key, required this.category});

  static Future<void> show(BuildContext context, Category category) {
    return showDialog<void>(
      context: context,
      builder: (_) => SharePursuitDialog(category: category),
    );
  }

  @override
  State<SharePursuitDialog> createState() => _SharePursuitDialogState();
}

class _SharePursuitDialogState extends State<SharePursuitDialog> {
  ShareInvitation? _invitation;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await ApiClient.getShareInvitations(widget.category.id);
      if (mounted) {
        setState(() {
          _invitation = rows.isNotEmpty ? rows.first : null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _shareLink(String link) async {
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link copied to clipboard')),
        );
      }
    } else {
      await Share.share(link, subject: 'Join my Pursuit on ROUZ');
    }
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final token = await ApiClient.createShareInvitation(widget.category.id);
      final link = DeepLinkGenerator.generateInviteLink(token);
      await _shareLink(link);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create link: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renew() async {
    final inv = _invitation;
    if (inv == null) return;
    setState(() => _busy = true);
    try {
      await ApiClient.renewShareInvitation(inv.id);
      final link = DeepLinkGenerator.generateInviteLink(inv.id);
      await _shareLink(link);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not renew: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final inv = _invitation;
    if (inv == null) return;
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

  Future<void> _copyLink() async {
    final inv = _invitation;
    if (inv == null) return;
    await _shareLink(DeepLinkGenerator.generateInviteLink(inv.id));
  }

  Future<void> _setOpenToAll(bool openToAll) async {
    final inv = _invitation;
    if (inv == null) return;
    try {
      await ApiClient.setInvitationOpenToAll(inv.id, openToAll);
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update: $e')),
        );
      }
    }
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final now = DateTime.now();
    if (dt.year == now.year) return '${months[dt.month - 1]} ${dt.day}';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final inv = _invitation;
    return AlertDialog(
      title: Text(
        widget.category.headline,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    inv == null
                        ? 'Create a link to share this Pursuit. '
                            'Recipients get read-only access.'
                        : 'Single-use links expire in 7 days. '
                            'Check "Open To All" for a permanent, reusable link.',
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (inv != null) ...[
                    const SizedBox(height: 12),
                    _buildLinkCard(inv),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (!_loading && inv == null)
          ElevatedButton.icon(
            onPressed: _busy ? null : _create,
            icon: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_link, size: 16),
            label: const Text('Create Link'),
          ),
      ],
    );
  }

  Widget _buildLinkCard(ShareInvitation inv) {
    final String statusLabel;
    final Color statusColor;
    final String expiryText;
    final Color expiryColor;

    if (inv.openToAll) {
      statusLabel = 'Open';
      statusColor = Colors.green;
      expiryText = 'Permanent';
      expiryColor = Colors.green[700]!;
    } else if (inv.isUsed) {
      statusLabel = 'Used';
      statusColor = Colors.grey;
      expiryText = 'Used ${_formatDate(inv.usedAt!)}';
      expiryColor = Colors.grey;
    } else if (inv.isExpired) {
      statusLabel = 'Expired';
      statusColor = Colors.red;
      expiryText = 'Expired ${_formatDate(inv.expiresAt!)}';
      expiryColor = Colors.red;
    } else {
      statusLabel = 'Active';
      statusColor = Colors.green;
      expiryText = inv.expiresAt != null
          ? 'Expires ${_formatDate(inv.expiresAt!)}'
          : 'No expiry';
      expiryColor = Colors.green[700]!;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(statusLabel,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                Text(expiryText,
                    style: TextStyle(fontSize: 12, color: expiryColor)),
              ],
            ),
            Row(
              children: [
                Checkbox(
                  value: inv.openToAll,
                  onChanged: _busy ? null : (v) => _setOpenToAll(v ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                const Text('Open To All', style: TextStyle(fontSize: 12)),
                const Spacer(),
                if (inv.isActive)
                  IconButton(
                    onPressed: _busy ? null : _copyLink,
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy Link',
                    visualDensity: VisualDensity.compact,
                  )
                else
                  TextButton.icon(
                    onPressed: _busy ? null : _renew,
                    icon: const Icon(Icons.refresh, size: 14),
                    label:
                        const Text('Renew', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                    ),
                  ),
                TextButton.icon(
                  onPressed: _busy ? null : _delete,
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
}
