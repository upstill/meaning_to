import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/deep_link_generator.dart';
import 'package:meaning_to/edit_share_tasks_screen.dart';
import 'package:meaning_to/dialogs/find_user_dialog.dart';
import 'package:share_plus/share_plus.dart';

/// Lets the owner pick one or more of their own pursuits and issue a single
/// reusable link that grants the whole set. Replaces the old per-category
/// "Share This Pursuit" dialog and the open-to-all / single-use machinery.
class ShareAnyPursuitsScreen extends StatefulWidget {
  final List<Category> allCategories;

  const ShareAnyPursuitsScreen({super.key, required this.allCategories});

  static Future<void> show(
      BuildContext context, List<Category> allCategories) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ShareAnyPursuitsScreen(allCategories: allCategories),
      ),
    );
  }

  /// One-tap entry point ("Share This Pursuit"): issues a reusable link for a
  /// single pursuit and shows the result, identical to selecting it here.
  static Future<void> shareSingle(
      BuildContext context, Category category) async {
    try {
      final linkId = await ApiClient.createShareLink([category.id]);
      final url = DeepLinkGenerator.generateShareLink(linkId);
      if (context.mounted) {
        await showShareLinkResult(context, url, category: category);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create link: $e')),
        );
      }
    }
  }

  @override
  State<ShareAnyPursuitsScreen> createState() => _ShareAnyPursuitsScreenState();
}

class _ShareAnyPursuitsScreenState extends State<ShareAnyPursuitsScreen> {
  final Set<int> _selected = {};
  bool _issuing = false;

  List<({String linkId, List<Category> categories})> _links = [];
  bool _loadingLinks = true;

