import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/share_invitation.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/utils/deep_link_generator.dart';
import 'package:meaning_to/snag_pursuit_screen.dart';
import 'package:meaning_to/edit_share_tasks_screen.dart';
import 'package:share_plus/share_plus.dart';

class MySharesScreen extends StatefulWidget {
  final List<Category> allCategories;
  final void Function(Category) onSelect;
  final VoidCallback? onRefresh;

  const MySharesScreen({
    super.key,
    required this.allCategories,
    required this.onSelect,
    this.onRefresh,
  });

  static Future<void> show(
    BuildContext context,
    List<Category> allCategories,
    void Function(Category) onSelect, {
    VoidCallback? onRefresh,
  }) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => MySharesScreen(
          allCategories: allCategories,
          onSelect: onSelect,
          onRefresh: onRefresh,
        ),
      ),
    );
  }

  @override
  State<MySharesScreen> createState() => _MySharesScreenState();
}

class _MySharesScreenState extends State<MySharesScreen> {
  List<Map<String, dynamic>>? _sharedOutSummary;
  bool _loading = true;
  late List<Category> _sharedWithMe;
  final Set<int> _expandedInvitations = {};

  @override
  void initState() {
    super.initState();
    _sharedWithMe = widget.allCategories.where((c) => c.isShared).toList();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final summary = await ApiClient.getSharedOutSummary();
      if (mounted) {
        setState(() {
          _sharedOutSummary = summary;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleAvailable(Category category, bool value) async {
    setState(() => category.isAvailable = value);
    try {
      await ApiClient.setSharedCategoryAvailable(category.id, value);
      widget.onRefresh?.call();
    } catch (e) {
      if (mounted) {
        setState(() => category.isAvailable = !value); // revert
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update: $e')),
        );
      }
    }
  }

  Future<void> _deleteSubscription(Category category) async {
    try {
      await ApiClient.releaseSharedCategory(category.id);
      if (mounted) {
        setState(() => _sharedWithMe.remove(category));
        widget.onRefresh?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove share: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Shares')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSharedWithMeSection(),
                  const SizedBox(height: 24),
                  _buildSharingOutSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.black54,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSharingOutSection() {
    final summary = _sharedOutSummary ?? [];

    final rows = summary
        .map((s) {
          final catId = s['category_id'] as int;
          try {
            return widget.allCategories
                .firstWhere((c) => c.id == catId && !c.isShared);
          } catch (_) {
            return null;
          }
        })
        .whereType<Category>()
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('SHARING OUT'),
        if (rows.isEmpty)
          const Text(
            'You are not sharing any pursuits.',
            style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
          )
        else
          ...rows.map((cat) => _ShareCategoryCard(category: cat)),
      ],
    );
  }

  Widget _buildSharedWithMeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('SHARED WITH ME'),
        if (_sharedWithMe.isEmpty)
          const Text(
            'No pursuits have been shared with you.',
            style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
          )
        else
          ..._sharedWithMe.map((c) => _buildSharedWithMeRow(c)),
      ],
    );
  }

  Widget _buildSharedWithMeRow(Category category) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    category.headline,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      if (!category.isAvailable) {
                        await _toggleAvailable(category, true);
                      }
                      if (mounted) {
                        widget.onSelect(category);
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.arrow_forward),
                    tooltip: 'Adopt & Go to Pursuit',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              if (category.ownerName != null)
                Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    children: [
                      const TextSpan(text: 'from '),
                      TextSpan(
                        text: category.ownerName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              if (category.invitation != null && category.invitation!.isNotEmpty)
                Builder(builder: (context) {
                  const limit = 100;
                  final full = category.invitation!;
                  final expanded = _expandedInvitations.contains(category.id);
                  final needsTrunc = full.length > limit;
                  final shown = (needsTrunc && !expanded)
                      ? full.substring(0, limit).trimRight()
                      : full;
                  return Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                      children: [
                        TextSpan(text: shown),
                        if (needsTrunc && !expanded)
                          WidgetSpan(
                            child: GestureDetector(
                              onTap: () => setState(
                                  () => _expandedInvitations.add(category.id)),
                              child: const Text(
                                ' (more)',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.blue,
                                  fontStyle: FontStyle.normal,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              Row(
                children: [
                  Checkbox(
                    value: category.isAvailable,
                    onChanged: (v) => _toggleAvailable(category, v ?? true),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  Text('Include in my list of ${NamingUtils.categoriesName(capitalize: true, plural: true)}', style: const TextStyle(fontSize: 12)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _deleteSubscription(category),
                    icon: const Icon(Icons.delete_outline,
                        size: 14, color: Colors.red),
                    label: const Text('Forget',
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
      ),
    );
  }
}

class _ShareCategoryCard extends StatefulWidget {
  final Category category;

  const _ShareCategoryCard({required this.category});

  @override
  State<_ShareCategoryCard> createState() => _ShareCategoryCardState();
}

class _ShareCategoryCardState extends State<_ShareCategoryCard> {
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
      await Share.share(link, subject: 'Join my Pursuit on ROUZME!');
    }
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final token =
          await ApiClient.createShareInvitation(widget.category.id);
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.category.headline,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => EditShareTasksScreen.push(
                        context, category: widget.category),
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: const Text('Select Tasks to Share',
                        style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                    ),
                  ),
                ],
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (_invitation == null) ...[
                  const Text(
                    'Create a link to share this Pursuit. '
                    'Recipients get read-only access.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 4),
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _create,
                        icon: _busy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.add_link, size: 16),
                        label: const Text('Create Link'),
                      ),
                    ),
                  ),
                ] else
                  _buildLinkCard(_invitation!),
              ],
            ],
          ),
        ),
      ),
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

    return Column(
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
                  style:
                      const TextStyle(fontSize: 11, color: Colors.white)),
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
                label: const Text('Renew', style: TextStyle(fontSize: 12)),
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
    );
  }
}
