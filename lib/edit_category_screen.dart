import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/widgets/task_display.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/app_buttons.dart';
import 'package:meaning_to/widgets/category_form.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/add_tasks_screen.dart';
import 'package:meaning_to/shop_endeavors_screen.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

class EditCategoryScreen extends StatefulWidget {
  static VoidCallback? onEditComplete; // Static callback for edit completion
  static VoidCallback?
      onImportComplete; // Static callback for import completion

  final Category? category; // null for new category, existing category for edit
  final bool tasksOnly;
  final bool startInCategoryEditorPanel;

  const EditCategoryScreen({
    super.key,
    this.category,
    this.tasksOnly = false,
    this.startInCategoryEditorPanel = false,
  });

  // Add a factory constructor to handle arguments from Navigator
  static Route routeFromArgs(RouteSettings settings) {
    final args = settings.arguments as Map<String, dynamic>?;
    return MaterialPageRoute(
      builder: (_) => EditCategoryScreen(
        category: args?['category'] as Category?,
        tasksOnly: args?['tasksOnly'] == true,
        startInCategoryEditorPanel: args?['startInCategoryEditorPanel'] == true,
      ),
      settings: settings,
    );
  }

  @override
  EditCategoryScreenState createState() => EditCategoryScreenState();
}

// Sorting options for tasks
enum SortOption { alphabetical, priority, age }

