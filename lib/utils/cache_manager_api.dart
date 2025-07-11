import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/auth.dart';
import 'dart:async';

/// A cache management module for Categories and Tasks using the API
/// Can handle both saved Categories from the database and new unsaved Categories with Tasks
class CacheManagerApi {
  static final CacheManagerApi _instance = CacheManagerApi._internal();

  factory CacheManagerApi() {
    return _instance;
  }

  CacheManagerApi._internal();

  // Current context
  Category? _currentCategory;
  List<Task>? _currentTasks;
  String? _currentUserId;
  bool _isUnsavedCategory = false;

  // Notification stream for cache changes
  static final StreamController<void> _cacheChangeController =
      StreamController<void>.broadcast();
  static Stream<void> get onCacheChanged => _cacheChangeController.stream;

  // Getters
  Category? get currentCategory => _currentCategory;
  List<Task>? get currentTasks => _currentTasks;
  String? get currentUserId => _currentUserId;
  bool get isUnsavedCategory => _isUnsavedCategory;

  /// Initialize cache with a saved Category from the database
  /// Loads all Tasks for the Category
  Future<void> initializeWithSavedCategory(
      Category category, String userId) async {
    try {
      print(
          'CacheManagerApi: Initializing with saved category ${category.headline}');

      _currentCategory = category;
      _currentUserId = userId;
      _isUnsavedCategory = false;

      await _loadTasksFromApi();
    } catch (e, stackTrace) {
      print('CacheManagerApi: Error initializing with saved category: $e');
      print('CacheManagerApi: Stack trace: $stackTrace');
      clearCache();
      rethrow;
    }
  }

  /// Refresh tasks for the current category from the API
  /// Useful when tasks have been added by other screens
  Future<void> refreshCurrentCategoryTasks() async {
    if (_currentCategory == null || _currentUserId == null) {
      print('CacheManagerApi: No current category or user ID for refresh');
      return;
    }

    try {
      print(
          'CacheManagerApi: Refreshing tasks for category ${_currentCategory!.headline}');
      await _loadTasksFromApi();
    } catch (e) {
      print('CacheManagerApi: Error refreshing tasks: $e');
      rethrow;
    }
  }

  /// Load tasks from API for the current category
  Future<void> _loadTasksFromApi() async {
    if (_currentCategory == null || _currentUserId == null) {
      throw Exception('No current category or user ID');
    }

    try {
      // Load tasks from API
      final tasks = await ApiClient.getTasks();

      // Filter tasks for current category
      _currentTasks = tasks
          .where((task) => task.categoryId == _currentCategory!.id)
          .toList();

      if (_currentTasks!.isEmpty) {
        print(
            'CacheManagerApi: No tasks found for category ${_currentCategory!.id}');
        _currentTasks = [];
        return;
      }

      // Sort tasks: unfinished first, then by suggestibleAt ascending
      _sortTasks();

      print(
          'CacheManagerApi: Loaded ${_currentTasks!.length} tasks for saved category');

      // Notify listeners that cache has changed
      _cacheChangeController.add(null);
    } catch (e) {
      print('CacheManagerApi: Error loading tasks from API: $e');
      rethrow;
    }
  }

  /// Initialize cache with a new unsaved Category and its Tasks
  /// The Category and Tasks are not yet saved to the database
  void initializeWithUnsavedCategory(
      Category category, List<Task> tasks, String userId) {
    print(
        'CacheManagerApi: Initializing with unsaved category ${category.headline}');

    _currentCategory = category;
    _currentTasks =
        List.from(tasks); // Create a copy to avoid external modifications
    _currentUserId = userId;
    _isUnsavedCategory = true;

    // Sort tasks: unfinished first, then by suggestibleAt ascending
    _sortTasks();

    print(
        'CacheManagerApi: Loaded ${_currentTasks!.length} tasks for unsaved category');

    // Notify listeners that cache has changed
    _cacheChangeController.add(null);
  }

  /// Update an existing Task in the cache
  /// For unsaved categories, updates local cache
  /// For saved categories, updates API and cache
  Future<void> updateTask(Task updatedTask) async {
    if (_currentCategory == null || _currentTasks == null) {
      throw Exception('No category or tasks loaded in cache');
    }

    final taskIndex = _currentTasks!.indexWhere((t) => t.id == updatedTask.id);
    if (taskIndex == -1) {
      throw Exception('Task not found in cache');
    }

    if (_isUnsavedCategory) {
      // For unsaved categories, just update local cache
      _currentTasks![taskIndex] = updatedTask;
      _sortTasks();
      print('CacheManagerApi: Updated task in unsaved category cache');

      // Notify listeners that cache has changed
      _cacheChangeController.add(null);
    } else {
      // For saved categories, update API and cache
      try {
        final taskData = {
          'headline': updatedTask.headline,
          'notes': updatedTask.notes,
          'links': updatedTask.links,
          'finished': updatedTask.finished,
          'suggestible_at': updatedTask.suggestibleAt?.toIso8601String(),
          'deferral': updatedTask.deferral,
        };

        await ApiClient.updateTask(updatedTask.id.toString(), taskData);

        _currentTasks![taskIndex] = updatedTask;
        _sortTasks();

        print('CacheManagerApi: Updated task in API and cache');

        // Notify listeners that cache has changed
        _cacheChangeController.add(null);
      } catch (e) {
        print('CacheManagerApi: Error updating task: $e');
        rethrow;
      }
    }
  }

  /// Clear the cache
  void clearCache() {
    _currentCategory = null;
    _currentTasks = null;
    _currentUserId = null;
    _isUnsavedCategory = false;
    print('CacheManagerApi: Cache cleared');
  }

  /// Sort tasks: unfinished first, then by suggestibleAt ascending
  void _sortTasks() {
    if (_currentTasks == null) return;

    _currentTasks!.sort((a, b) {
      // First, sort by finished status (unfinished first)
      if (a.finished != b.finished) {
        return a.finished ? 1 : -1;
      }

      // Then, sort by suggestibleAt (null first, then ascending)
      if (a.suggestibleAt == null && b.suggestibleAt == null) return 0;
      if (a.suggestibleAt == null) return -1;
      if (b.suggestibleAt == null) return 1;
      return a.suggestibleAt!.compareTo(b.suggestibleAt!);
    });
  }
}
