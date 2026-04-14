import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/deep_link_generator.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/widgets/task_display.dart';
import 'package:meaning_to/home_screen.dart' show HomeTaskSortOption, HomeScreen;

class EditShareTasksScreen extends StatefulWidget {
  final Category category;

  const EditShareTasksScreen({super.key, required this.category});

  static Future<void> push(BuildContext context, {required Category category}) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditShareTasksScreen(category: category),
      ),
    );
  }

  @override
  State<EditShareTasksScreen> createState() => _EditShareTasksScreenState();
}

class _EditShareTasksScreenState extends State<EditShareTasksScreen> {
  List<Task> _allTasks = [];
  List<Task> _displayedTasks = [];
  bool _loading = true;
  bool _saving = false;
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
      final userId = AuthUtils.getCurrentUserId();
      final tasks = await ApiClient.getTasksByCategoryAndUser(
          widget.category.id, userId);
      if (mounted) {
        _allTasks = tasks;
        _selectedIds = tasks
            .where((t) => t.shared)
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
        tasks.sort((a, b) => a.createdAt.compareTo(b.createdAt));
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // Save shared-task selections.
      int changed = 0;
      for (final task in _allTasks) {
        final nowShared = _selectedIds.contains(task.id);
        if (task.shared != nowShared) {
          await ApiClient.updateTaskShared(task.id, nowShared);
          changed++;
        }
      }
      if (changed > 0) HomeScreen.needsTaskReload.value = true;

      // Create or reuse the invitation and copy the link to clipboard.
      final token = await ApiClient.createShareInvitation(widget.category.id);
      final link = DeepLinkGenerator.generateInviteLink(token);
      await Clipboard.setData(ClipboardData(text: link));

      if (mounted) {
        // Pop back past this screen and any dialog underneath it.
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).popUntil((route) => route.isFirst);
        messenger.showSnackBar(
          const SnackBar(content: Text('Invite link copied to clipboard')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
          onChanged: (v) { if (v != null) _setSort(v); },
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
        hintText: 'Search ${NamingUtils.tasksName(capitalize: true, plural: true)}...',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 20),
                onPressed: _searchController.clear,
              )
            : null,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
        title: const Text('Edit Shared Tasks'),
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Category header ───────────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.category.headline, style: headlineStyle),
                      const SizedBox(height: 4),
                      const Text(
                        'Check the tasks you want visible to subscribers.',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
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
                            ? 'Share All'
                            : 'Share All  (${_selectedIds.length} shared)',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: allSelected ? 'Unshare all' : 'Share all',
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              if (allSelected || someSelected) {
                                _selectedIds = {};
                              } else {
                                _selectedIds =
                                    _displayedTasks.map((t) => t.id).toSet();
                              }
                            });
                          },
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: allSelected
                                  ? Colors.green.shade600
                                  : someSelected
                                      ? Colors.green.shade300
                                      : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              allSelected || someSelected
                                  ? Icons.share
                                  : Icons.share_outlined,
                              size: 16,
                              color: allSelected || someSelected
                                  ? Colors.white
                                  : Colors.grey.shade400,
                            ),
                          ),
                        ),
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
                                    key: ValueKey(
                                        'edit-share-task-${task.id}'),
                                    task: task,
                                    withControls: false,
                                    isSelected:
                                        _selectedIds.contains(task.id),
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
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context)
                              .popUntil((route) => route.isFirst),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _saving || _loading ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.share, size: 16),
                                SizedBox(width: 6),
                                Text('Issue Link'),
                              ],
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
