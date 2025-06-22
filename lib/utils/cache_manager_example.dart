import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'dart:convert';
import 'dart:io';

/// Example usage of the CacheManager module
class CacheManagerExample {
  static final CacheManager _cacheManager = CacheManager();

  /// Example: Initialize cache with a saved category from database
  static Future<void> exampleWithSavedCategory() async {
    print('=== Example: Saved Category ===');

    // Assume we have a category from the database
    final savedCategory = Category(
      id: 1,
      headline: 'My Movies',
      ownerId: 'user123',
      createdAt: DateTime.now(),
    );

    // Initialize cache with saved category
    await _cacheManager.initializeWithSavedCategory(savedCategory, 'user123');

    print('Category: ${_cacheManager.currentCategory?.headline}');
    print('Task count: ${_cacheManager.taskCount}');
    print('Unfinished tasks: ${_cacheManager.unfinishedTaskCount}');

    // Get a random unfinished task
    final randomTask = _cacheManager.getRandomUnfinishedTask();
    if (randomTask != null) {
      print('Random task: ${randomTask.headline}');

      // Mark task as finished
      await _cacheManager.finishTask(randomTask.id);
      print('Task marked as finished');
    }
  }

  /// Example: Initialize cache with an unsaved category and tasks
  static Future<void> exampleWithUnsavedCategory() async {
    print('=== Example: Unsaved Category ===');

    // Create a new unsaved category
    final unsavedCategory = Category(
      id: -1, // Temporary ID for unsaved category
      headline: 'New Movie List',
      ownerId: 'user123',
      createdAt: DateTime.now(),
    );

    // Create some unsaved tasks
    final unsavedTasks = [
      Task(
        id: -1,
        categoryId: -1,
        headline: 'The Matrix',
        notes: 'Classic sci-fi movie',
        ownerId: 'user123',
        createdAt: DateTime.now(),
        finished: false,
      ),
      Task(
        id: -2,
        categoryId: -1,
        headline: 'Inception',
        notes: 'Mind-bending thriller',
        ownerId: 'user123',
        createdAt: DateTime.now(),
        finished: false,
      ),
    ];

    // Initialize cache with unsaved category and tasks
    _cacheManager.initializeWithUnsavedCategory(
        unsavedCategory, unsavedTasks, 'user123');

    print('Category: ${_cacheManager.currentCategory?.headline}');
    print('Task count: ${_cacheManager.taskCount}');
    print('Is unsaved: ${_cacheManager.isUnsavedCategory}');

    // Add another task to the unsaved category
    final newTask = Task(
      id: -3,
      categoryId: -1,
      headline: 'Interstellar',
      notes: 'Space exploration movie',
      ownerId: 'user123',
      createdAt: DateTime.now(),
      finished: false,
    );

    await _cacheManager.addTask(newTask);
    print('Added new task. Total tasks: ${_cacheManager.taskCount}');

    // Save the category and all tasks to database
    try {
      final savedCategory = await _cacheManager.saveUnsavedCategory();
      print('Category saved with ID: ${savedCategory.id}');
      print('Is unsaved: ${_cacheManager.isUnsavedCategory}');
    } catch (e) {
      print('Error saving category: $e');
    }
  }

  /// Example: Task management operations
  static Future<void> exampleTaskOperations() async {
    print('=== Example: Task Operations ===');

    // Initialize with a saved category (assuming it exists)
    final category = Category(
      id: 1,
      headline: 'Test Category',
      ownerId: 'user123',
      createdAt: DateTime.now(),
    );

    await _cacheManager.initializeWithSavedCategory(category, 'user123');

    // Add a new task
    final newTask = Task(
      id: -1,
      categoryId: category.id,
      headline: 'New Task',
      notes: 'This is a new task',
      ownerId: 'user123',
      createdAt: DateTime.now(),
      finished: false,
    );

    await _cacheManager.addTask(newTask);
    print('Added task. Total tasks: ${_cacheManager.taskCount}');

    // Get a random task and reject it
    final randomTask = _cacheManager.getRandomUnfinishedTask();
    if (randomTask != null) {
      print('Rejecting task: ${randomTask.headline}');
      await _cacheManager.rejectTask(randomTask.id);
      print('Task rejected and deferred');
    }

    // Remove a task
    if (_cacheManager.currentTasks != null &&
        _cacheManager.currentTasks!.isNotEmpty) {
      final taskToRemove = _cacheManager.currentTasks!.first;
      await _cacheManager.removeTask(taskToRemove.id);
      print('Removed task: ${taskToRemove.headline}');
    }
  }

