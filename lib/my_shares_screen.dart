import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/borrow_explanation.dart';

/// Lists the pursuits other people have shared with the current user and lets
/// them choose which to borrow onto their home list. Selection is batched:
/// each pursuit has a checkbox (pre-checked if currently borrowed), and tapping
/// Okay makes the borrowed set exactly the checked set. Newly received shares
/// (seen_at IS NULL) are highlighted; opening this screen marks them seen.
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
  bool _loading = true;
  bool _saving = false;
  late List<Category> _sharedWithMe;
  final Set<int> _expandedInvitations = {};

  /// Category ids that were unseen when this screen opened — highlighted here.
  Set<int> _newIds = {};

  /// Currently-checked pursuits (initialised to those already borrowed).
  final Set<int> _selected = {};

  /// Per-category task preview state (expanded set, fetched tasks, in-flight).
  final Set<int> _previewExpanded = {};
  final Map<int, List<Task>> _previewTasks = {};
  final Set<int> _previewLoading = {};

  /// Sharer names whose group is expanded (empty = all collapsed by default).
  final Set<String> _expandedOwners = {};

  @override
  void initState() {
    super.initState();
    _sharedWithMe = widget.allCategories.where((c) => c.isShared).toList();
    _resetSelection();
    _load();
  }

  void _resetSelection() {
    _selected
      ..clear()
      ..addAll(_sharedWithMe.where((c) => c.isAvailable).map((c) => c.id));
  }

  /// When only one user has shared anything, expand their group by default.
  void _expandSoleOwner() {
    final owners = _sharedWithMe.map((c) => c.ownerName ?? 'Someone').toSet();
    if (owners.length == 1) _expandedOwners.add(owners.first);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiClient.getAllSharedWithMe(),
        ApiClient.getUnseenShares(),
      ]);
      if (mounted) {
        setState(() {
          _sharedWithMe = results[0];
          _newIds = results[1].map((c) => c.id).toSet();
          _resetSelection();
          _expandSoleOwner();
          _loading = false;
        });
      }
      // Now that the recipient is viewing them, clear the "new" flag.
      if (_newIds.isNotEmpty) {
        await ApiClient.markSharesSeen();
        widget.onRefresh?.call();
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Commit the selection: borrow exactly the checked pursuits.
  Future<void> _onOkay() async {
    final addingBorrow =
        _sharedWithMe.any((c) => _selected.contains(c.id) && !c.isAvailable);
    setState(() => _saving = true);
    if (addingBorrow && mounted) await showBorrowExplanationIfNeeded(context);
    try {
      for (final c in _sharedWithMe) {
        final desired = _selected.contains(c.id);
        if (desired != c.isAvailable) {
          await ApiClient.setSharedCategoryAvailable(c.id, desired);
          c.isAvailable = desired;
        }
      }
      widget.onRefresh?.call();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }

  /// null = some (tristate dash), true = all, false = none.
  bool? get _selectAllValue {
    if (_sharedWithMe.isEmpty || _selected.isEmpty) return false;
    if (_selected.length == _sharedWithMe.length) return true;
    return null;
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selected.length == _sharedWithMe.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_sharedWithMe.map((c) => c.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shared With Me')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sharedWithMe.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No pursuits have been shared with you.',
                      style: TextStyle(
                          color: Colors.grey, fontStyle: FontStyle.italic),
                    ),
                  ),
                )
              : Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Select Pursuits to borrow, then tap Okay.',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                    CheckboxListTile(
                      value: _selectAllValue,
                      tristate: true,
                      onChanged: (_) => _toggleSelectAll(),
                      controlAffinity: ListTileControlAffinity.trailing,
                      dense: true,
                      title: const Text('Select All / None',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        children: _buildOwnerGroups(),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: OutlinedButton(
                                  onPressed: _saving
                                      ? null
                                      : () => Navigator.of(context).pop(),
                                  child: const Text('Cancel',
                                      style: TextStyle(fontSize: 18)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: _saving ? null : _onOkay,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green[700],
                                    foregroundColor: Colors.white,
                                  ),
                                  child: _saving
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white),
                                        )
                                      : const Text('Okay',
                                          style: TextStyle(fontSize: 18)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  /// Toggles the inline task preview for [category], lazily loading its shared
  /// tasks the first time it's opened.
  Future<void> _togglePreview(Category category) async {
    final id = category.id;
    if (_previewExpanded.contains(id)) {
      setState(() => _previewExpanded.remove(id));
      return;
    }
    setState(() => _previewExpanded.add(id));
    if (_previewTasks.containsKey(id)) return;
    setState(() => _previewLoading.add(id));
    try {
      final tasks = await ApiClient.getTasksByCategory(id);
      final shared = tasks.where((t) => t.shared).toList();
      if (mounted) setState(() => _previewTasks[id] = shared);
    } catch (_) {
      if (mounted) setState(() => _previewTasks[id] = []);
    } finally {
      if (mounted) setState(() => _previewLoading.remove(id));
    }
  }

  /// A tappable up/down arrow that opens the task preview.
  Widget _previewArrowWidget(Category category) {
    return GestureDetector(
      onTap: () => _togglePreview(category),
      child: Icon(
        _previewExpanded.contains(category.id)
            ? Icons.arrow_drop_up
            : Icons.arrow_drop_down,
        color: Colors.blue,
        size: 24,
      ),
    );
  }

  /// The preview arrow as an inline span, to sit at the end of the invitation.
  InlineSpan _previewArrowSpan(Category category) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: _previewArrowWidget(category),
    );
  }

  Widget _buildPreviewTasks(Category category) {
    if (_previewLoading.contains(category.id)) {
      return const Padding(
        padding: EdgeInsets.only(top: 6, left: 8),
        child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final tasks = _previewTasks[category.id] ?? [];
    if (tasks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 6, left: 8, bottom: 4),
        child: Text('No shared tasks.',
            style: TextStyle(
                fontSize: 13, color: Colors.grey, fontStyle: FontStyle.italic)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final t in tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('•  ${t.headline}',
                  style: const TextStyle(fontSize: 14)),
            ),
        ],
      ),
    );
  }

  /// Groups the shared pursuits by the user who shared them, each under an
  /// expandable header.
  List<Widget> _buildOwnerGroups() {
    final byOwner = <String, List<Category>>{};
    for (final c in _sharedWithMe) {
      byOwner.putIfAbsent(c.ownerName ?? 'Someone', () => []).add(c);
    }
    final owners = byOwner.keys.toList()..sort();
    return [for (final o in owners) _buildOwnerGroup(o, byOwner[o]!)];
  }

  Widget _buildOwnerGroup(String owner, List<Category> cats) {
    final expanded = _expandedOwners.contains(owner);
    final hasNew = cats.any((c) => _newIds.contains(c.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() {
            if (expanded) {
              _expandedOwners.remove(owner);
            } else {
              _expandedOwners.add(owner);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  color: Colors.grey[700],
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 16),
                      children: [
                        const TextSpan(text: 'from '),
                        TextSpan(
                          text: owner,
                          style:
                              const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasNew)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('NEW',
                        style: TextStyle(fontSize: 10, color: Colors.white)),
                  ),
                const SizedBox(width: 8),
                Text('${cats.length}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 4),
            child: Column(children: cats.map(_buildSharedWithMeRow).toList()),
          ),
      ],
    );
  }

  Widget _buildSharedWithMeRow(Category category) {
    final isNew = _newIds.contains(category.id);
    final checked = _selected.contains(category.id);
    final hasInvitation =
        category.invitation != null && category.invitation!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Card(
        shape: isNew
            ? RoundedRectangleBorder(
                side: const BorderSide(color: Colors.blue, width: 2),
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            category.headline,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isNew)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text('NEW',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.white)),
                          ),
                        // No invitation → the task-preview arrow rides the headline.
                        if (!hasInvitation) _previewArrowWidget(category),
                      ],
                    ),
                    if (hasInvitation)
                      Builder(builder: (context) {
                        const limit = 100;
                        final full = category.invitation!;
                        final expanded =
                            _expandedInvitations.contains(category.id);
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
                                    onTap: () => setState(() =>
                                        _expandedInvitations.add(category.id)),
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
                              _previewArrowSpan(category),
                            ],
                          ),
                        );
                      }),
                    if (_previewExpanded.contains(category.id))
                      _buildPreviewTasks(category),
                  ],
                ),
              ),
              Checkbox(
                value: checked,
                onChanged: (v) => setState(() {
                  if (v ?? false) {
                    _selected.add(category.id);
                  } else {
                    _selected.remove(category.id);
                  }
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
