import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/deep_link_generator.dart';
import 'package:meaning_to/edit_share_tasks_screen.dart';
import 'package:meaning_to/dialogs/find_user_dialog.dart';
import 'package:share_plus/share_plus.dart';

/// Lets the owner pick one or more of their own pursuits, then proceed to the
/// shared [ShareActionDialog] to send them. "Share This Pursuit" from Home
/// reaches that same dialog with a single pursuit.
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

  /// One-tap entry point ("Share This Pursuit"): opens the share dialog for a
  /// single pursuit — identical to selecting it here and proceeding.
  static Future<void> shareSingle(
      BuildContext context, Category category) {
    return ShareActionDialog.show(context, [category]);
  }

  @override
  State<ShareAnyPursuitsScreen> createState() => _ShareAnyPursuitsScreenState();
}

class _ShareAnyPursuitsScreenState extends State<ShareAnyPursuitsScreen> {
  final Set<int> _selected = {};

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

  /// Opens the share dialog for the currently-selected pursuits.
  Future<void> _proceed() async {
    final pursuits =
        _ownedPursuits.where((c) => _selected.contains(c.id)).toList();
    if (pursuits.isEmpty) return;
    await ShareActionDialog.show(context, pursuits);
    if (mounted) {
      setState(() => _selected.clear());
      await _loadLinks(); // a Share/Copy may have created a new link
    }
  }

  Future<void> _copyExistingLink(String linkId) async {
    final url = DeepLinkGenerator.generateShareLink(linkId);
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link copied to clipboard')),
        );
      }
    } else {
      await Share.share(url, subject: 'Join my Pursuit on ROUZME!');
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
              'Select the Pursuits you want to share, then tap "Share with..." to '
              'choose how to send them. Recipients get read-only access.',
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
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton.icon(
                onPressed: _selected.isEmpty ? null : _proceed,
                icon: const Icon(Icons.arrow_forward),
                label: Text(_selected.isEmpty
                    ? 'Share'
                    : 'Share ${_selected.length} '
                        'Pursuit${_selected.length == 1 ? '' : 's'}'),
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
      child: InkWell(
        onTap: () => setState(() {
          if (checked) {
            _selected.remove(cat.id);
          } else {
            _selected.add(cat.id);
          }
        }),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 12, 0),
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
            ],
          ),
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
                  onPressed: () => _copyExistingLink(link.linkId),
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

/// Confirmation-and-instructions dialog for sharing one or more pursuits.
/// Lists the pursuits (each with a Tasks editor) and offers the three ways to
/// share them: Share, Copy Link for Sending, or Send To User. Reached from both
/// "Share This Pursuit" (one pursuit) and the Share Any Pursuit(s) Proceed
/// button (the selected set).
class ShareActionDialog extends StatefulWidget {
  final List<Category> pursuits;

  const ShareActionDialog({super.key, required this.pursuits});

  static Future<void> show(BuildContext context, List<Category> pursuits) {
    return showDialog<void>(
      context: context,
      builder: (_) => ShareActionDialog(pursuits: pursuits),
    );
  }

  @override
  State<ShareActionDialog> createState() => _ShareActionDialogState();
}

class _ShareActionDialogState extends State<ShareActionDialog> {
  bool _busy = false;

  List<int> get _ids => widget.pursuits.map((c) => c.id).toList();

  /// Creates a share link for the pursuits, returning its URL (or null on
  /// error, after showing a snackbar via [messenger]).
  Future<String?> _createLink(ScaffoldMessengerState messenger) async {
    try {
      final linkId = await ApiClient.createShareLink(_ids);
      return DeepLinkGenerator.generateShareLink(linkId);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not create link: $e')),
      );
      return null;
    }
  }

  Future<void> _share() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    final url = await _createLink(messenger);
    if (url == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: url));
      messenger.showSnackBar(
        const SnackBar(content: Text('Link copied to clipboard')),
      );
    } else {
      await Share.share(url, subject: 'Join my Pursuit on ROUZME!');
    }
    navigator.pop();
  }

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    final url = await _createLink(messenger);
    if (url == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    messenger.showSnackBar(
      const SnackBar(content: Text('Link copied — paste it into a message to send')),
    );
    navigator.pop();
  }

  Future<void> _sendToUser() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final user = await FindUserDialog.show(context);
    if (user == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final n = await ApiClient.sendShareToUser(_ids, user.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text(n > 0
              ? 'Shared $n Pursuit${n == 1 ? '' : 's'} with ${user.name}'
              : '${user.name} already has those Pursuits'),
        ),
      );
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not send: $e')),
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A share-action button with the icon stacked above its (centred) label, so
  /// the three fit comfortably side by side.
  Widget _actionButton(IconData icon, String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: _busy ? null : onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.pursuits.length;
    return AlertDialog(
      scrollable: true,
      titlePadding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
      title: Row(
        children: [
          Expanded(
            child: Text(n == 1 ? 'Share This Pursuit' : 'Share $n Pursuits'),
          ),
          IconButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recipients get read-only access. Use Tasks to choose which '
              'tasks are shared, then pick how to send:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            ...widget.pursuits.map(_buildPursuitRow),
            const SizedBox(height: 16),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _actionButton(Icons.share, 'Share', _share)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _actionButton(
                          Icons.copy, 'Copy Link\nfor Sending', _copy)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _actionButton(Icons.person_add_alt_1,
                          'Send To\nUser', _sendToUser)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPursuitRow(Category cat) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              cat.headline,
              style:
                  const TextStyle(fontSize: 16.8, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton.icon(
            onPressed: _busy
                ? null
                : () => EditShareTasksScreen.push(context, category: cat),
            icon: const Icon(Icons.edit_outlined, size: 14),
            label: const Text('Tasks', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            ),
          ),
        ],
      ),
    );
  }
}
