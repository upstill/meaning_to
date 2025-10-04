import 'package:flutter/material.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/dialogs/category_picker_dialog.dart';

/// Dialog for selecting a task to add a link to
class TaskPickerDialog extends StatefulWidget {
  final String title;
  final Function(Task, Category) onTaskSelected;
  final Category? preselectedCategory;

  const TaskPickerDialog({
    super.key,
    required this.title,
    required this.onTaskSelected,
    this.preselectedCategory,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required Function(Task, Category) onTaskSelected,
    Category? preselectedCategory,
  }) {
    return showDialog(
      context: context,
      builder: (context) => TaskPickerDialog(
        title: title,
        onTaskSelected: onTaskSelected,
        preselectedCategory: preselectedCategory,
      ),
    );
  }

  @override
  State<TaskPickerDialog> createState() => _TaskPickerDialogState();
}

class _TaskPickerDialogState extends State<TaskPickerDialog> {
  Category? _selectedCategory;
  List<Category> _categories = [];
  List<Task> _tasks = [];
  bool _isLoadingCategories = true;
  bool _isLoadingTasks = false;
  String? _error;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.preselectedCategory;
    _loadCategories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      setState(() {
        _isLoadingCategories = true;
        _error = null;
      });

      final userId = AuthUtils.getCurrentUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Load all categories
      final response = await supabase
          .from('Categories')
          .select()
          .eq('owner_id', userId)
          .order('headline');

      final categoriesData = response as List<dynamic>;
      final categories = categoriesData
          .map((data) => Category.fromJson(data))
          .toList();

      setState(() {
        _categories = categories;
        _isLoadingCategories = false;
      });

      // Load tasks for the preselected category if available
      if (_selectedCategory != null) {
        await _loadTasksForCategory(_selectedCategory!);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoadingCategories = false;
      });
    }
  }

  Future<void> _loadTasksForCategory(Category category) async {
    try {
      setState(() {
        _isLoadingTasks = true;
        _error = null;
      });

      final userId = AuthUtils.getCurrentUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Load tasks for the selected category
      final response = await supabase
          .from('Tasks')
          .select()
          .eq('owner_id', userId)
          .eq('category_id', category.id)
          .eq('finished', false) // Only show unfinished tasks
          .order('headline');

      final tasksData = response as List<dynamic>;
      final tasks = tasksData
          .map((data) => Task.fromJson(data))
          .toList();

      setState(() {
        _tasks = tasks;
        _isLoadingTasks = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoadingTasks = false;
      });
    }
  }

  List<Task> get _filteredTasks {
    if (_searchQuery.isEmpty) {
      return _tasks;
    }

    return _tasks
        .where((task) =>
            task.headline.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (task.notes?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: Column(
          children: [
            // Category selection
            _buildCategorySelector(),
            const SizedBox(height: 12),

            // Search field (only show if category is selected)
            if (_selectedCategory != null) ...[
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search tasks...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
              const SizedBox(height: 12),
            ],

            // Tasks list
            Expanded(
              child: _buildTasksList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildCategorySelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Category',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                Text(
                  _selectedCategory?.headline ?? 'Select a category',
                  style: TextStyle(
                    fontSize: 14,
                    color: _selectedCategory != null
                        ? null
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _isLoadingCategories ? null : _selectCategory,
            child: Text(_selectedCategory != null ? 'Change' : 'Select'),
          ),
        ],
      ),
    );
  }

  Widget _buildTasksList() {
    if (_isLoadingCategories) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 8),
            Text('Loading categories...'),
          ],
        ),
      );
    }

    if (_selectedCategory == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              'Select a category to view tasks',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoadingTasks) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 8),
            Text('Loading tasks...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              'Error loading tasks',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _loadTasksForCategory(_selectedCategory!),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final tasks = _filteredTasks;

    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.task_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No tasks match your search'
                  : 'No unfinished tasks in this category',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _buildTaskTile(task);
      },
    );
  }

  Widget _buildTaskTile(Task task) {
    final linkCount = task.links?.length ?? 0;

    return ListTile(
      leading: Icon(
        Icons.task_alt,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        task.headline,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (task.notes != null && task.notes!.isNotEmpty) ...[
            Text(
              task.notes!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
          Row(
            children: [
              Icon(
                Icons.link,
                size: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '$linkCount link${linkCount != 1 ? 's' : ''}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
      onTap: () => _selectTask(task),
      dense: true,
    );
  }

  void _selectCategory() {
    CategoryPickerDialog.show(
      context,
      title: 'Select Category',
      defaultCategory: _selectedCategory,
      showCreateNew: false,
      onCategorySelected: (category, {bool? shouldMove}) {
        setState(() {
          _selectedCategory = category;
          _tasks = [];
          _searchQuery = '';
          _searchController.clear();
        });
        _loadTasksForCategory(category);
      },
    );
  }

  void _selectTask(Task task) {
    Navigator.of(context).pop();
    widget.onTaskSelected(task, _selectedCategory!);
  }
}