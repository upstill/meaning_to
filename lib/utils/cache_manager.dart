import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:io';
import 'package:meaning_to/utils/text_importer.dart';

/// A cache management module for Categories and Tasks
/// Can handle both saved Categories from the database and new unsaved Categories with Tasks
class CacheManager {
  // Current context
  Category? _currentCategory;
  List<Task>? _currentTasks;
  String? _currentUserId;
  bool _isUnsavedCategory = false;

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
          'CacheManager: Initializing with saved category ${category.headline}');

      _currentCategory = category;
      _currentUserId = userId;
      _isUnsavedCategory = false;

      // Load tasks from database
      final response = await Supabase.instance.client
          .from('Tasks')
          .select()
          .eq('category_id', category.id)
          .eq('owner_id', userId)
          .order('created_at', ascending: false);

      if (response == null || response.isEmpty) {
        print('CacheManager: No tasks found for category ${category.id}');
        _currentTasks = [];
        return;
      }

      // Convert to Task objects
      _currentTasks = (response as List)
          .map((json) => Task.fromJson(json as Map<String, dynamic>))
          .toList();

      // Sort tasks: unfinished first, then by suggestibleAt ascending
      _sortTasks();

      print(
          'CacheManager: Loaded ${_currentTasks!.length} tasks for saved category');
    } catch (e, stackTrace) {
      print('CacheManager: Error initializing with saved category: $e');
      print('CacheManager: Stack trace: $stackTrace');
      clearCache();
      rethrow;
    }
  }

  /// Initialize cache with a new unsaved Category and its Tasks
  /// The Category and Tasks are not yet saved to the database
  void initializeWithUnsavedCategory(
      Category category, List<Task> tasks, String userId) {
    print(
        'CacheManager: Initializing with unsaved category ${category.headline}');

    _currentCategory = category;
    _currentTasks =
        List.from(tasks); // Create a copy to avoid external modifications
    _currentUserId = userId;
    _isUnsavedCategory = true;

    // Sort tasks: unfinished first, then by suggestibleAt ascending
    _sortTasks();

    print(
        'CacheManager: Loaded ${_currentTasks!.length} tasks for unsaved category');
  }

  /// Save the current unsaved Category and its Tasks to the database
  /// Returns the saved Category with its database ID
  Future<Category> saveUnsavedCategory() async {
    if (!_isUnsavedCategory ||
        _currentCategory == null ||
        _currentUserId == null) {
      throw Exception('No unsaved category to save');
    }

    try {
      print(
          'CacheManager: Saving unsaved category ${_currentCategory!.headline}');

      // Save the category first
      final categoryData = {
        'headline': _currentCategory!.headline,
        'invitation': _currentCategory!.invitation,
        'owner_id': _currentUserId,
        'original_id':
            _currentCategory!.originalId ?? 1, // Default to movies (1)
      };

      final categoryResponse = await Supabase.instance.client
          .from('Categories')
          .insert(categoryData)
          .select()
          .single();

      final savedCategory = Category.fromJson(categoryResponse);
      print('CacheManager: Saved category with ID ${savedCategory.id}');

      // Save all tasks for the new category
      if (_currentTasks != null && _currentTasks!.isNotEmpty) {
        print(
            'CacheManager: Saving ${_currentTasks!.length} tasks for new category');

        for (final task in _currentTasks!) {
          final taskJson = task.toJson();
          final taskData = {
            'headline': taskJson['headline'],
            'notes': taskJson['notes'],
            'category_id': savedCategory.id,
            'owner_id': _currentUserId,
            'links': taskJson['links'],
          };

          final taskResponse = await Supabase.instance.client
              .from('Tasks')
              .insert(taskData)
              .select()
              .single();

          // Update the task with its database ID
          final savedTask = Task.fromJson(taskResponse);
          final taskIndex =
              _currentTasks!.indexWhere((t) => t.headline == task.headline);
          if (taskIndex != -1) {
            _currentTasks![taskIndex] = savedTask;
          }
        }
      }

      // Update cache to reflect saved state
      _currentCategory = savedCategory;
      _isUnsavedCategory = false;

      print('CacheManager: Successfully saved category and all tasks');
      return savedCategory;
    } catch (e, stackTrace) {
      print('CacheManager: Error saving unsaved category: $e');
      print('CacheManager: Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Add a new Task to the current Category
  /// For unsaved categories, adds to the local cache
  /// For saved categories, saves to database and updates cache
  Future<void> addTask(Task task) async {
    if (_currentCategory == null) {
      throw Exception('No category loaded in cache');
    }

    if (_isUnsavedCategory) {
      // For unsaved categories, just add to local cache
      _currentTasks!.add(task);
      _sortTasks();
      print('CacheManager: Added task to unsaved category cache');
    } else {
      // For saved categories, save to database and update cache
      try {
        final taskData = {
          'headline': task.headline,
          'notes': task.notes,
          'category_id': _currentCategory!.id,
          'owner_id': _currentUserId,
          'links': task.links != null
              ? (task.links!.length == 1
                  ? task.links![0]
                  : jsonEncode(task.links))
              : null,
        };

        final response = await Supabase.instance.client
            .from('Tasks')
            .insert(taskData)
            .select()
            .single();

        final savedTask = Task.fromJson(response);
        _currentTasks!.add(savedTask);
        _sortTasks();

        print('CacheManager: Added and saved task to database');
      } catch (e) {
        print('CacheManager: Error adding task: $e');
        rethrow;
      }
    }
  }

  /// Update an existing Task in the cache
  /// For unsaved categories, updates local cache
  /// For saved categories, updates database and cache
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
      print('CacheManager: Updated task in unsaved category cache');
    } else {
      // For saved categories, update database and cache
      try {
        final taskData = {
          'headline': updatedTask.headline,
          'notes': updatedTask.notes,
          'links': updatedTask.links != null
              ? (updatedTask.links!.length == 1
                  ? updatedTask.links![0]
                  : jsonEncode(updatedTask.links))
              : null,
          'finished': updatedTask.finished,
          'suggestible_at': updatedTask.suggestibleAt?.toIso8601String(),
          'deferral': updatedTask.deferral,
        };

        await Supabase.instance.client
            .from('Tasks')
            .update(taskData)
            .eq('id', updatedTask.id)
            .eq('owner_id', _currentUserId!);

        _currentTasks![taskIndex] = updatedTask;
        _sortTasks();

        print('CacheManager: Updated task in database and cache');
      } catch (e) {
        print('CacheManager: Error updating task: $e');
        rethrow;
      }
    }
  }

  /// Remove a Task from the cache
  /// For unsaved categories, removes from local cache
  /// For saved categories, deletes from database and updates cache
  Future<void> removeTask(int taskId) async {
    if (_currentCategory == null || _currentTasks == null) {
      throw Exception('No category or tasks loaded in cache');
    }

    final taskIndex = _currentTasks!.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) {
      throw Exception('Task not found in cache');
    }

    if (_isUnsavedCategory) {
      // For unsaved categories, just remove from local cache
      _currentTasks!.removeAt(taskIndex);
      print('CacheManager: Removed task from unsaved category cache');
    } else {
      // For saved categories, delete from database and update cache
      try {
        await Supabase.instance.client
            .from('Tasks')
            .delete()
            .eq('id', taskId)
            .eq('owner_id', _currentUserId!);

        _currentTasks!.removeAt(taskIndex);

        print('CacheManager: Removed task from database and cache');
      } catch (e) {
        print('CacheManager: Error removing task: $e');
        rethrow;
      }
    }
  }

  /// Get a random unfinished task from the current category
  /// Returns null if no unfinished tasks are available
  Task? getRandomUnfinishedTask() {
    if (_currentTasks == null || _currentTasks!.isEmpty) {
      return null;
    }

    // Find unfinished tasks that are suggestible
    final now = DateTime.now();
    final unfinishedTasks = _currentTasks!
        .where((task) =>
            !task.finished &&
            (task.suggestibleAt == null || !task.suggestibleAt!.isAfter(now)))
        .toList();

    if (unfinishedTasks.isEmpty) {
      return null;
    }

    // Return a random unfinished task
    final random =
        DateTime.now().millisecondsSinceEpoch % unfinishedTasks.length;
    return unfinishedTasks[random];
  }

  /// Mark a task as finished
  Future<void> finishTask(int taskId) async {
    final taskIndex = _currentTasks!.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) {
      throw Exception('Task not found in cache');
    }

    final task = _currentTasks![taskIndex];
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
      finished: true,
    );

    await updateTask(updatedTask);
  }

  /// Reject a task by deferring it
  Future<void> rejectTask(int taskId) async {
    final taskIndex = _currentTasks!.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) {
      throw Exception('Task not found in cache');
    }

    final task = _currentTasks![taskIndex];
    final currentDeferral = task.deferral ?? 60;
    final newDeferral = currentDeferral * 2;
    final now = DateTime.now();
    final newSuggestibleAt = now.add(Duration(minutes: currentDeferral));

    final updatedTask = Task(
      id: task.id,
      categoryId: task.categoryId,
      headline: task.headline,
      notes: task.notes,
      ownerId: task.ownerId,
      createdAt: task.createdAt,
      suggestibleAt: newSuggestibleAt,
      triggersAt: task.triggersAt,
      deferral: newDeferral,
      links: task.links,
      processedLinks: task.processedLinks,
      finished: task.finished,
    );

    await updateTask(updatedTask);
  }

  /// Clear the cache
  void clearCache() {
    _currentCategory = null;
    _currentTasks = null;
    _currentUserId = null;
    _isUnsavedCategory = false;
    print('CacheManager: Cache cleared');
  }

  /// Sort tasks: unfinished first, then by suggestibleAt ascending
  void _sortTasks() {
    if (_currentTasks == null) return;

    _currentTasks!.sort((a, b) {
      // First, sort by finished status (unfinished first)
      if (a.finished != b.finished) {
        return a.finished ? 1 : -1;
      }

      // Then, sort by suggestibleAt (earlier first)
      if (a.suggestibleAt == null && b.suggestibleAt == null) {
        return 0;
      }
      if (a.suggestibleAt == null) {
        return -1;
      }
      if (b.suggestibleAt == null) {
        return 1;
      }

      return a.suggestibleAt!.compareTo(b.suggestibleAt!);
    });
  }

  /// Check if cache is initialized
  bool get isInitialized => _currentCategory != null && _currentUserId != null;

  /// Get the number of tasks in the cache
  int get taskCount => _currentTasks?.length ?? 0;

  /// Get the number of unfinished tasks
  int get unfinishedTaskCount {
    if (_currentTasks == null) return 0;
    return _currentTasks!.where((task) => !task.finished).length;
  }

  /// Export the current cache contents to a JSON file
  /// Returns the file path where the JSON was saved
  Future<String> exportToJson(String filePath) async {
    if (!isInitialized) {
      throw Exception('Cache is not initialized. Nothing to export.');
    }

    try {
      print('CacheManager: Exporting cache to $filePath');

      // Create the export data structure
      final exportData = {
        'exportedAt': DateTime.now().toIso8601String(),
        'category': _currentCategory?.toJson(),
        'tasks': _currentTasks?.map((task) => task.toJson()).toList() ?? [],
        'userId': _currentUserId,
        'isUnsavedCategory': _isUnsavedCategory,
        'metadata': {
          'taskCount': taskCount,
          'unfinishedTaskCount': unfinishedTaskCount,
          'version': '1.0',
        },
      };

      // Convert to JSON string with pretty formatting
      final jsonString = JsonEncoder.withIndent('  ').convert(exportData);

      // Write to file
      final file = File(filePath);
      await file.writeAsString(jsonString);

      print('CacheManager: Successfully exported cache to $filePath');
      print('CacheManager: Exported ${taskCount} tasks');

      return filePath;
    } catch (e, stackTrace) {
      print('CacheManager: Error exporting cache: $e');
      print('CacheManager: Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Import cache contents from a JSON file or JSON text
  /// Returns true if import was successful
  ///
  /// [input] can be either:
  /// - A file path (string starting with '/' or containing path separators)
  /// - A JSON text block (string containing JSON data)
  Future<bool> importFromJson(String input) async {
    try {
      print('CacheManager: Importing cache from input');

      String jsonString;

      // Determine if input is a file path or JSON text
      if (_isFilePath(input)) {
        // Handle as file path
        print('CacheManager: Treating input as file path: $input');
        final file = File(input);
        if (!await file.exists()) {
          throw Exception('File does not exist: $input');
        }
        jsonString = await file.readAsString();
      } else {
        // Handle as JSON text
        print('CacheManager: Treating input as JSON text');
        jsonString = input;
      }

      // Validate JSON and check if it's from our export operation
      Map<String, dynamic>? importData;
      try {
        importData = jsonDecode(jsonString) as Map<String, dynamic>;
      } catch (e) {
        print(
            'CacheManager: Invalid JSON detected, falling back to TextImporter');
        await _fallbackToTextImporter(jsonString);
        return false;
      }

      // Check if the data came from our export operation (has 'category' key)
      if (!importData.containsKey('category')) {
        print(
            'CacheManager: JSON doesn\'t contain category key, falling back to TextImporter');
        await _fallbackToTextImporter(jsonString);
        return false;
      }

      // Validate the import data structure
      if (!importData.containsKey('tasks')) {
        throw Exception('Invalid cache export format: missing tasks');
      }

      // Parse the category
      final categoryJson = importData['category'] as Map<String, dynamic>;
      final category = Category.fromJson(categoryJson);

      // Parse the tasks
      final tasksJson = importData['tasks'] as List<dynamic>;
      final tasks = tasksJson
          .map((taskJson) => Task.fromJson(taskJson as Map<String, dynamic>))
          .toList();

      // Get additional metadata
      final userId = importData['userId'] as String?;
      final isUnsaved = importData['isUnsavedCategory'] as bool? ?? false;

      // Initialize the cache with imported data
      if (isUnsaved) {
        initializeWithUnsavedCategory(category, tasks, userId ?? 'unknown');
      } else {
        // For saved categories, we need to handle this carefully
        // since the IDs might conflict with existing database records
        print(
            'CacheManager: Warning - Importing saved category may cause ID conflicts');
        initializeWithUnsavedCategory(category, tasks, userId ?? 'unknown');
      }

      print('CacheManager: Successfully imported cache');
      print('CacheManager: Imported category: ${category.headline}');
      print('CacheManager: Imported ${tasks.length} tasks');

      return true;
    } catch (e, stackTrace) {
      print('CacheManager: Error importing cache: $e');
      print('CacheManager: Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Helper method to determine if a string is a file path
  bool _isFilePath(String input) {
    // Check for common file path indicators
    return input.startsWith('/') || // Absolute path
        input.startsWith('./') || // Relative path
        input.startsWith('../') || // Relative path
        input.contains('\\') || // Windows path separator
        input.contains('/') &&
            !input.trim().startsWith('{') &&
            !input.trim().startsWith(
                '['); // Contains path separator and doesn't look like JSON
  }

  /// Export cache to a default location with timestamp
  /// Returns the file path where the JSON was saved
  Future<String> exportToDefaultLocation() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final categoryName =
        _currentCategory?.headline.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_') ??
            'unknown';
    final fileName = 'cache_export_${categoryName}_$timestamp.json';

    // Use the app's documents directory
    final documentsDir = await _getDocumentsDirectory();
    final filePath = '${documentsDir.path}/$fileName';

    return await exportToJson(filePath);
  }

  /// Get the documents directory for the app
  Future<Directory> _getDocumentsDirectory() async {
    // For Flutter, we'll use the app's documents directory
    // This works for both mobile and desktop
    final appDir = Directory.current;
    final documentsDir = Directory('${appDir.path}/documents');

    // Create the directory if it doesn't exist
    if (!await documentsDir.exists()) {
      await documentsDir.create(recursive: true);
    }

    return documentsDir;
  }

  /// Get a list of available cache export files
  Future<List<FileSystemEntity>> getAvailableExports() async {
    try {
      final documentsDir = await _getDocumentsDirectory();
      final files = await documentsDir.list().toList();

      // Filter for JSON files that look like cache exports
      return files.where((file) {
        final fileName = file.path.split('/').last;
        return fileName.startsWith('cache_export_') &&
            fileName.endsWith('.json');
      }).toList();
    } catch (e) {
      print('CacheManager: Error getting available exports: $e');
      return [];
    }
  }

  /// Delete a cache export file
  Future<bool> deleteExport(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        print('CacheManager: Deleted export file: $filePath');
        return true;
      }
      return false;
    } catch (e) {
      print('CacheManager: Error deleting export: $e');
      return false;
    }
  }

  /// Get cache statistics as a JSON object
  Map<String, dynamic> getCacheStats() {
    if (!isInitialized) {
      return {'error': 'Cache not initialized'};
    }

    return {
      'category': {
        'id': _currentCategory?.id,
        'headline': _currentCategory?.headline,
        'isUnsaved': _isUnsavedCategory,
      },
      'tasks': {
        'total': taskCount,
        'unfinished': unfinishedTaskCount,
        'finished': taskCount - unfinishedTaskCount,
      },
      'userId': _currentUserId,
      'lastUpdated': DateTime.now().toIso8601String(),
    };
  }

  /// Validate that the current cache is in a consistent state
  bool validateCache() {
    if (!isInitialized) {
      return false;
    }

    // Check that all tasks belong to the current category
    if (_currentTasks != null) {
      for (final task in _currentTasks!) {
        if (task.categoryId != _currentCategory!.id) {
          print(
              'CacheManager: Validation failed - task ${task.id} has wrong categoryId');
          return false;
        }
      }
    }

    // Check that task counts are consistent
    final actualUnfinishedCount =
        _currentTasks?.where((task) => !task.finished).length ?? 0;
    if (actualUnfinishedCount != unfinishedTaskCount) {
      print('CacheManager: Validation failed - unfinished count mismatch');
      return false;
    }

    return true;
  }

  /// Fallback method to import from text
  Future<void> _fallbackToTextImporter(String text) async {
    try {
      print('CacheManager: Processing text through TextImporter');

      // Process the text through TextImporter using the public method
      final items = <ImportItem>[];
      await for (final item in TextImporter.processTextData(text)) {
        items.add(item);
      }

      print('CacheManager: TextImporter found ${items.length} items');

      // Merge items into the existing cache
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        print(
            'CacheManager: Processing item $i - Title: "${item.title}", Link: ${item.link}, Domain: ${item.domain}');

        await _mergeItemIntoCache(item);
      }
    } catch (e) {
      print('CacheManager: Error in TextImporter fallback: $e');
    }
  }

  /// Merge an ImportItem into the existing cache
  Future<void> _mergeItemIntoCache(ImportItem item) async {
    if (_currentCategory == null || _currentUserId == null) {
      print('CacheManager: Cannot merge item - no category or user ID');
      return;
    }

    // Find existing task with matching title
    Task? existingTask;
    if (_currentTasks != null) {
      try {
        existingTask = _currentTasks!.firstWhere(
          (task) => task.headline.toLowerCase() == item.title.toLowerCase(),
        );
      } catch (e) {
        // Task not found, will create new one
        existingTask = null;
      }
    }

    if (existingTask == null) {
      // Create new task
      print('CacheManager: Creating new task for "${item.title}"');
      final newTask = Task(
        id: DateTime.now().millisecondsSinceEpoch, // Temporary ID
        categoryId: _currentCategory!.id,
        headline: item.title,
        notes: item.description,
        ownerId: _currentUserId!,
        createdAt: DateTime.now(),
        finished: false,
      );

      // Add the new task to cache
      await addTask(newTask);
      existingTask = newTask;
    } else {
      // Update existing task
      print('CacheManager: Updating existing task "${item.title}"');

      // Update notes if description is provided
      if (item.description != null && item.description!.isNotEmpty) {
        final updatedTask = Task(
          id: existingTask.id,
          categoryId: existingTask.categoryId,
          headline: existingTask.headline,
          notes: item.description,
          ownerId: existingTask.ownerId,
          createdAt: existingTask.createdAt,
          suggestibleAt: existingTask.suggestibleAt,
          triggersAt: existingTask.triggersAt,
          deferral: existingTask.deferral,
          links: existingTask.links,
          processedLinks: existingTask.processedLinks,
          finished: existingTask.finished,
        );

        await updateTask(updatedTask);
        existingTask = updatedTask;
      }
    }

    // Add link if provided and not already present
    if (item.link != null && item.link!.isNotEmpty) {
      final currentLinks = existingTask.links ?? [];

      // Check if link already exists
      final linkExists = currentLinks.any((link) =>
          link.toLowerCase() == item.link!.toLowerCase() ||
          link.contains(item.link!) ||
          item.link!.contains(link));

      if (!linkExists) {
        print('CacheManager: Adding link ${item.link} to task "${item.title}"');

        final updatedLinks = List<String>.from(currentLinks)..add(item.link!);
        final updatedTask = Task(
          id: existingTask.id,
          categoryId: existingTask.categoryId,
          headline: existingTask.headline,
          notes: existingTask.notes,
          ownerId: existingTask.ownerId,
          createdAt: existingTask.createdAt,
          suggestibleAt: existingTask.suggestibleAt,
          triggersAt: existingTask.triggersAt,
          deferral: existingTask.deferral,
          links: updatedLinks,
          processedLinks: existingTask.processedLinks,
          finished: existingTask.finished,
        );

        await updateTask(updatedTask);
      } else {
        print(
            'CacheManager: Link ${item.link} already exists for task "${item.title}"');
      }
    }
  }
}