class EditCategoryScreenState extends State<EditCategoryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _headlineController = TextEditingController();
  final _invitationController = TextEditingController();
  final _searchController = TextEditingController();
  bool _isLoading = false;
  bool _editTasksLocal = false;
  bool _isEditing = false;
  bool _categorySaved = false; // Track if category has been saved
  bool _isPrivate = false; // Private flag for categories
  bool _tasksArePrivate = true; // Tasks are private flag for categories
  bool _isSearching = false; // Track if search is in progress
  bool _showCategoryEditorPanel = false;
  Category?
      _currentCategory; // Track the current category (for new categories after creation)
  StreamSubscription<void>? _cacheSubscription;
  bool _ignoringCacheChanges = false;

  Future<void> _toggleCategoryPrivacy() async {
    final currentCategory = widget.category ?? _currentCategory;
    if (currentCategory == null) {
      return;
    }

    if (AuthUtils.isGuestUser()) {
      _showGuestSignupDialog(
        content:
            'Here\'s where you can change whether your ${NamingUtils.categoriesName(plural: false, withArticle: true)} is private once you\'re logged in.',
      );
      return;
    }

    if (_isLoading) return;

    final nextValue = !_isPrivate;

    // Optimistic UI update
    setState(() {
      _isPrivate = nextValue;
      if (widget.category != null) {
        widget.category!.isPrivate = nextValue;
      } else if (_currentCategory != null) {
        _currentCategory!.isPrivate = nextValue;
      }

      final cached = CacheManager().currentCategory;
      if (cached != null && cached.id == currentCategory.id) {
        cached.isPrivate = nextValue;
      }
    });

    try {
      await supabase
          .from('Categories')
          .update({'private': nextValue})
          .eq('id', currentCategory.id)
          .select()
          .single();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              nextValue ? 'Pursuit is now private.' : 'Pursuit is now public.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Revert UI on error
      if (mounted) {
        setState(() {
          _isPrivate = !nextValue;
          if (widget.category != null) {
            widget.category!.isPrivate = !nextValue;
          } else if (_currentCategory != null) {
            _currentCategory!.isPrivate = !nextValue;
          }

          final cached = CacheManager().currentCategory;
          if (cached != null && cached.id == currentCategory.id) {
            cached.isPrivate = !nextValue;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating privacy: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Sorting options
  SortOption _currentSortOption = SortOption.priority;

  void _setSortOption(SortOption value) {
    if (_currentSortOption == value) return;
    setState(() {
      _currentSortOption = value;
      _clearTaskCache();
    });
  }

  // Method to switch to age sorting (for use after import)
  void switchToAgeSorting() {
    if (mounted) {
      setState(() {
        _currentSortOption = SortOption.age;
        _clearTaskCache();
      });
    }
  }

  // Cached sorted tasks to avoid repeated sorting
  List<Task>? _cachedSortedTasks;
  List<Task>? _lastCachedTasks;

  // Progressive loading state
  bool _isLoadingProgressively = false;
  int _displayedTaskCount = 0;
  static const int _initialTaskCount = 12;
  static const int _batchSize = 20;

  // Get unfiltered tasks count for UI decisions
  int get _unfilteredTaskCount {
    final allTasks = CacheManager().currentTasks ?? [];
    final currentCategoryId = widget.category?.id ?? _currentCategory?.id;
    return allTasks
        .where((task) => task.categoryId == currentCategoryId)
        .length;
  }

  // Pure UI getter for tasks from the cache
  List<Task> get _tasks {
    final allTasks = CacheManager().currentTasks ?? [];
    final currentCategoryId = widget.category?.id ?? _currentCategory?.id;

    // Filter tasks to only show tasks for the current category
    var tasks =
        allTasks.where((task) => task.categoryId == currentCategoryId).toList();

    // Apply search filtering if search query is not empty
    final searchQuery = _searchController.text.trim().toLowerCase();
    if (searchQuery.isNotEmpty) {
      tasks = tasks.where((task) {
        return task.headline.toLowerCase().contains(searchQuery);
      }).toList();
    }

    // Always re-sort if the task list has changed (check by length and content)
    bool shouldResort = _cachedSortedTasks == null ||
        _lastCachedTasks == null ||
        _lastCachedTasks!.length != tasks.length ||
        !_haveSameTaskIds(_lastCachedTasks!, tasks);

    if (shouldResort) {
      _lastCachedTasks = List.from(tasks); // Create a copy
      _cachedSortedTasks = _sortTasks(tasks);
      // Reset progressive loading when task list changes
      _displayedTaskCount = 0;
      _isLoadingProgressively = false;
    }

    return _cachedSortedTasks!;
  }

  // Helper method to check if two task lists have the same task IDs (order independent)
  bool _haveSameTaskIds(List<Task> list1, List<Task> list2) {
    if (list1.length != list2.length) return false;

    final ids1 = list1.map((task) => task.id).toSet();
    final ids2 = list2.map((task) => task.id).toSet();

    return ids1.length == ids2.length && ids1.containsAll(ids2);
  }

  // Get tasks for progressive loading
  List<Task> get _displayedTasks {
    final allTasks = _tasks;

    if (_displayedTaskCount == 0) {
      // Only use progressive loading for large task lists (>50 tasks)
      // For smaller lists, show all tasks immediately to avoid flicker
      if (allTasks.length > 50) {
        _displayedTaskCount = _initialTaskCount;
        _startProgressiveLoading();
      } else {
        _displayedTaskCount = allTasks.length;
      }
    }
    final result = allTasks.take(_displayedTaskCount).toList();
    return result;
  }

  /// Sort tasks based on the current sort option
  List<Task> _sortTasks(List<Task> tasks) {
    switch (_currentSortOption) {
      case SortOption.alphabetical:
        return tasks
          ..sort((a, b) =>
              a.headline.toLowerCase().compareTo(b.headline.toLowerCase()));
      case SortOption.priority:
        return tasks
          ..sort((a, b) {
            // First, sort by finished status (unfinished first)
            if (a.finished != b.finished) {
              return a.finished ? 1 : -1;
            }
            // Then, sort by suggestibleAt (earlier first, null first)
            if (a.suggestibleAt == null && b.suggestibleAt == null) {
              // Both have null suggestibleAt - sort by creation date (newest first)
              return b.createdAt.compareTo(a.createdAt);
            }
            if (a.suggestibleAt == null) {
              return -1;
            }
            if (b.suggestibleAt == null) {
              return 1;
            }
            return a.suggestibleAt!.compareTo(b.suggestibleAt!);
          });
      case SortOption.age:
        return tasks
          ..sort((a, b) {
            // Sort by creation date (newest first)
            return b.createdAt.compareTo(a.createdAt);
          });
    }
  }

  /// Clear the task cache when sort option changes
  void _clearTaskCache() {
    _cachedSortedTasks = null;
    _lastCachedTasks = null;
    _displayedTaskCount = 0; // Reset display count so it will be recalculated
  }

  /// Start progressive loading of tasks
  void _startProgressiveLoading() {
    if (_isLoadingProgressively) return;

    _isLoadingProgressively = true;
    _loadMoreTasks();
  }

  /// Load more tasks progressively
  Future<void> _loadMoreTasks() async {
    final allTasks = _tasks;

    while (_displayedTaskCount < allTasks.length && _isLoadingProgressively) {
      await Future.delayed(
          const Duration(milliseconds: 50)); // Small delay between batches

      if (mounted) {
        setState(() {
          _displayedTaskCount =
              (_displayedTaskCount + _batchSize).clamp(0, allTasks.length);
        });
      }
    }

    _isLoadingProgressively = false;
  }

  @override
  void initState() {
    super.initState();

    _headlineController.text = widget.category?.headline ?? '';
    _invitationController.text = widget.category?.invitation ?? '';
    _isPrivate = widget.category?.isPrivate ?? false;
    _tasksArePrivate = widget.category?.tasksArePrivate ?? true;
    _editTasksLocal = widget.tasksOnly;
    _showCategoryEditorPanel = widget.startInCategoryEditorPanel;
    if (_showCategoryEditorPanel) {
      _editTasksLocal = false;
      _isEditing = true;
    }

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
      if (mounted && !_ignoringCacheChanges) {
        // Force task list re-evaluation so field changes (e.g., shared) are reflected
        _clearTaskCache();
        setState(() {});

        // Check if this was triggered by an import
        if (EditCategoryScreen.onImportComplete != null) {
          // Don't switch sorting - newly imported tasks with null suggestibleAt
          // will appear at the top in Priority sorting automatically
          EditCategoryScreen.onImportComplete!();
          EditCategoryScreen.onImportComplete = null;
        }
      }
    });

    // Initialize cache if category is provided
    if (widget.category != null) {
      _initializeCache();
    }
  }

  /// Initialize the cache with the current category
  Future<void> _initializeCache() async {
    try {
      final cacheManager = CacheManager();
      await cacheManager.initializeWithSavedCategory(
          widget.category!, AuthUtils.getCurrentUserId());

      // Check if there's a mismatch
      if (cacheManager.currentCategory?.id != widget.category!.id) {}
    } catch (e) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only refresh cache if we haven't already initialized for this category
    if (widget.category != null &&
        _currentCategory?.id != widget.category!.id) {
      _refreshCacheIfNeeded();
    }
  }

  /// Smart refresh that can skip database calls when appropriate
  Future<void> _refreshCacheIfNeeded() async {
    final cacheManager = CacheManager();

    // Only refresh if we're switching to a different category or cache is empty
    if (cacheManager.currentCategory?.id != widget.category!.id ||
        cacheManager.currentTasks == null) {
      await cacheManager.initializeWithSavedCategory(
          widget.category!, AuthUtils.getCurrentUserId());
    } else {
      // Don't force refresh - cache is already current
    }
  }

  @override
  void dispose() {
    _headlineController.dispose();
    _invitationController.dispose();
    _cacheSubscription?.cancel();
    // Clear any pending import callbacks
    EditCategoryScreen.onImportComplete = null;
    super.dispose();
  }

  // Pure UI method - no database operations
  void _handleBack() {
    // Call the static callback before popping
    if (EditCategoryScreen.onEditComplete != null) {
      try {
        EditCategoryScreen.onEditComplete!();
      } catch (e) {}
    } else {}

    // Pop after executing the callback
    if (mounted) {
      Navigator.of(context)
          .pop(true); // Always return true to indicate completion
    } else {}
  }

  // Pure UI method - no database operations
  Future<void> _editTask(Task task) async {
    // Check if user is guest
    if (AuthUtils.isGuestUser()) {
      _showGuestSignupDialog(
        content:
            'Here\'s where you can revise ${NamingUtils.tasksName(plural: false, withArticle: true)} once you\'ve signed in. \nSign up to create your own ${NamingUtils.categoriesName()} and ${NamingUtils.tasksName()}!',
      );
      return;
    }

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
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  // Pure UI method - no database operations
  Future<void> _createTask() async {
    // Check if user is guest
    if (AuthUtils.isGuestUser()) {
      _showGuestSignupDialog(
        content:
            'Here\'s where you can add ${NamingUtils.tasksName(plural: false, withArticle: true)} once you\'re signed in. Sign up to create your own ${NamingUtils.categoriesName()} and ${NamingUtils.tasksName()}!',
      );
      return;
    }

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

      // Handle both map result (from NewContentScreen) and boolean result (from TaskEditScreen)
      if (result == true || (result is Map && result.containsKey('task'))) {
        // Tasks were added, trigger UI rebuild to reflect cache changes
        if (mounted) {
          _clearTaskCache(); // Force cache refresh
          setState(() {});
        }
      }
    }
  }

  String _getDefaultGuestMessage() {
    return 'Here\'s where you can add a new ${NamingUtils.categoriesName(plural: false)} once you\'re logged in. Sign up to create your own ${NamingUtils.categoriesName()} and ${NamingUtils.tasksName()}!';
  }

  void _showGuestSignupDialog({required String content}) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('No Changes in Guest Mode'),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushNamed(context, '/auth');
              },
              child: const Text('Sign Up'),
            ),
          ],
        );
      },
    );
  }

  // Pure UI method - no database operations
  Future<void> _deleteTask(Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Are you sure you want to delete "${task.headline}"?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, false);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, true);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      // Set flag to ignore cache changes during deletion
      _ignoringCacheChanges = true;

      // Use CacheManager to delete the task first
      await CacheManager().removeTask(task.id);

      // Clear cached tasks and update the UI immediately
      setState(() {
        _clearTaskCache();
      });
    } catch (e) {
      // If there's an error, re-enable cache change listening and reload
      _ignoringCacheChanges = false;
      _clearTaskCache();
      setState(() {});

      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // Always re-enable cache change listening after a delay
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _ignoringCacheChanges = false;
        }
      });
    }
  }

  // Pure UI method - optimistic update with async database save
  void _toggleTaskCompletion(Task task) {
    // Ignore cache changes while updating finished state to avoid unnecessary reloads
    _ignoringCacheChanges = true;

    final newFinishedState = !task.finished;

    // Create updated task with new finished state immediately (optimistic update)
    final updatedTask = Task(
      id: task.id,
      categoryId: task.categoryId,
      headline: task.headline,
      notes: task.notes,
      ownerId: task.ownerId,
      createdAt: task.createdAt,
      suggestibleAt: task.suggestibleAt,
      triggersAt: task.triggersAt,
      deferral: task.deferral,
      links: task.links,
      processedLinks: task.processedLinks,
      finished: newFinishedState,
      shared: task.shared,
      dirty: task.dirty,
    );

    // Update the task in the sorted cache directly to avoid scroll reset
    if (_cachedSortedTasks != null) {
      final index = _cachedSortedTasks!.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        _cachedSortedTasks![index] = updatedTask;
      }
    }

    // Also update _lastCachedTasks to keep them in sync
    if (_lastCachedTasks != null) {
      final index = _lastCachedTasks!.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        _lastCachedTasks![index] = updatedTask;
      }
    }

    // Update UI immediately - note: with large task lists this rebuild can be slow
    setState(() {});

    // Save to database asynchronously (don't await)
    _saveTaskFinishedToDatabase(task.id, newFinishedState).then((_) {
      // Re-enable cache change listening after save completes
      if (mounted) {
        _ignoringCacheChanges = false;
      }
    }).catchError((_) {
      // Re-enable even on error
      if (mounted) {
        _ignoringCacheChanges = false;
      }
    });
  }

  // Background database save - updates database directly without triggering cache notifications
  Future<void> _saveTaskFinishedToDatabase(
      int taskId, bool newFinishedState) async {
    try {
      // Update only the finished column in database - minimal, fast operation
      await ApiClient.updateTaskFinished(taskId, newFinishedState);

      // Update the task in the main cache silently (without triggering notifications)
      final cacheManager = CacheManager();
      final allTasks = cacheManager.currentTasks;
      if (allTasks != null) {
        final taskIndex = allTasks.indexWhere((t) => t.id == taskId);
        if (taskIndex != -1) {
          final task = allTasks[taskIndex];
          // Update the task in cache with clean (non-dirty) state since we just saved to DB
          final cleanTask = Task(
            id: task.id,
            categoryId: task.categoryId,
            headline: task.headline,
            notes: task.notes,
            ownerId: task.ownerId,
            createdAt: task.createdAt,
            suggestibleAt: task.suggestibleAt,
            triggersAt: task.triggersAt,
            deferral: task.deferral,
            links: task.links,
            processedLinks: task.processedLinks,
            finished: newFinishedState,
            shared: task.shared,
            dirty: false, // Mark as clean since we just saved to database
          );
          allTasks[taskIndex] = cleanTask;
        }
      }

      print(
          'Edit Category: Task $taskId finished state saved to database: $newFinishedState');
    } catch (e) {
      print('Edit Category: Error saving finished state: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving finished state: $e'),
            backgroundColor: Colors.red,
          ),
        );
        // On error, force a refresh to revert to database state
        _clearTaskCache();
        setState(() {});
      }
    }
  }

  // Pure UI method - optimistic update with async database save
  void _toggleTaskShare(Task task, bool newSharedState) {
    // Ignore cache changes while updating share state to avoid unnecessary reloads
    _ignoringCacheChanges = true;

    // Create updated task with new share state immediately (optimistic update)
    final updatedTask = Task(
      id: task.id,
      categoryId: task.categoryId,
      headline: task.headline,
      notes: task.notes,
      ownerId: task.ownerId,
      createdAt: task.createdAt,
      suggestibleAt: task.suggestibleAt,
      triggersAt: task.triggersAt,
      deferral: task.deferral,
      links: task.links,
      processedLinks: task.processedLinks,
      finished: task.finished,
      shared: newSharedState,
      dirty: task.dirty,
    );

    // Update the task in the sorted cache directly to avoid scroll reset
    if (_cachedSortedTasks != null) {
      final index = _cachedSortedTasks!.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        _cachedSortedTasks![index] = updatedTask;
      }
    }

    // Also update _lastCachedTasks to keep them in sync
    if (_lastCachedTasks != null) {
      final index = _lastCachedTasks!.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        _lastCachedTasks![index] = updatedTask;
      }
    }

    // Update UI immediately - note: with large task lists this rebuild can be slow
    setState(() {});

    // Save to database asynchronously (don't await)
    _saveTaskShareToDatabase(task.id, newSharedState).then((_) {
      // Re-enable cache change listening after save completes
      if (mounted) {
        _ignoringCacheChanges = false;
      }
    }).catchError((_) {
      // Re-enable even on error
      if (mounted) {
        _ignoringCacheChanges = false;
      }
    });
  }

  // Background database save - updates database directly without triggering cache notifications
  Future<void> _saveTaskShareToDatabase(int taskId, bool newSharedState) async {
    try {
      // Update only the shared column in database - minimal, fast operation
      await ApiClient.updateTaskShared(taskId, newSharedState);

      // Update the task in the main cache silently (without triggering notifications)
      final cacheManager = CacheManager();
      final allTasks = cacheManager.currentTasks;
      if (allTasks != null) {
        final taskIndex = allTasks.indexWhere((t) => t.id == taskId);
        if (taskIndex != -1) {
          final task = allTasks[taskIndex];
          // Update the task in cache with clean (non-dirty) state since we just saved to DB
          final cleanTask = Task(
            id: task.id,
            categoryId: task.categoryId,
            headline: task.headline,
            notes: task.notes,
            ownerId: task.ownerId,
            createdAt: task.createdAt,
            suggestibleAt: task.suggestibleAt,
            triggersAt: task.triggersAt,
            deferral: task.deferral,
            links: task.links,
            processedLinks: task.processedLinks,
            finished: task.finished,
            shared: newSharedState,
            dirty: false, // Mark as clean since we just saved to database
          );
          allTasks[taskIndex] = cleanTask;
        }
      }

      print(
          'Edit Category: Task $taskId shared state saved to database: $newSharedState');
    } catch (e) {
      print('Edit Category: Error saving share state: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving share state: $e'),
            backgroundColor: Colors.red,
          ),
        );
        // On error, force a refresh to revert to database state
        _clearTaskCache();
        setState(() {});
      }
    }
  }

  // Pure UI method - no database operations
  Future<void> _makeCategoryPublic() async {
    try {
      final currentCategory = widget.category ?? _currentCategory;
      if (currentCategory == null) {
        return;
      }

      // Update in API
      await ApiClient.updateCategory(currentCategory.id.toString(), {
        'private': false,
      });

      // Update local state
      if (widget.category != null) {
        // Update the widget's category
        widget.category!.isPrivate = false;
      } else {
        // Update the current category
        _currentCategory = Category(
          id: currentCategory.id,
          headline: currentCategory.headline,
          invitation: currentCategory.invitation,
          ownerId: currentCategory.ownerId,
          createdAt: currentCategory.createdAt,
          isPrivate: false, // Make it public
          tasksArePrivate: currentCategory.tasksArePrivate,
        );
      }

      // Update the form state to reflect the change
      _isPrivate = false;

      setState(() {}); // Trigger rebuild to reflect changes

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pursuit is now public! You can share ideas.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error making pursuit public: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Pure UI method - no database operations
  Future<void> _makeTaskAvailable(Task task) async {
    try {
      // Use the existing CacheManager instance that's already initialized
      final cacheManager = CacheManager();

      await cacheManager.reviveTask(task.id);

      setState(() {}); // Trigger rebuild to reflect cache changes
    } catch (e) {
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

    if (result != null && mounted) {
      // Check if result is 'home' (go to home screen) or true (multiple tasks)
      if (result == 'home') {
        // User chose to go to home screen
        // Trigger UI rebuild to reflect cache changes
        setState(() {});

        // Call the edit complete callback to notify Home screen to refresh
        if (EditCategoryScreen.onEditComplete != null) {
          try {
            EditCategoryScreen.onEditComplete!();
          } catch (e) {}
        }

        // Navigate to home screen
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else if (result == true) {
        // Multiple tasks were added
        // Tasks were added, trigger UI rebuild to reflect cache changes
        setState(() {});

        // Call the edit complete callback to notify Home screen to refresh
        if (EditCategoryScreen.onEditComplete != null) {
          try {
            EditCategoryScreen.onEditComplete!();
          } catch (e) {}
        }
      }
      // If result is null, just refresh the UI (user chose to add more)
      else {
        setState(() {});

        // Call the edit complete callback
        if (EditCategoryScreen.onEditComplete != null) {
          try {
            EditCategoryScreen.onEditComplete!();
          } catch (e) {}
        }
      }
    }
  }

  Widget _buildTaskList() {
    if (_tasks.isEmpty) {
      return Center(
          child: Text(
              'No ${NamingUtils.tasksName(plural: true)} yet. Add one to get started!'));
    }

    return Column(
      children: _displayedTasks.map((task) {
        return TaskDisplay(
          key: ValueKey(
            'task-${task.id}',
          ), // Add a key to help Flutter track the widget
          task: task,
          withControls: true,
          onEdit: () => _editTask(task),
          onDelete: () => _deleteTask(task),
          onTap: () => _toggleTaskCompletion(task),
          onUpdateSuggestibleAt: (DateTime newTime) => _makeTaskAvailable(task),
          onShareToggle: (bool newSharedState) =>
              _toggleTaskShare(task, newSharedState),
          isCategoryPrivate: widget.category?.isPrivate ??
              _currentCategory?.isPrivate ??
              false,
          onMakeCategoryPublic: _makeCategoryPublic,
        );
      }).toList(),
    );
  }

  Widget _buildTaskListWithLoading() {
    return Column(
      children: [
        _buildTaskList(),
        if (_isLoadingProgressively && _displayedTaskCount < _tasks.length)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNewTaskList() {
    if (_tasks.isEmpty) {
      return Center(
          child: Text(
              'No ${NamingUtils.tasksName(plural: true)} yet. Add one to get started!'));
    }

    return Column(
      children: _displayedTasks.map((task) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            title: Text(task.headline),
            subtitle: task.notes != null
                ? Html(
                    data: task.notes!,
                    style: {
                      "body": Style(
                        fontSize: FontSize(14),
                        margin: Margins.zero,
                        padding: HtmlPaddings.zero,
                      ),
                      "a": Style(
                        color: Theme.of(context).colorScheme.primary,
                        textDecoration: TextDecoration.underline,
                      ),
                    },
                    onLinkTap: (url, _, __) async {
                      if (url != null) {
                        try {
                          bool launched = await launchUrl(
                            Uri.parse(url),
                            mode: LaunchMode.externalApplication,
                            webViewConfiguration: const WebViewConfiguration(
                              enableJavaScript: false,
                              enableDomStorage: false,
                            ),
                          );
                          if (!launched) {
                            await launchUrl(Uri.parse(url),
                                mode: LaunchMode.platformDefault);
                          }
                        } catch (e) {
                          print('Could not launch URL: $url');
                        }
                      }
                    },
                  )
                : null,
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
      }).toList(),
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

  String _buildNewCategoryTaskCountText() {
    final displayTasks = _tasks.length;

    return '$displayTasks Available ${NamingUtils.tasksName(plural: true)}';
  }

  String _buildAppBarTitle() {
    final currentCategory = widget.category ?? _currentCategory;

    if (currentCategory == null) {
      return 'New ${NamingUtils.categoriesName(plural: false)}';
    }

    final taskCount = _tasks.length;
    final taskWord = taskCount == 1
        ? NamingUtils.tasksName(plural: false)
        : NamingUtils.tasksName(plural: true);

    return '$taskCount $taskWord to ${currentCategory.headline}';
  }

  String _buildTaskCountText() {
    // Get total tasks from cache manager (before limiting)
    final allTasks = CacheManager().currentTasks ?? [];
    final totalTasks = allTasks
        .where((task) =>
            task.categoryId == (widget.category?.id ?? _currentCategory?.id))
        .toList();

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
        return 'No ${NamingUtils.tasksName(plural: true)} on deck';
      }
      return 'No ${NamingUtils.tasksName(plural: true)} on deck (${parts.join(', ')})';
    }

    final parts = <String>[];
    if (deferredTasks > 0) parts.add('$deferredTasks Deferred');
    if (finishedTasks > 0) parts.add('$finishedTasks Finished');

    final taskText = availableTasks == 1
        ? '${NamingUtils.tasksName(plural: false)} is up'
        : '${NamingUtils.tasksName(plural: true)} are ready to suggest';
    final availableText =
        availableTasks == 1 ? 'Only one' : availableTasks.toString();

    if (parts.isEmpty) {
      return '$availableText $taskText';
    }
    return '$availableText $taskText (${parts.join(', ')})';
  }

  // Save category changes to database
  Future<void> _saveCategory() async {
    if (widget.category == null) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final userId = AuthUtils.getCurrentUserId();
      final categoryId = widget.category!.id;

      final data = {
        'headline': _headlineController.text,
        'invitation': _invitationController.text.isEmpty
            ? null
            : _invitationController.text,
        'private': _isPrivate,
        'tasks_are_private': _tasksArePrivate,
      };

      // Update the category in the database
      final response = await supabase
          .from('Categories')
          .update(data)
          .eq('id', categoryId)
          .select()
          .single();

      final updatedCategory = Category.fromJson(response);

      // Update the widget's category with the new data
      widget.category!.headline = updatedCategory.headline;
      widget.category!.invitation = updatedCategory.invitation;
      widget.category!.isPrivate = updatedCategory.isPrivate;
      widget.category!.tasksArePrivate = updatedCategory.tasksArePrivate;

      setState(() {
        _isEditing = false;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${NamingUtils.categoriesName()} saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Error saving ${NamingUtils.categoriesName(capitalize: false, plural: false)}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveCategoryFromForm(
    String headline,
    String invitation,
    bool isPrivate,
    bool tasksArePrivate,
  ) async {
    _headlineController.text = headline;
    _invitationController.text = invitation;
    _isPrivate = isPrivate;
    _tasksArePrivate = tasksArePrivate;
    await _saveCategory();
  }

  Future<void> _shopForCategories() async {
    try {
      final dynamic result =
          await Navigator.pushNamed(context, '/shop-endeavors');
      if (result == true && mounted) {
        _handleBack();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening shop: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Delete category and all its tasks from database
  Future<void> _deleteCategory() async {
    if (widget.category == null) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final userId = AuthUtils.getCurrentUserId();
      final categoryId = widget.category!.id;

      // First, delete all tasks in this category
      final deleteTasksResponse = await supabase
          .from('Tasks')
          .delete()
          .eq('category_id', categoryId)
          .eq('owner_id', userId);

      // Then, delete the category itself
      final deleteCategoryResponse = await supabase
          .from('Categories')
          .delete()
          .eq('id', categoryId)
          .eq('owner_id', userId);

      // Clear the cache
      CacheManager().clearCache();

      // Call the edit complete callback to update home screen
      if (EditCategoryScreen.onEditComplete != null) {
        try {
          EditCategoryScreen.onEditComplete!();
        } catch (e) {}
      } else {}

      // Navigate back to home screen
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
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
        _handleBack();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              _handleBack();
            },
          ),
          title: Text(_buildAppBarTitle()),
          actions: [
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
                            title: Text(
                                'Delete the ${NamingUtils.categoriesName(plural: false)} "${widget.category!.headline}" and all its ${NamingUtils.tasksName(plural: true)}?'),
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
                    'Delete the ${NamingUtils.categoriesName(plural: false)} "${widget.category!.headline}" and all its ${NamingUtils.tasksName(plural: true)}',
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
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.category!.headline,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _isPrivate ? Icons.lock : Icons.lock_open,
                            ),
                            tooltip:
                                _isPrivate ? 'Make Public' : 'Make Private',
                            onPressed:
                                _isLoading ? null : _toggleCategoryPrivacy,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit details',
                      onPressed: () {
                        if (AuthUtils.isGuestUser()) {
                          _showGuestSignupDialog(
                            content:
                                'Here\'s where you can edit ${NamingUtils.categoriesName(plural: false, withArticle: true)} once you\'re logged in. Sign up to create your own ${NamingUtils.categoriesName()} and ${NamingUtils.tasksName()}!',
                          );
                          return;
                        }
                        setState(() {
                          _editTasksLocal = false;
                          _showCategoryEditorPanel = true;
                          _isEditing = true;
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
                if (widget.category != null && _showCategoryEditorPanel) ...[
                  CategoryForm(
                    category: widget.category,
                    isEditing: true,
                    isLoading: _isLoading,
                    showPrivacyOptions: false,
                    onSave: _saveCategoryFromForm,
                    onCancel: () {
                      setState(() {
                        _showCategoryEditorPanel = false;
                        _editTasksLocal = true;
                        _isEditing = false;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  const Center(
                    child: Text(
                      '** You can grab ideas from other people. **',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _shopForCategories,
                    icon: const Icon(Icons.shopping_cart),
                    label: Text(
                      'Shop for ${NamingUtils.categoriesName(capitalize: true)}',
                      style: const TextStyle(fontSize: 18),
                    ),
                    style: AppButtons.goForth().copyWith(
                      minimumSize: const WidgetStatePropertyAll(
                          Size(double.infinity, 50)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else if (widget.category != null) ...[
                  if (_isEditing) ...[
                    // Editable form when editing
                    TextFormField(
                      controller: _headlineController,
                      decoration: InputDecoration(
                        labelText: '${NamingUtils.categoriesName()} Name',
                        border: const OutlineInputBorder(),
                        suffixIcon: Tooltip(
                          message: _isPrivate ? 'Make Public' : 'Make Private',
                          child: IconButton(
                            icon: Icon(
                              _isPrivate ? Icons.lock : Icons.lock_open,
                            ),
                            onPressed:
                                _isLoading ? null : _toggleCategoryPrivacy,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a ${NamingUtils.categoriesName(capitalize: false, plural: false)} name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _invitationController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                        hintText: 'Add a description or invitation...',
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    if (!_isPrivate) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 16.0),
                        child: CheckboxListTile(
                          title: Text(
                              '${NamingUtils.tasksName(plural: true)} are private by default'),
                          value: _tasksArePrivate,
                          onChanged: (value) {
                            setState(() {
                              _tasksArePrivate = value ?? true;
                            });
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              // Reset controllers to current values
                              _headlineController.text =
                                  widget.category!.headline;
                              _invitationController.text =
                                  widget.category!.invitation ?? '';
                              setState(() {
                                _isPrivate = widget.category!.isPrivate;
                                _tasksArePrivate =
                                    widget.category!.tasksArePrivate;
                                _isEditing = false;
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[300],
                              foregroundColor: Colors.black,
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _saveCategory,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // Display mode when not editing
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      widget.category!.headline,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      _isPrivate ? Icons.lock : Icons.lock_open,
                                    ),
                                    tooltip: _isPrivate
                                        ? 'Make Public'
                                        : 'Make Private',
                                    onPressed: _isLoading
                                        ? null
                                        : _toggleCategoryPrivacy,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
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
                              if (_isPrivate) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.lock,
                                        size: 16, color: Colors.grey[600]),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Private ${NamingUtils.categoriesName(capitalize: false, plural: false)}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ] else if (widget.category!.tasksArePrivate) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.lock,
                                        size: 16, color: Colors.grey[600]),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${NamingUtils.tasksName(plural: true)} are private by default',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () {
                            if (AuthUtils.isGuestUser()) {
                              _showGuestSignupDialog(
                                content:
                                    'Here\'s where you can revise ${NamingUtils.categoriesName(plural: false, withArticle: true)} once you\'re logged in. Sign up to create your own ${NamingUtils.categoriesName()} and ${NamingUtils.tasksName()}!',
                              );
                              return;
                            }
                            setState(() {
                              _isEditing = true;
                            });
                          },
                          tooltip:
                              'Edit ${NamingUtils.categoriesName(capitalize: false, plural: false)}',
                        ),
                      ],
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
                  !_showCategoryEditorPanel &&
                  (widget.category != null || _currentCategory != null)) ...[
                // Only show "Current tasks:" header if there are tasks (use unfiltered count)
                if (_unfilteredTaskCount > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.category == null
                            ? _buildNewCategoryTaskCountText()
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
                            'Add ${NamingUtils.tasksName(withArticle: true, capitalize: false, plural: false)} manually',
                        style: AppButtons.iconGoForth(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 0),
                  // Sorting + Search (stacked to avoid horizontal overflow)
                  Builder(builder: (context) {
                    Widget buildSortRow(SortOption option, String label) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Radio<SortOption>(
                            value: option,
                            groupValue: _currentSortOption,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            onChanged: (SortOption? value) {
                              if (value != null) _setSortOption(value);
                            },
                          ),
                          Text(label),
                        ],
                      );
                    }

                    final sortWidget = Row(
                      // Center "Sort By:" vertically relative to the stacked options.
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text('Sort By:'),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            buildSortRow(SortOption.priority, 'Priority'),
                            buildSortRow(SortOption.alphabetical, 'A-Z'),
                            buildSortRow(SortOption.age, 'Age'),
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
                        suffixIcon: _isSearching
                            ? const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _searchController.clear();
                                        _clearTaskCache();
                                      });
                                    },
                                  )
                                : null,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _isSearching = true;
                          _clearTaskCache();
                        });
                        // Show processing indicator briefly
                        Future.delayed(const Duration(milliseconds: 300), () {
                          if (mounted) {
                            setState(() {
                              _isSearching = false;
                            });
                          }
                        });
                      },
                    );

                    return LayoutBuilder(builder: (context, constraints) {
                      // Always keep search on the same line as sort options, but ensure the
                      // search field's right edge is always visible. When space is tight,
                      // the sort controls scroll within a bounded area instead of pushing
                      // the search field off-screen.

                      if (_unfilteredTaskCount < 5) {
                        return searchWidget;
                      }

                      final sortAreaWidth =
                          (constraints.maxWidth * 0.35).clamp(0.0, 240.0);

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
                  }),
                  const SizedBox(height: 0),
                ],
                const SizedBox(height: 8),
                // Show "No tasks yet" only if there are truly no tasks (unfiltered)
                if (_unfilteredTaskCount == 0)
                  Center(
                    child: Column(
                      children: [
                        Text(
                          'No ${NamingUtils.tasksName(plural: true)} yet.',
                          style: const TextStyle(fontSize: 16),
                        ),
                        if (widget.category != null) ...[
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _createTask,
                            icon: const Icon(Icons.add),
                            label: Text(
                                'Add ${NamingUtils.tasksName(withArticle: true, plural: false)}'),
                            style: AppButtons.goForth().copyWith(
                              padding: const WidgetStatePropertyAll(
                                EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 8),
                          Text(
                            'Add some ${NamingUtils.tasksName(plural: true)} above to get started!',
                            style: const TextStyle(
                                fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ],
                    ),
                  )
                // Show "No results" if search has no matches but there are tasks
                else if (_tasks.isEmpty &&
                    _searchController.text.trim().isNotEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 48,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No results found',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Try a different search term',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  widget.category == null
                      ? _buildNewTaskList()
                      : _buildTaskListWithLoading(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
