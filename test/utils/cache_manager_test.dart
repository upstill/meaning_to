import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'dart:convert';
import 'dart:io';

void main() {
  group('CacheManager Tests', () {
    late CacheManager cacheManager;

    setUp(() {
      cacheManager = CacheManager();
    });

    tearDown(() {
      cacheManager.clearCache();
    });

    group('Initialization Tests', () {
      test('should start with empty cache', () {
        expect(cacheManager.isInitialized, false);
        expect(cacheManager.currentCategory, null);
        expect(cacheManager.currentTasks, null);
        expect(cacheManager.taskCount, 0);
        expect(cacheManager.unfinishedTaskCount, 0);
      });

      test('should initialize with unsaved category and tasks', () {
        final category = Category(
          id: -1,
          headline: 'Test Category',
          ownerId: 'user123',
          createdAt: DateTime.now(),
        );

        final tasks = [
          Task(
            id: -1,
            categoryId: -1,
            headline: 'Task 1',
            notes: 'First task for test',
            ownerId: 'user123',
            createdAt: DateTime.now(),
            finished: false,
          ),
          Task(
            id: -2,
            categoryId: -1,
            headline: 'Task 2',
            notes: 'Second task for test',
            ownerId: 'user123',
            createdAt: DateTime.now(),
            finished: true,
          ),
        ];

        cacheManager.initializeWithUnsavedCategory(category, tasks, 'user123');

        expect(cacheManager.isInitialized, true);
        expect(cacheManager.currentCategory?.headline, 'Test Category');
        expect(cacheManager.taskCount, 2);
        expect(cacheManager.unfinishedTaskCount, 1);
        expect(cacheManager.isUnsavedCategory, true);
      });
    });

    group('Task Management Tests (Unsaved Category)', () {
      late Category testCategory;
      late List<Task> testTasks;

      setUp(() {
        testCategory = Category(
          id: 1,
          headline: 'Test Category',
          ownerId: 'user123',
          createdAt: DateTime.now(),
        );

        testTasks = [
          Task(
            id: 1,
            categoryId: 1,
            headline: 'Task 1',
            notes: 'First task',
            ownerId: 'user123',
            createdAt: DateTime.now(),
            finished: false,
          ),
          Task(
            id: 2,
            categoryId: 1,
            headline: 'Task 2',
            notes: 'Second task',
            ownerId: 'user123',
            createdAt: DateTime.now(),
            finished: true,
          ),
        ];

        cacheManager.initializeWithUnsavedCategory(
            testCategory, testTasks, 'user123');
      });

      test('should add new task to cache', () async {
        final newTask = Task(
          id: 3,
          categoryId: 1,
          headline: 'New Task',
          notes: 'New task notes',
          ownerId: 'user123',
          createdAt: DateTime.now(),
          finished: false,
        );

        await cacheManager.addTask(newTask);

        expect(cacheManager.taskCount, 3);
        expect(cacheManager.unfinishedTaskCount, 2);
      });

      test('should update existing task', () async {
        final updatedTask = Task(
          id: 1,
          categoryId: 1,
          headline: 'Updated Task 1',
          notes: 'Updated notes',
          ownerId: 'user123',
          createdAt: DateTime.now(),
          finished: true,
        );

        await cacheManager.updateTask(updatedTask);

        expect(cacheManager.taskCount, 2);
        expect(cacheManager.unfinishedTaskCount, 0);

        final updatedTaskInCache =
            cacheManager.currentTasks?.firstWhere((t) => t.id == 1);
        expect(updatedTaskInCache?.headline, 'Updated Task 1');
        expect(updatedTaskInCache?.finished, true);
      });

      test('should remove task from cache', () async {
        await cacheManager.removeTask(1);

        expect(cacheManager.taskCount, 1);
        expect(cacheManager.unfinishedTaskCount, 0);
        expect(cacheManager.currentTasks?.any((t) => t.id == 1), false);
      });

      test('should finish task', () async {
        await cacheManager.finishTask(1);

        expect(cacheManager.unfinishedTaskCount, 0);
        final finishedTask =
            cacheManager.currentTasks?.firstWhere((t) => t.id == 1);
        expect(finishedTask?.finished, true);
      });

      test('should reject task', () async {
        final originalTask =
            cacheManager.currentTasks?.firstWhere((t) => t.id == 1);
        expect(originalTask?.deferral, null);

        await cacheManager.rejectTask(1);

        final rejectedTask =
            cacheManager.currentTasks?.firstWhere((t) => t.id == 1);
        expect(rejectedTask?.deferral,
            120); // First deferral is 60, then doubled to 120
        expect(rejectedTask?.suggestibleAt, isNotNull);
      });

      test('should get random unfinished task', () {
        final randomTask = cacheManager.getRandomUnfinishedTask();
        expect(randomTask, isNotNull);
        expect(randomTask?.finished, false);
        expect(randomTask?.headline, 'Task 1');
      });

      test('should return null when no unfinished tasks available', () {
        // Finish all tasks by updating them in the cache
        final tasks = cacheManager.currentTasks;
        if (tasks != null) {
          for (int i = 0; i < tasks.length; i++) {
            if (!tasks[i].finished) {
              final finishedTask = Task(
                id: tasks[i].id,
                categoryId: tasks[i].categoryId,
                headline: tasks[i].headline,
                notes: tasks[i].notes,
                ownerId: tasks[i].ownerId,
                createdAt: tasks[i].createdAt,
                suggestibleAt: tasks[i].suggestibleAt,
                triggersAt: tasks[i].triggersAt,
                deferral: tasks[i].deferral,
                links: tasks[i].links,
                processedLinks: tasks[i].processedLinks,
                finished: true,
              );
              tasks[i] = finishedTask;
            }
          }
        }

        final randomTask = cacheManager.getRandomUnfinishedTask();
        expect(randomTask, null);
      });
    });

    group('Export/Import Tests (Unsaved Category Only)', () {
      late Category testCategory;
      late List<Task> testTasks;

      setUp(() {
        testCategory = Category(
          id: 1,
          headline: 'Test Export Category',
          ownerId: 'user123',
          createdAt: DateTime.now(),
        );

        testTasks = [
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

        cacheManager.initializeWithUnsavedCategory(
            testCategory, testTasks, 'user123');
      });

      test('should export cache to JSON', () async {
        final exportPath =
            await cacheManager.exportToJson('/tmp/test_export.json');

        expect(exportPath, '/tmp/test_export.json');

        // Verify the exported file exists and contains valid JSON
        final file = File(exportPath);
        expect(await file.exists(), true);

        final jsonString = await file.readAsString();
        final exportData = jsonDecode(jsonString) as Map<String, dynamic>;

        expect(exportData['category'], isNotNull);
        expect(exportData['tasks'], isNotNull);
        expect(exportData['userId'], 'user123');
        expect(exportData['isUnsavedCategory'], true);
        expect(exportData['metadata'], isNotNull);

        // Clean up
        await file.delete();
      });

      test('should export cache to default location', () async {
        final exportPath = await cacheManager.exportToDefaultLocation();

        expect(exportPath, contains('cache_export_'));
        expect(exportPath, endsWith('.json'));

        // Clean up
        await File(exportPath).delete();
      });

      test('should import cache from JSON text', () async {
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

        // Clear cache
        cacheManager.clearCache();

        // Import from JSON text
        final importSuccess = await cacheManager.importFromJson(jsonText);

        expect(importSuccess, true);
        expect(cacheManager.currentCategory?.headline, 'Imported from Text');
        expect(cacheManager.taskCount, 2);
        expect(cacheManager.unfinishedTaskCount, 1);

        final tasks = cacheManager.currentTasks;
        expect(tasks?.length, 2);
        expect(tasks?.any((t) => t.headline == 'Text Import Task 1'), true);
        expect(tasks?.any((t) => t.headline == 'Text Import Task 2'), true);
      });

      test('should fallback to TextImporter for invalid JSON', () async {
        const invalidJson = 'This is not valid JSON';

        final importSuccess = await cacheManager.importFromJson(invalidJson);

        expect(importSuccess, false);
        // The fallback should process the text through TextImporter
        // but not modify the cache since it's not valid cache export format
      });

      test('should fallback to TextImporter for JSON without category key',
          () async {
        const otherJson = '{"some": "other", "data": "here"}';

        final importSuccess = await cacheManager.importFromJson(otherJson);

        expect(importSuccess, false);
        // The fallback should process the text through TextImporter
      });
    });

    group('Cache Statistics and Validation Tests', () {
      test('should get cache statistics', () {
        final category = Category(
          id: 1,
          headline: 'Stats Test Category',
          ownerId: 'user123',
          createdAt: DateTime.now(),
        );

        final tasks = [
          Task(
            id: 1,
            categoryId: 1,
            headline: 'Unfinished Task',
            notes: 'Not done yet',
            ownerId: 'user123',
            createdAt: DateTime.now(),
            finished: false,
          ),
          Task(
            id: 2,
            categoryId: 1,
            headline: 'Finished Task',
            notes: 'All done',
            ownerId: 'user123',
            createdAt: DateTime.now(),
            finished: true,
          ),
        ];

        cacheManager.initializeWithUnsavedCategory(category, tasks, 'user123');

        final stats = cacheManager.getCacheStats();

        expect(stats['category']['headline'], 'Stats Test Category');
        expect(stats['category']['isUnsaved'], true);
        expect(stats['tasks']['total'], 2);
        expect(stats['tasks']['unfinished'], 1);
        expect(stats['tasks']['finished'], 1);
        expect(stats['userId'], 'user123');
        expect(stats['lastUpdated'], isNotNull);
      });

      test('should validate cache consistency', () {
        final category = Category(
          id: 1,
          headline: 'Validation Test Category',
          ownerId: 'user123',
          createdAt: DateTime.now(),
        );

        final tasks = [
          Task(
            id: 1,
            categoryId: 1, // Correct category ID
            headline: 'Valid Task',
            notes: 'Valid task',
            ownerId: 'user123',
            createdAt: DateTime.now(),
            finished: false,
          ),
        ];

        cacheManager.initializeWithUnsavedCategory(category, tasks, 'user123');

        expect(cacheManager.validateCache(), true);
      });

      test('should detect cache validation failures', () {
        final category = Category(
          id: 1,
          headline: 'Invalid Test Category',
          ownerId: 'user123',
          createdAt: DateTime.now(),
        );

        final tasks = [
          Task(
            id: 1,
            categoryId: 999, // Wrong category ID
            headline: 'Invalid Task',
            notes: 'Invalid task',
            ownerId: 'user123',
            createdAt: DateTime.now(),
            finished: false,
          ),
        ];

        cacheManager.initializeWithUnsavedCategory(category, tasks, 'user123');

        expect(cacheManager.validateCache(), false);
      });
    });

    group('File Management Tests', () {
      test('should delete export file', () async {
        final testFile = File('/tmp/test_delete.json');
        await testFile.writeAsString('{"test": "data"}');

        expect(await testFile.exists(), true);

        final deleted =
            await cacheManager.deleteExport('/tmp/test_delete.json');

        expect(deleted, true);
        expect(await testFile.exists(), false);
      });
    });
  });
}
