import 'package:flutter/material.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/widgets/task_display.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/edit_category_screen.dart';
import 'dart:async';

class FindScreen extends StatefulWidget {
  const FindScreen({super.key});

  @override
  State<FindScreen> createState() => _FindScreenState();
}

class _FindScreenState extends State<FindScreen> {
  final _searchController = TextEditingController();
  List<Task> _searchResults = [];
  Map<int, Category> _categoryMap = {};
  bool _isSearching = false;
  Timer? _searchDebounceTimer;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await ApiClient.getCategories();

      // Create a map of category ID to Category for quick lookup
      final categoryMap = <int, Category>{};
      for (final category in categories) {
        categoryMap[category.id] = category;
      }

      if (mounted) {
        setState(() {
          _categoryMap = categoryMap;
        });
      }
    } catch (e) {
      print('FindScreen: Error loading categories: $e');
    }
  }

  void _onSearchChanged() {
    // Debounce search to avoid too many API calls
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch();
    });
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isSearching = true;
      });
    }

    try {
      print('FindScreen: Searching database for "$query"');
      final tasks = await ApiClient.searchTasksByHeadline(query);
      print('FindScreen: Database returned ${tasks.length} matching tasks');

      if (mounted) {
        setState(() {
          _searchResults = tasks;
          _isSearching = false;
        });
      }
    } catch (e) {
      print('FindScreen: Error searching tasks: $e');
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  List<Task> get _filteredTasks {
    return _searchResults;
  }

  Map<int, List<Task>> get _tasksByCategory {
    final Map<int, List<Task>> grouped = {};
    for (final task in _filteredTasks) {
      if (!grouped.containsKey(task.categoryId)) {
        grouped[task.categoryId] = [];
      }
      grouped[task.categoryId]!.add(task);
    }
    return grouped;
  }

  Future<void> _editTask(Task task) async {
    final category = _categoryMap[task.categoryId];
    if (category == null) {
      print('FindScreen: Category not found for task ${task.id}');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TaskEditScreen(category: category, task: task),
      ),
    );

    // Refresh search results after editing
    _performSearch();
  }

  Future<void> _deleteTask(Task task) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Task'),
          content: Text('Are you sure you want to delete "${task.headline}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        // Delete the task
        await ApiClient.deleteTask(task.id.toString());
        // Refresh search results
        _performSearch();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting task: $e')),
          );
        }
      }
    }
  }

  Future<void> _toggleTaskCompletion(Task task) async {
    try {
      await ApiClient.updateTaskFinished(task.id, !task.finished);
      _performSearch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating task: $e')),
        );
      }
    }
  }

  Future<void> _makeTaskAvailable(Task task) async {
    try {
      await ApiClient.updateTaskSuggestibleAt(
          task.id, DateTime.now().toIso8601String());
      _performSearch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating task: $e')),
        );
      }
    }
  }

  Future<void> _toggleTaskShare(Task task, bool newSharedState) async {
    try {
      await ApiClient.updateTaskShared(task.id, newSharedState);
      _performSearch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating task: $e')),
        );
      }
    }
  }

  void _navigateToCategory(Category category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditCategoryScreen(category: category),
      ),
    ).then((_) {
      // Refresh search results when returning from category screen
      _performSearch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredTasks = _filteredTasks;
    final tasksByCategory = _tasksByCategory;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Tasks'),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchController.clear();
              },
              tooltip: 'Clear search',
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search tasks by headline...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
              onChanged: (value) {
                // Explicitly trigger rebuild when text changes
                setState(() {});
              },
            ),
          ),
          if (_isSearching)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Searching...',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else if (_searchController.text.trim().isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Enter a search term to find tasks',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (filteredTasks.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No tasks found',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try a different search term',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: tasksByCategory.length,
                itemBuilder: (context, index) {
                  final categoryId = tasksByCategory.keys.elementAt(index);
                  final category = _categoryMap[categoryId];
                  final tasks = tasksByCategory[categoryId]!;

                  if (category == null) {
                    return const SizedBox.shrink();
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: InkWell(
                          onTap: () => _navigateToCategory(category),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  category.headline,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                ),
                              ),
                              Text(
                                '${tasks.length} ${tasks.length == 1 ? NamingUtils.tasksName(plural: false) : NamingUtils.tasksName(plural: true)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Tasks in this category
                      ...tasks.map((task) => Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: TaskDisplay(
                              key: ValueKey('task-${task.id}'),
                              task: task,
                              withControls: true,
                              onEdit: () => _editTask(task),
                              onDelete: () => _deleteTask(task),
                              onTap: () => _toggleTaskCompletion(task),
                              onUpdateSuggestibleAt: (DateTime newTime) =>
                                  _makeTaskAvailable(task),
                              onShareToggle: (bool newSharedState) =>
                                  _toggleTaskShare(task, newSharedState),
                              isCategoryPrivate: category.isPrivate,
                            ),
                          )),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
