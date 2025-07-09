import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/widgets/task_display.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/add_tasks_screen.dart';
import 'package:meaning_to/shop_endeavors_screen.dart';
import 'dart:async';

class EditCategoryScreen extends StatefulWidget {
  static VoidCallback? onEditComplete; // Static callback for edit completion

  final Category? category; // null for new category, existing category for edit
  final bool tasksOnly;

  const EditCategoryScreen({super.key, this.category, this.tasksOnly = false});

  // Add a factory constructor to handle arguments from Navigator
  static Route routeFromArgs(RouteSettings settings) {
    final args = settings.arguments as Map<String, dynamic>?;
    print('EditCategoryScreen: routeFromArgs called');
    return MaterialPageRoute(
      builder: (_) => EditCategoryScreen(
        category: args?['category'] as Category?,
        tasksOnly: args?['tasksOnly'] == true,
      ),
      settings: settings,
    );
  }

  @override
  EditCategoryScreenState createState() => EditCategoryScreenState();
}

class EditCategoryScreenState extends State<EditCategoryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _headlineController = TextEditingController();
  final _invitationController = TextEditingController();
  bool _isLoading = false;
  bool _editTasksLocal = false;
  bool _isEditing = false;
  bool _categorySaved = false; // Track if category has been saved
  bool _isPrivate = false; // Private flag for categories
  Category?
      _currentCategory; // Track the current category (for new categories after creation)
  StreamSubscription<void>? _cacheSubscription;

  // Pure UI getter for tasks from the cache
  List<Task> get _tasks {
    final tasks = CacheManager().currentTasks ?? [];
    print(
        'EditCategoryScreen: Getting tasks from cache - ${tasks.length} tasks');
    for (final task in tasks) {
      print(
          'EditCategoryScreen: Task "${task.headline}" - isDeferred: ${task.isDeferred}, suggestibleAt: ${task.suggestibleAt}');
    }
    return tasks;
  }

  @override
  void initState() {
    super.initState();
    print('EditCategoryScreen: initState called');
    print('EditCategoryScreen: Current category: ${widget.category?.headline}');

    _headlineController.text = widget.category?.headline ?? '';
    _invitationController.text = widget.category?.invitation ?? '';
    _isPrivate = widget.category?.isPrivate ?? false;
    _editTasksLocal = widget.tasksOnly;

    // Set category as saved if it already exists
    _categorySaved = widget.category != null;

    // Add listener to track headline changes for button state
    _headlineController.addListener(() {
      setState(() {
        // Trigger rebuild when headline changes to update button state
      });
    });

    // Listen for cache changes to update UI
    _cacheSubscription = CacheManager.onCacheChanged.listen((_) {
      print('EditCategoryScreen: Cache changed, rebuilding UI');
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _headlineController.dispose();
    _invitationController.dispose();
    _cacheSubscription?.cancel();
    super.dispose();
  }

  // Pure UI method - no database operations
  void _handleBack() {
    print('EditCategoryScreen: Back button pressed');
    print('EditCategoryScreen: Current category: ${widget.category?.headline}');
    print(
        'EditCategoryScreen: Static callback available: ${EditCategoryScreen.onEditComplete != null}');

    // Call the static callback before popping
    if (EditCategoryScreen.onEditComplete != null) {
      print('EditCategoryScreen: Calling static callback');
      try {
        EditCategoryScreen.onEditComplete!();
        print('EditCategoryScreen: Static callback executed successfully');
      } catch (e) {
        print('EditCategoryScreen: Error executing static callback: $e');
      }
    } else {
      print('EditCategoryScreen: No static callback available');
    }

    // Pop after executing the callback
    if (mounted) {
      Navigator.of(context)
          .pop(true); // Always return true to indicate completion
      print('EditCategoryScreen: Popped screen with true result');
    } else {
      print('EditCategoryScreen: Widget not mounted, cannot pop');
    }
  }

  // Pure UI method - no database operations
  Future<void> _editTask(Task task) async {
    final currentCategory = widget.category ?? _currentCategory;
    if (currentCategory == null) {
      // For new categories, show error message - category must be saved first
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Please save the category first before editing tasks'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    } else {
      // For existing categories, use the normal flow
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              TaskEditScreen(category: currentCategory, task: task),
        ),
      );

      if (result == true) {
        // Tasks were modified, trigger UI rebuild to reflect cache changes
        print('EditCategoryScreen: Tasks were modified, rebuilding UI');
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  // Pure UI method - no database operations
  Future<void> _createTask() async {
    final currentCategory = widget.category ?? _currentCategory;
    if (currentCategory == null) {
      // For new categories, show error message - category must be saved first
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please save the category first before adding tasks'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    } else {
      // For existing categories, use the normal flow
      final result = await Navigator.pushNamed(
        context,
        '/edit-task',
        arguments: {'category': currentCategory, 'task': null},
      );

      if (result == true) {
        // Tasks were added, trigger UI rebuild to reflect cache changes
        print('EditCategoryScreen: Tasks were added, rebuilding UI');
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  // Pure UI method - no database operations
  Future<void> _deleteTask(Task task) async {
    print(
        '=== Starting delete task for: ${task.headline} (ID: ${task.id}) ===');
    print('EditCategoryScreen: _deleteTask called with task: ${task.headline}');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Are you sure you want to delete "${task.headline}"?'),
        actions: [
          TextButton(
            onPressed: () {
              print('EditCategoryScreen: Delete cancelled by user');
              Navigator.pop(context, false);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              print('EditCategoryScreen: Delete confirmed by user');
              Navigator.pop(context, true);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    print('EditCategoryScreen: Dialog result: $confirmed');

    if (confirmed != true) {
      print('Delete cancelled by user');
      return;
    }

    try {
      // Use CacheManager to delete the task
      await CacheManager().removeTask(task.id);

      // Trigger a rebuild to reflect the changes
      setState(() {});

      print('Successfully deleted task: ${task.headline}');
    } catch (e) {
      print('Error deleting task: $e');

      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    print('=== End delete task ===');
  }

  // Pure UI method - no database operations
  Future<void> _toggleTaskCompletion(Task task) async {
    try {
      if (task.finished) {
        await CacheManager().unfinishTask(task.id);
      } else {
        await CacheManager().finishTask(task.id);
      }
      setState(() {}); // Trigger rebuild to reflect cache changes
    } catch (e) {
      print('Error toggling task completion: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Pure UI method - no database operations
  Future<void> _makeTaskAvailable(Task task) async {
    try {
      print(
          'EditCategoryScreen: _makeTaskAvailable called for task: ${task.headline}');
      print('EditCategoryScreen: Task ID: ${task.id}');

      // Use the existing CacheManager instance that's already initialized
      final cacheManager = CacheManager();
      print('EditCategoryScreen: CacheManager instance created');

      await cacheManager.reviveTask(task.id);
      print('EditCategoryScreen: cacheManager.reviveTask completed');

      setState(() {}); // Trigger rebuild to reflect cache changes
      print('EditCategoryScreen: Task made available successfully');
    } catch (e) {
      print('Error making task available: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error making task available: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Pure UI method - no database operations
  Future<void> _addTasksFromText() async {
    final currentCategory = widget.category ?? _currentCategory;
    if (currentCategory == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please save the category first before adding tasks'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddTasksScreen(category: currentCategory),
      ),
    );

    if (result == true) {
      // Tasks were added, trigger UI rebuild to reflect cache changes
      print('EditCategoryScreen: Tasks were added from text, rebuilding UI');
      if (mounted) {
        setState(() {});
      }
    }
  }

  // Pure UI method - no database operations
  Future<void> _shopForSuggestions() async {
    final currentCategory = widget.category ?? _currentCategory;
    if (currentCategory == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Please save the category first before shopping for suggestions'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ShopEndeavorsScreen(existingCategory: currentCategory),
      ),
    );

    if (result == true) {
      // Tasks were added, trigger UI rebuild to reflect cache changes
      print('EditCategoryScreen: Tasks were added from shop, rebuilding UI');
      if (mounted) {
        setState(() {});
      }

      // Call the edit complete callback to notify Home screen to refresh
      if (EditCategoryScreen.onEditComplete != null) {
        print(
            'EditCategoryScreen: Calling edit complete callback after shop tasks added');
        try {
          EditCategoryScreen.onEditComplete!();
          print(
              'EditCategoryScreen: Edit complete callback executed successfully after shop tasks');
        } catch (e) {
          print(
              'EditCategoryScreen: Error executing edit complete callback after shop tasks: $e');
        }
      } else {
        print(
            'EditCategoryScreen: No edit complete callback available after shop tasks');
      }
    }
  }

  Widget _buildTaskList() {
    if (_tasks.isEmpty) {
      print('EditCategoryScreen: No tasks to display');
      return Center(
          child: Text(
              'No ${NamingUtils.tasksName(plural: true)} yet. Add one to get started!'));
    }

    // Debug log to check task links and suggestibleAt times
    print(
      '\n=== EditCategoryScreen: Building task list with ${_tasks.length} tasks ===',
    );
    for (final task in _tasks) {
      print(
        'Task "${task.headline}" - isDeferred: ${task.isDeferred}, isSuggestible: ${task.isSuggestible}',
      );
    }

    print('EditCategoryScreen: Creating ListView.builder...');
    return ListView.builder(
      shrinkWrap: true, // Add this to ensure ListView takes minimum space
      physics:
          const NeverScrollableScrollPhysics(), // Disable scrolling since we're in a ListView
      itemCount: _tasks.length,
      itemBuilder: (context, index) {
        final task = _tasks[index];
        print(
          '\n=== EditCategoryScreen: Building TaskDisplay for "${task.headline}" at index $index ===',
        );
        print('Task links: ${task.links}');
        print('Task links type: ${task.links?.runtimeType}');
        print('Task links length: ${task.links?.length ?? 0}');
        print('About to create TaskDisplay widget...');

        final taskDisplay = TaskDisplay(
          key: ValueKey(
            'task-${task.id}',
          ), // Add a key to help Flutter track the widget
          task: task,
          withControls: true,
          onEdit: () => _editTask(task),
          onDelete: () => _deleteTask(task),
          onTap: () => _toggleTaskCompletion(task),
          onUpdateSuggestibleAt: (DateTime newTime) => _makeTaskAvailable(task),
        );

        print('TaskDisplay widget created successfully for "${task.headline}"');
        print('=== End TaskDisplay creation ===\n');

        return taskDisplay;
      },
    );
  }

  Widget _buildNewTaskList() {
    if (_tasks.isEmpty) {
      print('EditCategoryScreen: No new tasks to display');
      return Center(
          child: Text(
              'No ${NamingUtils.tasksName(plural: true)} yet. Add one to get started!'));
    }

    print(
        'EditCategoryScreen: Building new task list with ${_tasks.length} tasks');

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _tasks.length,
      itemBuilder: (context, index) {
        final task = _tasks[index];
        print(
            'EditCategoryScreen: Building new task "${task.headline}" at index $index');

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            title: Text(task.headline),
            subtitle: task.notes != null ? Text(task.notes!) : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _editTask(task),
                  tooltip:
                      'Edit ${NamingUtils.tasksName(capitalize: false, plural: false)}',
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => _deleteTask(task),
                  tooltip:
                      'Remove ${NamingUtils.tasksName(capitalize: false, plural: false)}',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _editNewTask(Task task) {
    // For new tasks, we can edit them directly
    showDialog(
      context: context,
      builder: (context) {
        final headlineController = TextEditingController(text: task.headline);
        final notesController = TextEditingController(text: task.notes ?? '');

        return AlertDialog(
          title: Text('Edit ${NamingUtils.tasksName()}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: headlineController,
                decoration: InputDecoration(
                  labelText: '${NamingUtils.tasksName()} Title',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final taskIndex = _tasks.indexWhere((t) => t.id == task.id);
                if (taskIndex != -1) {
                  setState(() {
                    _tasks[taskIndex] = Task(
                      id: task.id,
                      categoryId: task.categoryId,
                      ownerId: task.ownerId,
                      headline: headlineController.text,
                      notes: notesController.text.isEmpty
                          ? null
                          : notesController.text,
                      links: task.links,
                      processedLinks: task.processedLinks,
                      createdAt: task.createdAt,
                      suggestibleAt: task.suggestibleAt,
                      finished: task.finished,
                    );
                  });
                }
                Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _removeNewTask(int index) {
    setState(() {
      _tasks.removeAt(index);
    });
  }

  Widget _buildSummaryItem(
      String label, int count, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  String _buildTaskCountText() {
    print('EditCategoryScreen: _buildTaskCountText called');
    print('EditCategoryScreen: Total tasks in cache: ${_tasks.length}');
    print(
        'EditCategoryScreen: Current category ID: ${widget.category?.id ?? _currentCategory?.id}');

    final tasks = _tasks
        .where((task) =>
            task.categoryId == (widget.category?.id ?? _currentCategory?.id))
        .toList();

    print(
        'EditCategoryScreen: Filtered tasks for current category: ${tasks.length}');
    for (final task in tasks) {
      print(
          'EditCategoryScreen: Task "${task.headline}" - finished: ${task.finished}, isSuggestible: ${task.isSuggestible}');
    }

    final availableTasks =
        tasks.where((task) => !task.finished && task.isSuggestible).length;
    final deferredTasks =
        tasks.where((task) => !task.finished && task.isDeferred).length;
    final finishedTasks = tasks.where((task) => task.finished).length;

    print(
        'EditCategoryScreen: availableTasks: $availableTasks, deferredTasks: $deferredTasks, finishedTasks: $finishedTasks');

    if (availableTasks == 0) {
      final parts = <String>[];
      if (deferredTasks > 0) parts.add('$deferredTasks Deferred');
      if (finishedTasks > 0) parts.add('$finishedTasks Finished');

      if (parts.isEmpty) {
        return 'No ${NamingUtils.tasksName(plural: true)} On Deck';
      }
      return 'No ${NamingUtils.tasksName(plural: true)} On Deck (${parts.join(', ')})';
    }

    final parts = <String>[];
    if (deferredTasks > 0) parts.add('$deferredTasks Deferred');
    if (finishedTasks > 0) parts.add('$finishedTasks Finished');

    final taskText = availableTasks == 1
        ? '${NamingUtils.tasksName()} Is Up'
        : 'Available ${NamingUtils.tasksName(plural: true)}';
    final availableText =
        availableTasks == 1 ? 'Only One' : availableTasks.toString();

    if (parts.isEmpty) {
      return '$availableText $taskText';
    }
    return '$availableText $taskText (${parts.join(', ')})';
  }

  // Delete category and all its tasks from database
  Future<void> _deleteCategory() async {
    if (widget.category == null) {
      print('EditCategoryScreen: Cannot delete - no category provided');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final userId = AuthUtils.getCurrentUserId();
      final categoryId = widget.category!.id;

      print(
          'EditCategoryScreen: Deleting category ${widget.category!.headline} (ID: $categoryId)');

      // First, delete all tasks in this category
      print('EditCategoryScreen: Deleting all tasks in category...');
      final deleteTasksResponse = await supabase
          .from('Tasks')
          .delete()
          .eq('category_id', categoryId)
          .eq('owner_id', userId);

      print(
          'EditCategoryScreen: Tasks deletion response: $deleteTasksResponse');

      // Then, delete the category itself
      print('EditCategoryScreen: Deleting category...');
      final deleteCategoryResponse = await supabase
          .from('Categories')
          .delete()
          .eq('id', categoryId)
          .eq('owner_id', userId);

      print(
          'EditCategoryScreen: Category deletion response: $deleteCategoryResponse');

      // Clear the cache
      CacheManager().clearCache();
      print('EditCategoryScreen: Cache cleared');

      // Call the edit complete callback to update home screen
      if (EditCategoryScreen.onEditComplete != null) {
        print(
            'EditCategoryScreen: Calling edit complete callback after deletion');
        try {
          EditCategoryScreen.onEditComplete!();
          print(
              'EditCategoryScreen: Edit complete callback executed successfully');
        } catch (e) {
          print(
              'EditCategoryScreen: Error executing edit complete callback: $e');
        }
      } else {
        print('EditCategoryScreen: No edit complete callback available');
      }

      // Navigate back to home screen
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        print('EditCategoryScreen: Navigated back to home screen');
      }
    } catch (e) {
      print('EditCategoryScreen: Error deleting category: $e');
      setState(() {
        _isLoading = false;
      });

      // Show error message to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting category: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        print('EditCategoryScreen: WillPopScope triggered');
        _handleBack();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              print('EditCategoryScreen: Back button pressed in app bar');
              _handleBack();
            },
          ),
          title: Text(
            widget.category == null
                ? 'New ${NamingUtils.categoriesName()}'
                : 'Edit ${NamingUtils.categoriesName()}',
          ),
          actions: [
            if (widget.category != null && !_editTasksLocal && _isEditing)
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  // Reset controllers to current values
                  _headlineController.text = widget.category!.headline;
                  _invitationController.text =
                      widget.category!.invitation ?? '';
                  setState(() {
                    _isEditing = false;
                  });
                },
                tooltip: 'Cancel edit',
              ),
            // Refresh button for existing categories
            if (widget.category != null && !_editTasksLocal)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _isLoading
                    ? null
                    : () {
                        // No cache refresh needed, just rebuild UI
                        if (mounted) {
                          setState(() {});
                        }
                      },
                tooltip: 'Refresh ${NamingUtils.tasksName(plural: true)}',
              ),
            // Only show category delete button for authenticated users
            if (widget.category != null &&
                !_editTasksLocal &&
                !AuthUtils.isGuestUser())
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: _isLoading
                    ? null
                    : () {
                        // TODO: Implement category deletion
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title:
                                Text('Delete ${NamingUtils.categoriesName()}?'),
                            content: Text(
                              'This will also delete all ${NamingUtils.tasksName(plural: true)} in this category. This action cannot be undone.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  Navigator.pop(context);
                                  await _deleteCategory();
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                      },
                tooltip:
                    'Delete ${NamingUtils.categoriesName(capitalize: false, plural: false)}',
              ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              if (_editTasksLocal && widget.category != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.category!.headline,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit details',
                      onPressed: () {
                        setState(() {
                          _editTasksLocal = false;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (widget.category!.invitation != null)
                  Text(
                    widget.category!.invitation!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                const SizedBox(height: 16),
              ] else ...[
                // Category form section
                // This section is now purely for display and cannot save/edit
                // The actual editing logic is handled by the main app's category list
                // or a separate edit screen if needed.
                // For now, we just display the current category's details.
                if (widget.category != null) ...[
                  Text(
                    'Current ${NamingUtils.categoriesName()}:',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.category!.headline,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (widget.category!.invitation != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.category!.invitation!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                ] else ...[
                  // If no category is selected, show a placeholder
                  Center(
                    child: Text(
                      'Select a ${NamingUtils.categoriesName(capitalize: false, plural: false)} from the list on the left to edit its details.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ],
              ],

              // Show tasks section for both new and existing categories
              const SizedBox(height: 6),

              // Task list section (only for saved categories)
              if (_categorySaved &&
                  (widget.category != null || _currentCategory != null)) ...[
                // Task summary (only for existing categories with tasks)

                // Only show "Current tasks:" header if there are tasks
                if (widget.category == null
                    ? _tasks.isNotEmpty
                    : _tasks.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.category == null
                            ? '${_tasks.length} Available ${NamingUtils.tasksName(plural: true)}:'
                            : _buildTaskCountText(),
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green),
                      ),
                      IconButton(
                        onPressed: _createTask,
                        icon: const Icon(Icons.add),
                        tooltip:
                            'Add a ${NamingUtils.tasksName(capitalize: false, plural: false)} manually',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
                if (widget.category == null ? _tasks.isEmpty : _tasks.isEmpty)
                  Center(
                    child: Column(
                      children: [
                        Text(
                          'No ${NamingUtils.tasksName(plural: true)} yet.',
                          style: TextStyle(fontSize: 16),
                        ),
                        if (widget.category != null) ...[
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _createTask,
                            icon: const Icon(Icons.add),
                            label: Text('Add a ${NamingUtils.tasksName()}'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 8),
                          Text(
                            'Add some ${NamingUtils.tasksName(plural: true)} above to get started!',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ],
                    ),
                  )
                else
                  widget.category == null
                      ? _buildNewTaskList()
                      : _buildTaskList(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
