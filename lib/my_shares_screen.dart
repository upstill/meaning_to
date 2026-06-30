import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/borrow_explanation.dart';

/// Lists the pursuits other people have shared with the current user. Newly
/// received shares (seen_at IS NULL) are highlighted; opening this screen marks
/// them seen so the highlight and the home-screen notification clear.
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
  late List<Category> _sharedWithMe;
  final Set<int> _expandedInvitations = {};

  /// Category ids that were unseen when this screen opened — highlighted here.
  Set<int> _newIds = {};

  @override
  void initState() {
    super.initState();
    _sharedWithMe = widget.allCategories.where((c) => c.isShared).toList();
    _load();
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

  Future<void> _toggleAvailable(Category category, bool value) async {
    setState(() => category.isAvailable = value);
    if (value && mounted) await showBorrowExplanationIfNeeded(context);
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
      appBar: AppBar(title: const Text('Shared With Me')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_sharedWithMe.isEmpty)
                    const Text(
                      'No pursuits have been shared with you.',
                      style: TextStyle(
                          color: Colors.grey, fontStyle: FontStyle.italic),
                    )
                  else
                    ..._sharedWithMe.map(_buildSharedWithMeRow),
                ],
              ),
            ),
    );
  }

  Widget _buildSharedWithMeRow(Category category) {
    final isNew = _newIds.contains(category.id);
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
                          style: TextStyle(fontSize: 10, color: Colors.white)),
                    ),
                  IconButton(
                    onPressed: () async {
                      if (!category.isAvailable) {
                        await _toggleAvailable(category, true);
                      } else if (mounted) {
                        await showBorrowExplanationIfNeeded(context);
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
              if (category.invitation != null &&
                  category.invitation!.isNotEmpty)
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
                  const Text('Borrow this', style: TextStyle(fontSize: 12)),
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
