import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';

void main() {
  group('CacheManager Revive Task Tests', () {
    late CacheManager cacheManager;

    setUp(() {
      cacheManager = CacheManager();
    });

    tearDown(() {
      cacheManager.clearCache();
    });

    test('should revive task and set suggestibleAt to now', () async {
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
        ownerId: 'user123',
        createdAt: DateTime.now(),
        suggestibleAt:
            DateTime.now().add(Duration(hours: 2)), // Deferred for 2 hours
        finished: false,
      );

      // Initialize cache
      cacheManager.initializeWithUnsavedCategory(category, [task], 'user123');

      // Verify task is deferred
      expect(task.suggestibleAt!.isAfter(DateTime.now()), true);

      // Revive the task
      await cacheManager.reviveTask(task.id);

      // Get the updated task from cache
      final updatedTask = cacheManager.currentTasks?.firstWhere(
        (t) => t.id == task.id,
        orElse: () => task,
      );

      expect(updatedTask, isNotNull);
      expect(updatedTask!.suggestibleAt, isNotNull);
      expect(
          updatedTask.suggestibleAt!
              .isBefore(DateTime.now().add(Duration(seconds: 1))),
          true);
      expect(
          updatedTask.suggestibleAt!
              .isAfter(DateTime.now().subtract(Duration(seconds: 1))),
          true);
    });

    test('should throw exception when task not found in cache', () async {
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
        ownerId: 'user123',
        createdAt: DateTime.now(),
        finished: false,
      );

      // Initialize cache
      cacheManager.initializeWithUnsavedCategory(category, [task], 'user123');

      // Try to revive a non-existent task
      expect(
        () => cacheManager.reviveTask(999),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Task not found in cache'),
        )),
      );
    });

    test('should revive task and update cache order', () async {
      // Create test data
      final category = Category(
        id: 1,
        headline: 'Test Category',
        ownerId: 'user123',
        createdAt: DateTime.now(),
      );

      final now = DateTime.now();
      final task1 = Task(
        id: 1,
        categoryId: 1,
        headline: 'Task 1',
        ownerId: 'user123',
        createdAt: now,
        suggestibleAt: now.add(Duration(hours: 1)), // Deferred
        finished: false,
      );

      final task2 = Task(
        id: 2,
        categoryId: 1,
        headline: 'Task 2',
        ownerId: 'user123',
        createdAt: now,
        suggestibleAt: null, // Available now
        finished: false,
      );

      // Initialize cache
      cacheManager.initializeWithUnsavedCategory(
          category, [task1, task2], 'user123');

      // Verify initial order (task2 should be first since it's available now)
      expect(cacheManager.currentTasks![0].id, 2);
      expect(cacheManager.currentTasks![1].id, 1);

      // Revive task1
      await cacheManager.reviveTask(task1.id);

      // After reviving, both tasks should have suggestibleAt set to current time
      // The order should be based on their suggestibleAt times (which should be very close)
      // Since both are now available, the order might be based on creation time or ID
      final updatedTask1 =
          cacheManager.currentTasks!.firstWhere((t) => t.id == 1);
      final updatedTask2 =
          cacheManager.currentTasks!.firstWhere((t) => t.id == 2);

      // Both tasks should now be available (suggestibleAt should be in the past or very recent)
      expect(
          updatedTask1.suggestibleAt!
              .isBefore(DateTime.now().add(Duration(seconds: 1))),
          true);
      expect(updatedTask2.suggestibleAt,
          isNull); // task2 still has null suggestibleAt

      // task2 should still be first since it has null suggestibleAt
      expect(cacheManager.currentTasks![0].id, 2);
    });
  });
}
