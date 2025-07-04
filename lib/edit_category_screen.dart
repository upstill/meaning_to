import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:file_selector/file_selector.dart';
import 'dart:convert';
import 'package:meaning_to/widgets/link_display.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:meaning_to/utils/link_processor.dart';
import 'package:http/http.dart' as http;
import 'package:meaning_to/utils/link_extractor.dart';
import 'package:meaning_to/import_justwatch_screen.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/widgets/task_display.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/text_importer.dart';
import 'package:meaning_to/add_tasks_screen.dart';
import 'package:meaning_to/widgets/category_form.dart';

class EditCategoryScreen extends StatefulWidget {
  static VoidCallback? onEditComplete; // Static callback for edit completion

  final Category? category; // null for new category, existing category for edit
  final bool tasksOnly;

  // Remove onComplete from constructor since we'll use static callback
  EditCategoryScreen({super.key, this.category, this.tasksOnly = false});

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

class EditCategoryScreenState extends State<EditCategoryScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _headlineController = TextEditingController();
  final _invitationController = TextEditingController();
  bool _isLoading = false;
  bool _editTasksLocal = false;
  bool _isEditing = false;
  bool _categorySaved = false; // Track if category has been saved
  bool _isPrivate = false; // Private flag for categories
  List<Task> _newTasks = []; // For new categories
  Category?
      _currentCategory; // Track the current category (for new categories after creation)

  // Add a getter for tasks from the cache
  List<Task> get _tasks => CacheManager().currentTasks ?? [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    print('EditCategoryScreen: initState called');
    print(
        'EditCategoryScreen: Static callback available: ${EditCategoryScreen.onEditComplete != null}');
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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // No cache refresh needed - tasks are loaded via getter
  }

  @override
  void didUpdateWidget(EditCategoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // No cache refresh needed - tasks are loaded via getter
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _headlineController.dispose();
    _invitationController.dispose();
    super.dispose();
  }

  Future<void> _saveCategory() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final userId = AuthUtils.getCurrentUserId();
      if (userId == null) throw Exception('No user logged in');

      final data = {
        'headline': _headlineController.text,
        'invitation': _invitationController.text.isEmpty
            ? null
            : _invitationController.text,
        'owner_id': userId,
        'original_id': null, // Custom categories should have null original_id
        'private': _isPrivate,
      };