  /// Example: Cache management
  static void exampleCacheManagement() {
    print('=== Example: Cache Management ===');

    print('Is initialized: ${_cacheManager.isInitialized}');
    print('Current category: ${_cacheManager.currentCategory?.headline}');
    print('Task count: ${_cacheManager.taskCount}');

    // Clear the cache
    _cacheManager.clearCache();
    print('Cache cleared');
    print('Is initialized: ${_cacheManager.isInitialized}');
  }

  /// Example: Export and import functionality
  static Future<void> exampleExportImport() async {
    print('=== Example: Export and Import ===');

    // First, initialize with some data
    final category = Category(
      id: 1,
      headline: 'Test Export Category',
      ownerId: 'user123',
      createdAt: DateTime.now(),
    );

    final tasks = [
      Task(
        id: 1,
        categoryId: 1,
        headline: 'Task 1',
        notes: 'First task for export test',
        ownerId: 'user123',
        createdAt: DateTime.now(),
        finished: false,
      ),
      Task(
        id: 2,
        categoryId: 1,
        headline: 'Task 2',
        notes: 'Second task for export test',
        ownerId: 'user123',
        createdAt: DateTime.now(),
        finished: true,
      ),
    ];

    _cacheManager.initializeWithUnsavedCategory(category, tasks, 'user123');
    print('Initialized cache with ${_cacheManager.taskCount} tasks');

    // Export to default location
    try {
      final exportPath = await _cacheManager.exportToDefaultLocation();
      print('Exported cache to: $exportPath');

      // Get cache statistics
      final stats = _cacheManager.getCacheStats();
      print('Cache stats: $stats');

      // Validate cache
      final isValid = _cacheManager.validateCache();
      print('Cache validation: $isValid');

      // Get available exports
      final availableExports = await _cacheManager.getAvailableExports();
      print('Available exports: ${availableExports.length} files');

      // Import the exported file (as file path)
      _cacheManager.clearCache(); // Clear current cache
      print('Cleared cache for import test');

      final importSuccess = await _cacheManager.importFromJson(exportPath);
      print('Import successful: $importSuccess');
      print('Imported category: ${_cacheManager.currentCategory?.headline}');
      print('Imported tasks: ${_cacheManager.taskCount}');

      // Clean up - delete the export file
      final deleted = await _cacheManager.deleteExport(exportPath);
      print('Deleted export file: $deleted');
    } catch (e) {
      print('Error in export/import example: $e');
    }
  }

  /// Example: Import from JSON text block
  static Future<void> exampleImportFromText() async {
    print('=== Example: Import from JSON Text ===');

    // Sample JSON text block
    const jsonText = '''
{
  "exportedAt": "2024-01-15T10:30:00.000Z",
  "category": {
    "id": 1,
    "headline": "Imported from Text",
    "invitation": "Category imported from JSON text",
    "owner_id": "user123",
    "created_at": "2024-01-15T10:00:00.000Z",
    "updated_at": null,
    "original_id": 1,
    "triggers_at": null,
    "template": null
  },
  "tasks": [
    {
      "id": 1,
      "category_id": 1,
      "headline": "Text Import Task 1",
      "notes": "This task was imported from JSON text",
      "owner_id": "user123",
      "created_at": "2024-01-15T10:00:00.000Z",
      "suggestible_at": "2024-01-15T10:00:00.000Z",
      "triggers_at": null,
      "deferral": null,
      "links": null,
      "finished": false
    },
    {
      "id": 2,
      "category_id": 1,
      "headline": "Text Import Task 2",
      "notes": "Another task from JSON text",
      "owner_id": "user123",
      "created_at": "2024-01-15T10:00:00.000Z",
      "suggestible_at": "2024-01-15T10:00:00.000Z",
      "triggers_at": null,
      "deferral": null,
      "links": null,
      "finished": true
    }
  ],
  "userId": "user123",
  "isUnsavedCategory": false,
  "metadata": {
    "taskCount": 2,
    "unfinishedTaskCount": 1,
    "version": "1.0"
  }
}
''';

    try {
      // Clear any existing cache
      _cacheManager.clearCache();
      print('Cleared cache for text import test');

      // Import from JSON text block
      final importSuccess = await _cacheManager.importFromJson(jsonText);
      print('Import from text successful: $importSuccess');

      if (importSuccess) {
        print('Imported category: ${_cacheManager.currentCategory?.headline}');
        print('Imported tasks: ${_cacheManager.taskCount}');
        print('Unfinished tasks: ${_cacheManager.unfinishedTaskCount}');

        // Show imported tasks
        if (_cacheManager.currentTasks != null) {
          for (final task in _cacheManager.currentTasks!) {
            print('  - ${task.headline} (finished: ${task.finished})');
          }
        }
      }
    } catch (e) {
      print('Error importing from text: $e');
    }
  }

