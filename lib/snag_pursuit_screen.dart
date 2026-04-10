import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/dialogs/category_picker_dialog.dart';
import 'package:meaning_to/widgets/task_display.dart';
import 'package:meaning_to/home_screen.dart' show HomeTaskSortOption;
import 'package:supabase_flutter/supabase_flutter.dart';

class SnagPursuitScreen extends StatefulWidget {
  final Category sharedCategory;
  final List<Category> allCategories;

  const SnagPursuitScreen({
    super.key,
    required this.sharedCategory,
    required this.allCategories,
  });

  static Future<Category?> push(
    BuildContext context, {
    required Category sharedCategory,
    required List<Category> allCategories,
  }) {
    return Navigator.of(context).push<Category>(
      MaterialPageRoute(
        builder: (_) => SnagPursuitScreen(
          sharedCategory: sharedCategory,
          allCategories: allCategories,
        ),
      ),
    );
  }

  @override
  State<SnagPursuitScreen> createState() => _SnagPursuitScreenState();
}

class _SnagPursuitScreenState extends State<SnagPursuitScreen> {
  List<Task> _allTasks = [];
  List<Task> _displayedTasks = [];
  bool _loading = true;
  String? _error;
  Set<int> _selectedIds = {};
  HomeTaskSortOption _sortOption = HomeTaskSortOption.priority;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilter);
    _load();
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilter);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Find user's existing owned category cloned from the same original.
      final sharedOriginalId =
          widget.sharedCategory.originalId ?? widget.sharedCategory.id;
      final cloneCategory = widget.allCategories
          .where((c) => !c.isShared && c.originalId == sharedOriginalId)
          .firstOrNull;

      // Load shared tasks, and (if clone exists) existing owned tasks in parallel.
      final results = await Future.wait([
        ApiClient.getTasksByCategory(widget.sharedCategory.id)
            .then((tasks) => tasks.where((t) => t.shared).toList()),
        if (cloneCategory != null)
          ApiClient.getTasksByCategory(cloneCategory.id),
      ]);

      final tasks = results[0];
      Set<String> existingHeadlines = {};
      if (cloneCategory != null && results.length > 1) {
        existingHeadlines =
            results[1].map((t) => t.headline.trim().toLowerCase()).toSet();
      }

      if (mounted) {
        _allTasks = tasks;
        // Pre-select all tasks except those redundant with the existing clone.
        _selectedIds = tasks
            .where((t) =>
                !existingHeadlines.contains(t.headline.trim().toLowerCase()))
            .map((t) => t.id)
            .toSet();
        _applyFilter();
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load tasks: $e';
          _loading = false;
        });
      }
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    List<Task> filtered = query.isEmpty
        ? List.of(_allTasks)
        : _allTasks
            .where((t) =>
                t.headline.toLowerCase().contains(query) ||
                (t.notes?.toLowerCase().contains(query) ?? false))
            .toList();
    _sortTasks(filtered);
    if (mounted) setState(() => _displayedTasks = filtered);
  }

  void _sortTasks(List<Task> tasks) {
    switch (_sortOption) {
      case HomeTaskSortOption.alphabetical:
        tasks.sort((a, b) => a.headline.compareTo(b.headline));
      case HomeTaskSortOption.age:
        tasks.sort((a, b) =>
            (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
      case HomeTaskSortOption.priority:
        tasks.sort((a, b) {
          final aAt = a.suggestibleAt;
          final bAt = b.suggestibleAt;
          if (aAt == null && bAt == null) return 0;
          if (aAt == null) return -1;
          if (bAt == null) return 1;
          return aAt.compareTo(bAt);
        });
    }
  }

  void _setSort(HomeTaskSortOption option) {
    setState(() {
      _sortOption = option;
      _applyFilter();
    });
  }

  void _toggleSelect(int taskId, bool? val) {
    setState(() {
      if (val == true) {
        _selectedIds.add(taskId);
      } else {
        _selectedIds.remove(taskId);
      }
    });
  }

  Future<void> _snagSelected() async {
    if (_selectedIds.isEmpty) return;
    final selected =
        _allTasks.where((t) => _selectedIds.contains(t.id)).toList();

    // Look for an owned category that is a clone of the same original
    final sharedOriginalId =
        widget.sharedCategory.originalId ?? widget.sharedCategory.id;
    final cloneCategory = widget.allCategories
        .where((c) => !c.isShared && c.originalId == sharedOriginalId)
        .firstOrNull;

    final topLabel = cloneCategory != null
        ? "My existing '${cloneCategory.headline}'"
        : "A '${widget.sharedCategory.headline}' pursuit of my own";

    if (!mounted) return;
    await CategoryPickerDialog.show(
      context,
      title: 'Copy to which Pursuit?',
      subtitle: 'Select one of your own Pursuits to copy these '
          '${NamingUtils.tasksName(plural: true, capitalize: false)} into.',
      showCreateNew: true,
      hideShared: true,
      excludeCategory: cloneCategory,
      topButtonLabel: topLabel,
      topButtonOnPressed: () {
        if (cloneCategory != null) {
          _copyTasksTo(selected, cloneCategory);
        } else {
          _createCloneAndCopyTasksTo(selected);
        }
      },
      onCategorySelected: (target, {bool? shouldMove, bool? applyToAll}) {
        _copyTasksTo(selected, target);
      },
    );
  }

  Future<void> _createCloneAndCopyTasksTo(List<Task> tasks) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final newCategory = await ApiClient.createCategory({
        'headline': widget.sharedCategory.headline,
        'owner_id': userId,
        'original_id':
            widget.sharedCategory.originalId ?? widget.sharedCategory.id,
        if (widget.sharedCategory.invitation != null)
          'invitation': widget.sharedCategory.invitation,
      });
      await _copyTasksTo(tasks, newCategory);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not create Pursuit: $e'),
        ));
      }
    }
  }

  Future<void> _copyTasksTo(List<Task> tasksArg, Category target) async {
    List<Task> tasks = tasksArg;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    // Check for duplicate headlines in the target category.
    try {
      final existing = await ApiClient.getTasksByCategory(target.id);
      final existingHeadlines =
          existing.map((t) => t.headline.trim().toLowerCase()).toSet();
      final conflicts = tasks
          .where((t) =>
              existingHeadlines.contains(t.headline.trim().toLowerCase()))
          .toList();

      if (conflicts.isNotEmpty && mounted) {
        final String message;
        if (conflicts.length == 1) {
          message =
              '"${conflicts[0].headline}" is already a task in "${target.headline}". What to do?';
        } else {
          message =
              '"${conflicts[0].headline}" and ${conflicts.length - 1} other '
              '${NamingUtils.tasksName(plural: conflicts.length > 2, capitalize: false)} '
              'are already in "${target.headline}". What to do?';
        }
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Duplicate Task'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'omit'),
                child: const Text('Omit Redundant'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, 'save'),
                child: const Text('Save Anyway'),
              ),
            ],
          ),
        );
        if (choice == 'cancel' || choice == null) return;
        if (choice == 'omit') {
          tasks = tasks
              .where((t) =>
                  !existingHeadlines.contains(t.headline.trim().toLowerCase()))
              .toList();
        }
      }
    } catch (_) {
      // If the duplicate check fails, proceed without it.
    }

    int copied = 0;
    for (final task in tasks) {
      try {
        await ApiClient.createTask({
          'headline': task.headline,
          if (task.notes != null) 'notes': task.notes,
          if (task.synopsis != null) 'synopsis': task.synopsis,
          'owner_id': userId,
          'category_id': target.id,
          'original_id': task.id,
          if (task.links != null && task.links!.isNotEmpty) 'links': task.links,
          'finished': false,
          'shared': false,
        });
        copied++;
      } catch (e) {
        debugPrint('Error copying task "${task.headline}": $e');
      }
    }
    if (mounted) {
      setState(() => _selectedIds = {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Copied $copied ${NamingUtils.tasksName(plural: copied != 1, capitalize: false)} '
          'to "${target.headline}"',
        ),
      ));

      final shouldRelease = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
              'Release ${widget.sharedCategory.ownerName != null ? '${widget.sharedCategory.ownerName}\'s ' : ''}"${widget.sharedCategory.headline}" from your list?'),
          content: Text(
            'Now that you\'ve copied what you wanted, do you want to release this share '
            'from your ${NamingUtils.categoriesName(capitalize: true, plural: true)} menu?'
            '(You can always get it back using the "My Shares" item in the ${NamingUtils.categoriesName(capitalize: true, plural: false)}\'s menu.)',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep It'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[700],
                foregroundColor: Colors.white,
              ),
              child: const Text('Remove It'),
            ),
          ],
        ),
      );

      if (shouldRelease == true && mounted) {
        try {
          await ApiClient.releaseSharedCategory(widget.sharedCategory.id);
        } catch (e) {
          debugPrint('Error releasing shared category: $e');
        }
      }

      if (mounted) Navigator.of(context).pop(target);
    }
  }

  Widget _buildSortRow(HomeTaskSortOption option, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<HomeTaskSortOption>(
          value: option,
          groupValue: _sortOption,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          onChanged: (v) {
            if (v != null) _setSort(v);
          },
        ),
        Text(label),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headlineFontSize = (theme.textTheme.bodyLarge?.fontSize ?? 16) + 10;
    final headlineStyle = TextStyle(
      fontSize: headlineFontSize,
      fontWeight: FontWeight.bold,
      color: const Color(0xFF1A237E),
    );

    final allSelected = _displayedTasks.isNotEmpty &&
        _selectedIds.containsAll(_displayedTasks.map((t) => t.id));
    final someSelected = !allSelected && _selectedIds.isNotEmpty;

    final sortWidget = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text('Sort By:'),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSortRow(HomeTaskSortOption.priority, 'Priority'),
            _buildSortRow(HomeTaskSortOption.alphabetical, 'A-Z'),
            _buildSortRow(HomeTaskSortOption.age, 'Age'),
          ],
        ),
      ],
    );

    final searchWidget = TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText:
            'Search ${NamingUtils.tasksName(capitalize: true, plural: true)}...',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 20),
                onPressed: () {
                  _searchController.clear();
                },
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: const OutlineInputBorder(),
      ),
    );

    final headerRow = LayoutBuilder(builder: (context, constraints) {
      final sortAreaWidth = (constraints.maxWidth * 0.35).clamp(0.0, 240.0);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: sortAreaWidth,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: sortWidget,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: searchWidget),
        ],
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Snag For Me'),
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Top card — mirrors the home screen category card ─────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Pursuit name (large bold blue)
                      Text(widget.sharedCategory.headline,
                          style: headlineStyle),
                      if ((widget.sharedCategory.ownerName ?? '').isNotEmpty)
                        Text(
                          'from ${widget.sharedCategory.ownerName}',
                          style: TextStyle(
                            fontSize: headlineFontSize * 0.7,
                            fontStyle: FontStyle.italic,
                            color: const Color(0xFF1A237E),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // ── Explanation ───────────────────────────────────────────────
              Text(
                'Select the ${NamingUtils.tasksName(plural: true, capitalize: false)} '
                'you\'d like to copy into your '
                '${NamingUtils.categoriesName(plural: false, capitalize: true)}. ',
                style: const TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 8),

              // ── Sort + Search ─────────────────────────────────────────────
              headerRow,
              const SizedBox(height: 8),

              // ── Select All ────────────────────────────────────────────────
              if (!_loading && _displayedTasks.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _selectedIds.isEmpty
                            ? 'Select All'
                            : 'Select All  (${_selectedIds.length} selected)',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      Checkbox(
                        tristate: true,
                        value:
                            allSelected ? true : (someSelected ? null : false),
                        onChanged: (val) {
                          setState(() {
                            if (allSelected || someSelected) {
                              _selectedIds = {};
                            } else {
                              _selectedIds =
                                  _displayedTasks.map((t) => t.id).toSet();
                            }
                          });
                        },
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),

              // ── Task list ─────────────────────────────────────────────────
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Text(_error!,
                                style: const TextStyle(color: Colors.red)))
                        : _displayedTasks.isEmpty
                            ? Center(
                                child: Text(
                                  _searchController.text.isNotEmpty
                                      ? 'No matching ${NamingUtils.tasksName(plural: true, capitalize: false)} found.'
                                      : 'No ${NamingUtils.tasksName(plural: true, capitalize: false)} yet.',
                                  style: const TextStyle(
                                      fontSize: 16, color: Colors.grey),
                                ),
                              )
                            : ListView.builder(
                                itemCount: _displayedTasks.length,
                                itemBuilder: (_, i) {
                                  final task = _displayedTasks[i];
                                  return TaskDisplay(
                                    key: ValueKey('snag-task-${task.id}'),
                                    task: task,
                                    withControls: false,
                                    isSelected: _selectedIds.contains(task.id),
                                    onSelected: (val) =>
                                        _toggleSelect(task.id, val),
                                  );
                                },
                              ),
              ),

              // ── Bottom action bar ─────────────────────────────────────────
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _selectedIds.isEmpty ? null : _snagSelected,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        _selectedIds.isEmpty
                            ? 'Snag Selected'
                            : 'Snag ${_selectedIds.length} Selected',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