      if (widget.category == null) {
        // Create new category
        print('Creating new category...');
        final response =
            await supabase.from('Categories').insert(data).select().single();

        final newCategory = Category.fromJson(response);
        print('Created new category: ${newCategory.headline}');

        // Save any tasks that were created
        if (_newTasks.isNotEmpty) {
          print('Saving ${_newTasks.length} tasks for new category...');
          for (final task in _newTasks) {
            final taskData = {
              'headline': task.headline,
              'notes': task.notes,
              'category_id': newCategory.id,
              'owner_id': userId,
              'links': task.links,
            };
            await supabase.from('Tasks').insert(taskData);
          }
        }

        // For new categories, update the widget's category reference and switch to view mode
        if (mounted) {
          setState(() {
            // Store the new category locally and switch to view mode
            _currentCategory = newCategory;
            _categorySaved = true;
            _isLoading = false;
            _isEditing = false; // Switch to view mode
          });
        }
      } else {
        // Update existing category
        print('Updating existing category...');
        final response = await supabase
            .from('Categories')
            .update(data)
            .eq('id', widget.category!.id)
            .eq('owner_id', userId)
            .select()
            .single();

        // Update the category in memory with the response data
        final updatedCategory = Category.fromJson(response);
        widget.category!.headline = updatedCategory.headline;
        widget.category!.invitation = updatedCategory.invitation;
        print('Updated category: ${widget.category!.headline}');

        // Call the edit complete callback to update home screen
        if (EditCategoryScreen.onEditComplete != null) {
          print('EditCategoryScreen: Calling edit complete callback');
          try {
            EditCategoryScreen.onEditComplete!();
            print(
              'EditCategoryScreen: Edit complete callback executed successfully',
            );
          } catch (e) {
            print(
              'EditCategoryScreen: Error executing edit complete callback: $e',
            );
          }
        } else {
          print('EditCategoryScreen: No edit complete callback available');
        }

        // Stay on the screen, just update the state
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isEditing = false; // Return to view mode
          });
        }
      }
    } catch (e) {
      print('Error saving category: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _editTask(Task task) async {
    final currentCategory = widget.category ?? _currentCategory;
    if (currentCategory == null) {
      // For new categories, show error message - category must be saved first
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please save the category first before editing tasks',
            ),
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
        // Refresh the cache to get the new task
        try {
          final userId = AuthUtils.getCurrentUserId();
          if (userId != null) {
            await CacheManager().refreshFromDatabase();
            print('EditCategoryScreen: Cache refreshed after task creation');
          }
        } catch (e) {
          print('EditCategoryScreen: Error refreshing cache: $e');
        }
        setState(() {});
      }
    }
  }

  /// Check if a task with the same headline already exists and merge information if needed
  Future<Task?> _checkForDuplicateAndMerge(
      Task newTask, List<Task> existingTasks) async {
    final existingTask = existingTasks.firstWhere(
      (task) =>
          task.headline.toLowerCase().trim() ==
          newTask.headline.toLowerCase().trim(),
      orElse: () => newTask, // Return the new task if no duplicate found
    );

    if (existingTask.id != newTask.id) {
      // Found a duplicate - merge information
      print('Found duplicate task: "${newTask.headline}"');

      // Check if we need to update the existing task with new information
      bool needsUpdate = false;
      Map<String, dynamic> updateData = {};

      // Add links if the new task has them and the existing task doesn't
      if (newTask.links != null &&
          newTask.links!.isNotEmpty &&
          (existingTask.links == null || existingTask.links!.isEmpty)) {
        updateData['links'] = newTask.links;
        needsUpdate = true;
        print('  -> Adding links to existing task');
      }

      // Add notes if the new task has them and the existing task doesn't
      if (newTask.notes != null &&
          newTask.notes!.isNotEmpty &&
          (existingTask.notes == null || existingTask.notes!.isEmpty)) {
        updateData['notes'] = newTask.notes;
        needsUpdate = true;
        print('  -> Adding notes to existing task');
      }

      // Update the existing task if needed
      if (needsUpdate) {
        try {
          final userId = AuthUtils.getCurrentUserId();
          if (userId == null) throw Exception('No user logged in');

          await supabase
              .from('Tasks')
              .update(updateData)
              .eq('id', existingTask.id)
              .eq('owner_id', userId);

          print('  -> Updated existing task with new information');

          // Return the updated existing task
          return Task(
            id: existingTask.id,
            categoryId: existingTask.categoryId,
            ownerId: existingTask.ownerId,
            headline: existingTask.headline,
            notes: updateData['notes'] ?? existingTask.notes,
            links: updateData['links'] ?? existingTask.links,
            processedLinks: existingTask.processedLinks,
            createdAt: existingTask.createdAt,
            suggestibleAt: existingTask.suggestibleAt,
            finished: existingTask.finished,
          );
        } catch (e) {
          print('Error updating existing task: $e');
        }
      }

      return existingTask; // Return existing task without changes
    }

    return null; // No duplicate found
  }

  Future<void> _createTask() async {
    final currentCategory = widget.category ?? _currentCategory;
    if (currentCategory == null) {
      // For new categories, show error message - category must be saved first
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please save the category first before adding tasks',
            ),
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
        // Refresh the cache to get the new task
        try {
          final userId = AuthUtils.getCurrentUserId();
          if (userId != null) {
            await CacheManager().refreshFromDatabase();
            print('EditCategoryScreen: Cache refreshed after task creation');
          }
        } catch (e) {
          print('EditCategoryScreen: Error refreshing cache: $e');
        }
        setState(() {});
      }
    }
  }

  Future<String?> _getJustWatchTitle(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        print('Error fetching JustWatch page: ${response.statusCode}');
        return null;
      }

      final document = html_parser.parse(response.body);
      final titleElement = document.querySelector(
        'h1.title-detail-hero__details__title',
      );
      if (titleElement != null) {
        // Get only the direct text nodes, ignoring text from child elements
        final directText = titleElement.nodes
            .where((node) => node.nodeType == 3) // 3 is the value for TEXT_NODE
            .map((node) => node.text?.trim())
            .where((text) => text != null && text.isNotEmpty)
            .join(' ')
            .trim();

        return directText.isEmpty ? null : directText;
      }
      return null;
    } catch (e) {
      print('Error fetching JustWatch title: $e');
      return null;
    }
  }

  void _handleBack() {
    print('EditCategoryScreen: Back button pressed');
    print('EditCategoryScreen: Current category: ${widget.category?.headline}');
    print(
      'EditCategoryScreen: Static callback available: ${EditCategoryScreen.onEditComplete != null}',
    );

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
      Navigator.of(
        context,
      ).pop(true); // Always return true to indicate completion
      print('EditCategoryScreen: Popped screen with true result');
    } else {
      print('EditCategoryScreen: Widget not mounted, cannot pop');
    }
  }

  Future<void> _deleteTask(Task task) async {
    print(
      '=== Starting delete task for: ${task.headline} (ID: ${task.id}) ===',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Are you sure you want to delete "${task.headline}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      print('Delete cancelled by user');
      return;
    }

    try {
      // Use CacheManager to delete the task
      await CacheManager().removeTask(task.id);

      // Trigger a rebuild to reflect the changes
      setState(() {
        // No need to update _error as it's no longer used
      });

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

  /// Toggle task completion status
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

  /// Update task suggestibleAt time to current time (make available immediately)
  Future<void> _makeTaskAvailable(Task task) async {
    try {
      print(
          'EditCategoryScreen: _makeTaskAvailable called for task: ${task.headline}');
      print('EditCategoryScreen: Task ID: ${task.id}');

      // Use the existing CacheManager instance that's already initialized
      final cacheManager = CacheManager();
      print('EditCategoryScreen: CacheManager instance created');
      print(
          'EditCategoryScreen: CacheManager isInitialized: ${cacheManager.isInitialized}');

      if (!cacheManager.isInitialized) {
        print(
            'EditCategoryScreen: CacheManager not initialized, initializing now...');
        final userId = AuthUtils.getCurrentUserId();
        await cacheManager.initializeWithSavedCategory(
            widget.category!, userId);
      }

      // Test the database update first
      print('EditCategoryScreen: Testing database update...');
      await cacheManager.testDatabaseUpdate(task.id);

      print(
          'EditCategoryScreen: About to call cacheManager.reviveTask(${task.id})');
      await cacheManager.reviveTask(task.id);
      print('EditCategoryScreen: cacheManager.reviveTask completed');

      // Update the local task list to reflect the change
      final taskIndex = _tasks.indexWhere((t) => t.id == task.id);
      if (taskIndex != -1) {
        final updatedTask = cacheManager.currentTasks?.firstWhere(
          (t) => t.id == task.id,
          orElse: () => task,
        );
        if (updatedTask != null) {
          _tasks[taskIndex] = updatedTask;
        }
      }

      setState(() {}); // Trigger rebuild to reflect cache changes
      print('EditCategoryScreen: Task made available successfully');
    } catch (e) {
      print('Error making task available: $e');
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

  Widget _buildTaskList() {
    if (_tasks.isEmpty) {
      print('EditCategoryScreen: No tasks to display');
      return const Center(child: Text('No tasks yet. Add one to get started!'));
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
    if (_newTasks.isEmpty) {
      print('EditCategoryScreen: No new tasks to display');
      return const Center(child: Text('No tasks yet. Add one to get started!'));
    }

    print(
        'EditCategoryScreen: Building new task list with ${_newTasks.length} tasks');

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _newTasks.length,
      itemBuilder: (context, index) {
        final task = _newTasks[index];
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
                  onPressed: () => _editNewTask(task),
                  tooltip: 'Edit task',
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => _removeNewTask(index),
                  tooltip: 'Remove task',
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
          title: const Text('Edit Task'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: headlineController,
                decoration: const InputDecoration(
                  labelText: 'Task Title',
                  border: OutlineInputBorder(),
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
                final taskIndex = _newTasks.indexWhere((t) => t.id == task.id);
                if (taskIndex != -1) {
                  setState(() {
                    _newTasks[taskIndex] = Task(
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
      _newTasks.removeAt(index);
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
    final tasks = _tasks
        .where((task) =>
            task.categoryId == (widget.category?.id ?? _currentCategory?.id))
        .toList();

    final availableTasks =
        tasks.where((task) => !task.finished && task.isSuggestible).length;
    final deferredTasks =
        tasks.where((task) => !task.finished && task.isDeferred).length;
    final finishedTasks = tasks.where((task) => task.finished).length;

    if (availableTasks == 0) {
      final parts = <String>[];
      if (deferredTasks > 0) parts.add('$deferredTasks Deferred');
      if (finishedTasks > 0) parts.add('$finishedTasks Finished');

      if (parts.isEmpty) {
        return 'No Tasks On Deck';
      }
      return 'No Tasks On Deck (${parts.join(', ')})';
    }

    final parts = <String>[];
    if (deferredTasks > 0) parts.add('$deferredTasks Deferred');
    if (finishedTasks > 0) parts.add('$finishedTasks Finished');

    final taskText = availableTasks == 1 ? 'Task Is Up' : 'Available Tasks';
    final availableText =
        availableTasks == 1 ? 'Only One' : availableTasks.toString();

    if (parts.isEmpty) {
      return '$availableText $taskText';
    }
    return '$availableText $taskText (${parts.join(', ')})';
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
            widget.category == null ? 'New Endeavor' : 'Edit Endeavor',
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
                            title: const Text('Delete Endeavor?'),
                            content: const Text(
                              'This will also delete all tasks in this category. This action cannot be undone.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () {
                                  // TODO: Implement deletion
                                  Navigator.pop(context);
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
                tooltip: 'Delete endeavor',
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
                CategoryForm(
                  category: widget.category ?? _currentCategory,
                  isEditing: _isEditing || widget.category == null,
                  isLoading: _isLoading,
                  onSave: (headline, invitation, isPrivate) async {
                    // Update local state
                    _headlineController.text = headline;
                    _invitationController.text = invitation;
                    _isPrivate = isPrivate;

                    // Save the category
                    await _saveCategory();

                    // Switch to view mode for existing categories
                    if (widget.category != null) {
                      setState(() {
                        _isEditing = false;
                      });
                    }
                  },
                  onEdit: () {
                    setState(() {
                      _isEditing = true;
                    });
                  },
                  onCancel: () {
                    // Reset controllers to current values
                    _headlineController.text =
                        (widget.category ?? _currentCategory)!.headline;
                    _invitationController.text =
                        (widget.category ?? _currentCategory)!.invitation ?? '';
                    _isPrivate =
                        (widget.category ?? _currentCategory)!.isPrivate;
                    setState(() {
                      _isEditing = false;
                    });
                  },
                ),
              ],

              // Import JustWatch button (only for view mode and specific categories)
              if (!_isEditing &&
                  (widget.category != null || _currentCategory != null) &&
                  ((widget.category ?? _currentCategory)!.originalId == 1 ||
                      (widget.category ?? _currentCategory)!.originalId ==
                          2)) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    print('Import JustWatch button pressed');
                    print(
                        'Category: ${(widget.category ?? _currentCategory)?.headline}');

                    // Navigate to Import JustWatch screen, replacing the current screen
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ImportJustWatchScreen(
                          category: (widget.category ?? _currentCategory)!,
                        ),
                      ),
                    ).then((result) {
                      if (result is Category) {
                        setState(() {
                          widget.category!.headline = result.headline;
                          widget.category!.invitation = result.invitation;
                        });
                      }
                    });
                  },
                  icon: const Icon(Icons.movie),
                  label: const Text('Import JustWatch list'),
                ),
              ],
              // Show tasks section for both new and existing categories
              const SizedBox(height: 6),

              // Task list section (only for saved categories)
              if (_categorySaved &&
                  (widget.category != null || _currentCategory != null)) ...[
                // Task summary (only for existing categories with tasks)

                // Only show "Current tasks:" header if there are tasks
                if (widget.category == null
                    ? _newTasks.isNotEmpty
                    : _tasks.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.category == null
                            ? '${_newTasks.length} Available tasks:'
                            : _buildTaskCountText(),
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green),
                      ),
                      IconButton(
                        onPressed: _createTask,
                        icon: const Icon(Icons.add),
                        tooltip: 'Add a task manually',
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
                if (widget.category == null
                    ? _newTasks.isEmpty
                    : _tasks.isEmpty)
                  Center(
                    child: Column(
                      children: [
                        const Text(
                          'No tasks yet.',
                          style: TextStyle(fontSize: 16),
                        ),
                        if (widget.category != null) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'See above to get started',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ] else ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Add some tasks above to get started!',
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
