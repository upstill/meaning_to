import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';

void main() {
  group('CacheManager Unfinish Task Tests', () {
    late CacheManager cacheManager;

    setUp(() {
      cacheManager = CacheManager();
    });

    tearDown(() {
      cacheManager.clearCache();
    });

    test('should unfinish task and set finished to false', () async {
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
        finished: true, // Start as finished
      );

      // Initialize cache
      cacheManager.initializeWithUnsavedCategory(category, [task], 'user123');

      // Verify task is finished
      expect(task.finished, true);

      // Unfinish the task
      await cacheManager.unfinishTask(task.id);

      // Get the updated task from cache
      final updatedTask = cacheManager.currentTasks?.firstWhere(
        (t) => t.id == task.id,
        orElse: () => task,
      );

      expect(updatedTask, isNotNull);
      expect(updatedTask!.finished, false);
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
        finished: true,
      );

      // Initialize cache
      cacheManager.initializeWithUnsavedCategory(category, [task], 'user123');

      // Try to unfinish a non-existent task
      expect(
        () => cacheManager.unfinishTask(999),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Task not found in cache'),
        )),
      );
    });

    test('should unfinish task and update cache order', () async {
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
        finished: true, // Finished
      );

      final task2 = Task(
        id: 2,
        categoryId: 1,
        headline: 'Task 2',
        ownerId: 'user123',
        createdAt: now,
        finished: false, // Unfinished
      );

      // Initialize cache
      cacheManager.initializeWithUnsavedCategory(
          category, [task1, task2], 'user123');

      // Verify initial order (task2 should be first since it's unfinished)
      expect(cacheManager.currentTasks![0].id, 2);
      expect(cacheManager.currentTasks![1].id, 1);

      // Unfinish task1
      await cacheManager.unfinishTask(task1.id);

      // Verify task1 is now first (unfinished tasks come first)
      expect(cacheManager.currentTasks![0].id, 1);
      expect(cacheManager.currentTasks![1].id, 2);
    });
  });
}
