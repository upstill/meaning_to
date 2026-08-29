import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:meaning_to/utils/app_buttons.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/deep_link_generator.dart';
import 'package:meaning_to/home_screen.dart' show kDirectSharingEnabled;
import 'package:meaning_to/edit_share_tasks_screen.dart';
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

  List<({String linkId, List<Category> categories, List<String> takers})>
      _links = [];
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
    final shared = await ShareActionDialog.show(context, pursuits);
    if (!mounted) return;
    if (shared == true) {
      Navigator.of(context).pop(); // return to Home once a medium is chosen
    } else {
      setState(() => _selected.clear());
      await _loadLinks();
    }
  }

  /// Re-opens the share dialog for an existing link's pursuits — same flow as
  /// the top "Share…" button (Share / Copy Link for Sending / Send To User).
  Future<void> _inviteAgain(List<Category> pursuits) async {
    final shared = await ShareActionDialog.show(context, pursuits);
    if (!mounted) return;
    if (shared == true) {
      Navigator.of(context).pop(); // return to Home once a medium is chosen
    } else {
      await _loadLinks();
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
              'Select the Pursuits you want to share, then tap "Share..." to '
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

  Widget _buildLinkCard(
      ({String linkId, List<Category> categories, List<String> takers}) link) {
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
            const SizedBox(height: 2),
            link.takers.isEmpty
                ? const Text(
                    'Not yet taken up',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic),
                  )
                : Text(
                    'Taken up by: ${link.takers.join(', ')}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
            Row(
              children: [
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _inviteAgain(link.categories),
                  icon: const Icon(Icons.person_add_alt_1, size: 16),
                  label: const Text('Invite Again',
                      style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  ),
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

  /// Resolves to `true` if the user chose a share medium (Share / Copy / Send),
  /// or `null`/`false` if they just dismissed the dialog.
  static Future<bool?> show(BuildContext context, List<Category> pursuits) {
    return showDialog<bool>(
      context: context,
      builder: (_) => ShareActionDialog(pursuits: pursuits),
    );
  }

  @override
  State<ShareActionDialog> createState() => _ShareActionDialogState();
}

class _ShareActionDialogState extends State<ShareActionDialog> {
  bool _busy = false;
  final _emailController = TextEditingController();

  // People who've allowed the current user to send them Pursuits directly.
  // Usually empty — the search + "Send To User" are hidden unless non-empty.
  final _recipientFilter = TextEditingController();
  List<({String id, String name})> _recipients = [];
  ({String id, String name})? _selectedRecipient;

  @override
  void initState() {
    super.initState();
    if (kDirectSharingEnabled) _loadRecipients();
    _recipientFilter.addListener(() => setState(() {}));
  }

  Future<void> _loadRecipients() async {
    final people = await ApiClient.searchUsers(''); // all my recipients
    if (!mounted) return;
    setState(() => _recipients = people);
  }

  List<({String id, String name})> get _filteredRecipients {
    final q = _recipientFilter.text.trim().toLowerCase();
    if (q.isEmpty) return _recipients;
    return _recipients
        .where((r) => r.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _recipientFilter.dispose();
    super.dispose();
  }

  List<int> get _ids => widget.pursuits.map((c) => c.id).toList();

  /// Emails typed into the optional invite field (comma/space separated). Only
  /// a redeemer whose account email matches one of these is offered a direct-send
  /// channel — the email is a gate, never used to deliver the link.
  List<String> get _inviteEmails => _emailController.text
      .split(RegExp(r'[,\s]+'))
      .map((e) => e.trim().toLowerCase())
      .where((e) => e.contains('@') && e.length >= 3)
      .toSet()
      .toList();

  /// The OS share sheet is only meaningful on mobile. On web/desktop the Share
  /// action falls back to a clipboard copy (same as the Copy button), so we
  /// hide Share there. Check kIsWeb first — in a browser defaultTargetPlatform
  /// still reports the underlying OS.
  bool get _nativeShareAvailable =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Creates a share link for the pursuits, returning its URL (or null on
  /// error, after showing a snackbar via [messenger]).
  Future<String?> _createLink(ScaffoldMessengerState messenger) async {
    try {
      final linkId =
          await ApiClient.createShareLink(_ids, emails: _inviteEmails);
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
      await Share.share(url, subject: 'Join my Pursuit on RouzMe');
    }
    navigator.pop(true);
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
    navigator.pop(true);
  }

  Future<void> _sendToUser() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final user = _selectedRecipient;
    if (user == null) return;
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
      navigator.pop(true);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not send: $e')),
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A share-action button with the icon stacked above its (centred) label, so
  /// the three fit comfortably side by side.
  Widget _actionButton(IconData icon, String label, VoidCallback? onPressed,
      {Color? background, Color? foreground}) {
    // Icon inline with the label; the button sizes to fit its content.
    return ElevatedButton.icon(
      onPressed: _busy ? null : onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
            Text(
              (_nativeShareAvailable
                      ? ''
                      : 'Copy this link and paste it into a message to someone '
                          'you want to share with. ') +
                  'Recipients get read-only access. Hit Tasks below to choose '
                      'which tasks to share.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            ...widget.pursuits.map(_buildPursuitRow),
            const SizedBox(height: 16),
            // In-app direct send — only to people who've allowed you. Hidden
            // entirely (with its button) when you have no such recipients.
            // Also held back overall for now (kDirectSharingEnabled).
            if (kDirectSharingEnabled && _recipients.isNotEmpty) ...[
              const Text('Send directly to:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              if (_recipients.length > 4)
                TextField(
                  controller: _recipientFilter,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    hintText: 'Filter by name…',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in _filteredRecipients)
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: r.id,
                        groupValue: _selectedRecipient?.id,
                        onChanged: _busy
                            ? null
                            : (_) =>
                                setState(() => _selectedRecipient = r),
                        title: Text(r.name),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  style: AppButtons.cancelOutlined(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                // On mobile the native Share sheet already offers copy, so
                // show Share; on web/desktop Share just copies, so show Copy.
                if (_nativeShareAvailable)
                  _actionButton(Icons.share, 'Share', _share)
                else
                  _actionButton(Icons.copy, 'Copy Link', _copy),
                // Send To User only when there's someone to send to.
                if (kDirectSharingEnabled && _recipients.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _actionButton(
                    Icons.person_add,
                    'Send To User',
                    _selectedRecipient == null ? null : _sendToUser,
                  ),
                ],
              ],
            ),
            // OPTIONAL email gate, below the buttons — held back for now
            // (kDirectSharingEnabled). Only someone whose account email matches
            // can later accept direct shares from you.
            if (kDirectSharingEnabled) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                minLines: 1,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText:
                      'OPTIONAL: include their email here for greater security',
                  hintText: 'friend@example.com',
                  helperMaxLines: 3,
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
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