  /// Example: Dynamic import (file path vs text detection)
  static Future<void> exampleDynamicImport() async {
    print('=== Example: Dynamic Import Detection ===');

    // Test with file path
    const filePath = '/tmp/test_export.json';
    print('Testing import with file path: $filePath');
    try {
      await _cacheManager.importFromJson(filePath);
      print('File path import attempted');
    } catch (e) {
      print('File path import failed (expected): $e');
    }

    // Test with JSON text
    const jsonText = '{"category": {"id": 1, "headline": "Test"}, "tasks": []}';
    print('Testing import with JSON text');
    try {
      await _cacheManager.importFromJson(jsonText);
      print('JSON text import attempted');
    } catch (e) {
      print('JSON text import failed: $e');
    }

    // Test with ambiguous input (path-like but could be JSON)
    const ambiguousInput = '{"path": "/some/path", "data": "value"}';
    print('Testing import with ambiguous input');
    try {
      await _cacheManager.importFromJson(ambiguousInput);
      print('Ambiguous input import attempted');
    } catch (e) {
      print('Ambiguous input import failed: $e');
    }
  }

  /// Example: Export to custom location
  static Future<void> exampleCustomExport() async {
    print('=== Example: Custom Export ===');

    // Initialize with some data
    final category = Category(
      id: 1,
      headline: 'Custom Export Test',
      ownerId: 'user123',
      createdAt: DateTime.now(),
    );

    final tasks = [
      Task(
        id: 1,
        categoryId: 1,
        headline: 'Custom Task',
        notes: 'Task for custom export test',
        ownerId: 'user123',
        createdAt: DateTime.now(),
        finished: false,
      ),
    ];

    _cacheManager.initializeWithUnsavedCategory(category, tasks, 'user123');

    // Export to a custom location
    try {
      final customPath = '/tmp/custom_cache_export.json';
      final exportPath = await _cacheManager.exportToJson(customPath);
      print('Exported to custom location: $exportPath');

      // Verify the file exists and has content
      final file = File(exportPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        print('Export file size: ${content.length} characters');

        // Parse and verify the export structure
        final exportData = jsonDecode(content);
        print('Export contains category: ${exportData['category'] != null}');
        print('Export contains ${exportData['tasks'].length} tasks');
        print('Export metadata: ${exportData['metadata']}');

        // Clean up
        await file.delete();
        print('Cleaned up custom export file');
      }
    } catch (e) {
      print('Error in custom export example: $e');
    }
  }

  /// Example: Batch operations with export/import
  static Future<void> exampleBatchOperations() async {
    print('=== Example: Batch Operations ===');

    // Initialize with a large dataset
    final category = Category(
      id: 1,
      headline: 'Batch Operations Test',
      ownerId: 'user123',
      createdAt: DateTime.now(),
    );

    final tasks = List.generate(
        10,
        (index) => Task(
              id: index + 1,
              categoryId: 1,
              headline: 'Batch Task ${index + 1}',
              notes: 'Task ${index + 1} for batch operations test',
              ownerId: 'user123',
              createdAt: DateTime.now(),
              finished: index % 3 == 0, // Every 3rd task is finished
            ));

    _cacheManager.initializeWithUnsavedCategory(category, tasks, 'user123');
    print('Initialized with ${_cacheManager.taskCount} tasks');

    // Perform some operations
    for (int i = 0; i < 5; i++) {
      final randomTask = _cacheManager.getRandomUnfinishedTask();
      if (randomTask != null) {
        await _cacheManager.finishTask(randomTask.id);
        print('Finished task: ${randomTask.headline}');
      }
    }

    // Export the modified cache
    try {
      final exportPath = await _cacheManager.exportToDefaultLocation();
      print('Exported modified cache to: $exportPath');

      // Show final statistics
      final stats = _cacheManager.getCacheStats();
      print('Final cache stats: $stats');

      // Clean up
      await _cacheManager.deleteExport(exportPath);
    } catch (e) {
      print('Error in batch operations example: $e');
    }
  }
}
