import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/utils/app_buttons.dart';

/// A keyboard-friendly modal bottom sheet for switching pursuits. Shows a
/// search field (only once there are [searchThreshold]+ pursuits) that filters
/// the list by title, plus an optional "New Pursuit" action. Works the same on
/// desktop and phone (rises above the keyboard).
class PursuitSwitcherSheet extends StatefulWidget {
  final List<Category> categories; // switchable pursuits, in display order
  final void Function(Category) onSelect;
  final VoidCallback? onNewPursuit; // null hides the action (e.g. guests)
  final int searchThreshold;

  const PursuitSwitcherSheet({
    super.key,
    required this.categories,
    required this.onSelect,
    this.onNewPursuit,
    this.searchThreshold = 8,
  });

  static Future<void> show(
    BuildContext context, {
    required List<Category> categories,
    required void Function(Category) onSelect,
    VoidCallback? onNewPursuit,
    int searchThreshold = 8,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PursuitSwitcherSheet(
        categories: categories,
        onSelect: onSelect,
        onNewPursuit: onNewPursuit,
        searchThreshold: searchThreshold,
      ),
    );
  }

  @override
  State<PursuitSwitcherSheet> createState() => _PursuitSwitcherSheetState();
}

class _PursuitSwitcherSheetState extends State<PursuitSwitcherSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pursuit = NamingUtils.categoriesName(plural: false, capitalize: true);
    final pursuits = NamingUtils.categoriesName(plural: true);
    final showSearch = widget.categories.length >= widget.searchThreshold;

    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.categories
        : widget.categories
            .where((c) => c.headline.toLowerCase().contains(q))
            .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Choose a $pursuit',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            if (showSearch)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search $pursuits…',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in filtered)
                    ListTile(
                      dense: true,
                      title: Text(c.headline),
                      subtitle: (c.isShared && c.ownerName != null)
                          ? Text('from ${c.ownerName}',
                              style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey[600]))
                          : null,
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onSelect(c);
                      },
                    ),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text('No matching $pursuits',
                            style: TextStyle(color: Colors.grey[600])),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.onNewPursuit != null) ...[
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.add, color: AppButtons.goForthBg),
                title: Text('New $pursuit',
                    style: TextStyle(color: AppButtons.goForthBg)),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onNewPursuit!();
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
