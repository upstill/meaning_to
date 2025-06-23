import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/cache_manager.dart';

void main() {
  group('Task CacheManager Integration Tests', () {
    late CacheManager cacheManager;

    setUp(() {
      cacheManager = CacheManager();
      Task.clearCache();
    });

    tearDown(() {
      cacheManager.clearCache();
      Task.clearCache();
    });

    test('should integrate Task class with CacheManager for task rejection',
        () async {
      // Create test data
      final category = Category(
        id: 1,
        headline: 'Test Category',
        ownerId: 'user123',
        createdAt: DateTime.now(),
      );

      final task = Task(
        id: 1,
        categoryId: 1,
        headline: 'Test Task',
        notes: 'Test notes',
        ownerId: 'user123',
        createdAt: DateTime.now(),
        suggestibleAt: DateTime.now(),
        deferral: null,
        finished: false,
      );

      // Set up Task class state
      Task.updateCurrentTask(task);

      // Initialize CacheManager with the same data
      cacheManager.initializeWithUnsavedCategory(category, [task], 'user123');

      // Verify both are in sync
      expect(Task.currentTask?.id, task.id);
      expect(cacheManager.currentTasks?.first.id, task.id);

      // Reject task using CacheManager
      await cacheManager.rejectTask(task.id);

      // Verify CacheManager updated the task
      final updatedTaskInCache = cacheManager.currentTasks?.first;
      expect(updatedTaskInCache!.deferral,
          120); // Should be doubled from 60 to 120

      // Verify Task class state is updated
      expect(Task.currentTask?.deferral, 120);
      expect(Task.currentTask?.suggestibleAt, isNotNull);
    });

    test('should handle task rejection with existing deferral', () async {
      // Create test data with existing deferral
      final category = Category(
        id: 1,
        headline: 'Test Category',
        ownerId: 'user123',
        createdAt: DateTime.now(),
      );

      final task = Task(
        id: 1,
        categoryId: 1,
        headline: 'Test Task',
        notes: 'Test notes',
        ownerId: 'user123',
        createdAt: DateTime.now(),
        suggestibleAt: DateTime.now(),
        deferral: 30, // Existing deferral
        finished: false,
      );

      // Set up Task class state
      Task.updateCurrentTask(task);

      // Initialize CacheManager
      cacheManager.initializeWithUnsavedCategory(category, [task], 'user123');

      // Reject task using CacheManager
      await cacheManager.rejectTask(task.id);

      // Verify deferral was doubled
      final updatedTaskInCache = cacheManager.currentTasks?.first;
      expect(
          updatedTaskInCache!.deferral, 60); // Should be doubled from 30 to 60

      // Verify Task class state is updated
      expect(Task.currentTask?.deferral, 60);
    });
  });
}
