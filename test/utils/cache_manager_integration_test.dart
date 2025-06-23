import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';

void main() {
  group('CacheManager Integration Tests', () {
    late CacheManager cacheManager;

    setUp(() {
      cacheManager = CacheManager();
    });

    tearDown(() {
      cacheManager.clearCache();
    });

    test('should reject task and update deferral using CacheManager', () async {
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
        deferral: null, // No initial deferral
        finished: false,
      );

      // Initialize cache with unsaved category and task
      cacheManager.initializeWithUnsavedCategory(category, [task], 'user123');

      // Verify initial state
      expect(cacheManager.taskCount, 1);
      expect(cacheManager.unfinishedTaskCount, 1);

      // Reject the task
      await cacheManager.rejectTask(task.id);

      // Verify the task was updated
      final updatedTask = cacheManager.currentTasks?.firstWhere(
        (t) => t.id == task.id,
        orElse: () => task,
      );

      expect(updatedTask, isNotNull);
      expect(updatedTask!.deferral, 120); // Should be doubled from 60 to 120
      expect(updatedTask.suggestibleAt, isNotNull);
      expect(updatedTask.suggestibleAt!.isAfter(DateTime.now()), true);

      // Reject again to test doubling
      await cacheManager.rejectTask(task.id);

      final doubleRejectedTask = cacheManager.currentTasks?.firstWhere(
        (t) => t.id == task.id,
        orElse: () => task,
      );

      expect(doubleRejectedTask!.deferral,
          240); // Should be doubled from 120 to 240
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
        deferral: 30, // Existing deferral of 30 minutes
        finished: false,
      );

      // Initialize cache
      cacheManager.initializeWithUnsavedCategory(category, [task], 'user123');

      // Reject the task
      await cacheManager.rejectTask(task.id);

      // Verify the deferral was doubled
      final updatedTask = cacheManager.currentTasks?.firstWhere(
        (t) => t.id == task.id,
        orElse: () => task,
      );

      expect(updatedTask!.deferral, 60); // Should be doubled from 30 to 60
    });
  });
}