  /// The owner's own pursuits (shared-in ones can't be re-shared).
  late final List<Category> _ownedPursuits =
      widget.allCategories.where((c) => !c.isShared).toList();

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  Future<void> _loadLinks() async {
    setState(() => _loadingLinks = true);
    final links = await ApiClient.getMyShareLinks();
    if (mounted) {
      setState(() {
        _links = links;
        _loadingLinks = false;
      });
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

  /// Creates a share link for the selected pursuits and returns its URL, or
  /// null on error (after showing a snackbar). Refreshes the link list.
  Future<String?> _createLinkForSelected() async {
    try {
      final linkId = await ApiClient.createShareLink(_selected.toList());
      if (mounted) await _loadLinks();
      return DeepLinkGenerator.generateShareLink(linkId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create link: $e')),
        );
      }
      return null;
    }
  }

  /// Share the link to the selected pursuits via another app (native) / copy (web).
  Future<void> _shareSelected() async {
    if (_selected.isEmpty) return;
    setState(() => _issuing = true);
    final url = await _createLinkForSelected();
    if (url != null) {
      await _shareLink(url);
      if (mounted) setState(() => _selected.clear());
    }
    if (mounted) setState(() => _issuing = false);
  }

  /// Copy the link to the selected pursuits to the clipboard.
  Future<void> _copySelected() async {
    if (_selected.isEmpty) return;
    setState(() => _issuing = true);
    final url = await _createLinkForSelected();
    if (url != null) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Link copied — paste it into a message to send')),
        );
        setState(() => _selected.clear());
      }
    }
    if (mounted) setState(() => _issuing = false);
  }

  /// Find a user and grant them the selected pursuits directly, in-app.
  Future<void> _sendToUser() async {
    if (_selected.isEmpty) return;
    final user = await FindUserDialog.show(context);
    if (user == null || !mounted) return;
    setState(() => _issuing = true);
    try {
      final n = await ApiClient.sendShareToUser(_selected.toList(), user.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(n > 0
                ? 'Shared $n Pursuit${n == 1 ? '' : 's'} with ${user.name}'
                : '${user.name} already has those Pursuits'),
          ),
        );
        setState(() => _selected.clear());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _issuing = false);
    }
  }

  Future<void> _deleteLink(String linkId) async {
    try {
      await ApiClient.deleteShareLink(linkId);
      if (mounted) {
        setState(() => _links.removeWhere((l) => l.linkId == linkId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete link: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Share Any Pursuit(s)')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select the Pursuits you want to share, then issue one link to '
              'send by email. Anyone who opens it gets read-only access to those '
              'Pursuits.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            if (_ownedPursuits.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'You have no Pursuits of your own to share.',
                  style:
                      TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                ),
              )
            else
              ..._ownedPursuits.map(_buildPursuitRow),
            const SizedBox(height: 12),
            Center(
              child: Text(
                _selected.isEmpty
                    ? 'Select Pursuit(s) above, then choose how to share:'
                    : '${_selected.length} '
                        'Pursuit${_selected.length == 1 ? '' : 's'} selected — '
                        'share by:',
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: (_selected.isEmpty || _issuing)
                        ? null
                        : _shareSelected,
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Share'),
                  ),
                  ElevatedButton.icon(
                    onPressed: (_selected.isEmpty || _issuing)
                        ? null
                        : _copySelected,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy Link for Sending'),
                  ),
                  ElevatedButton.icon(
                    onPressed: (_selected.isEmpty || _issuing)
                        ? null
                        : _sendToUser,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Send To User'),
                  ),
                ],
              ),
            ),
            const Divider(height: 32),
            _buildExistingLinks(),
          ],
        ),
      ),
    );
  }

  Widget _buildPursuitRow(Category cat) {
    final checked = _selected.contains(cat.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              onChanged: (v) => setState(() {
                if (v ?? false) {
                  _selected.add(cat.id);
                } else {
                  _selected.remove(cat.id);
                }
              }),
            ),
            Expanded(
              child: Text(
                cat.headline,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            TextButton.icon(
              onPressed: () =>
                  EditShareTasksScreen.push(context, category: cat),
              icon: const Icon(Icons.edit_outlined, size: 14),
              label: const Text('Tasks', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExistingLinks() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'YOUR SHARE LINKS',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.black54,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        if (_loadingLinks)
          const Center(child: CircularProgressIndicator())
        else if (_links.isEmpty)
          const Text(
            'You haven\'t issued any share links yet.',
            style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
          )
        else
          ..._links.map(_buildLinkCard),
      ],
    );
  }

  Widget _buildLinkCard(({String linkId, List<Category> categories}) link) {
    final names = link.categories.map((c) => c.headline).join(', ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              names.isEmpty ? '(no pursuits)' : names,
              style: const TextStyle(fontSize: 14),
            ),
            Row(
              children: [
                const Spacer(),
                IconButton(
                  onPressed: () => _shareLink(
                      DeepLinkGenerator.generateShareLink(link.linkId)),
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy Link',
                  visualDensity: VisualDensity.compact,
                ),
                TextButton.icon(
                  onPressed: () => _deleteLink(link.linkId),
                  icon: const Icon(Icons.delete_outline,
                      size: 14, color: Colors.red),
                  label: const Text('Delete',
                      style: TextStyle(fontSize: 12, color: Colors.red)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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

/// Shows an issued share link with copy / share actions. When [category] is
/// given (the single-pursuit "Share This Pursuit" shortcut), the first
/// paragraph also offers a link to choose which tasks are shared.
Future<void> showShareLinkResult(BuildContext context, String url,
    {Category? category}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Share Link Ready'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Send this link by email. Anyone who opens it gets '
                      'read-only access to the selected Pursuit(s). ',
                ),
                if (category != null)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: GestureDetector(
                      onTap: () => EditShareTasksScreen.push(ctx,
                          category: category),
                      child: const Text(
                        '(If you want to select which tasks to share, '
                        'click here)',
                        style: TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(url,
                    style: const TextStyle(fontSize: 13)),
              ),
              IconButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Link copied to clipboard')),
                    );
                  }
                },
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy Link',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (!kIsWeb)
          TextButton.icon(
            onPressed: () =>
                Share.share(url, subject: 'Join my Pursuit on ROUZME!'),
            icon: const Icon(Icons.ios_share, size: 16),
            label: const Text('Share'),
          ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
