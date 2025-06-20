import 'dart:async';
import 'package:meaning_to/utils/text_importer.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/models/category.dart';

/// Example usage of the TextImporter module
class TextImporterExample {
  /// Example: Import from text for creating a new category
  static Future<void> importFromTextForNewCategory() async {
    print('=== Importing from Text for New Category ===');
    final category = Category(
        id: 1,
        ownerId: 'user123',
        headline: 'Test Category',
        createdAt: DateTime.now());
    final stream = TextImporter.processTextData(
      'Test Task 1\nhttps://example.com/movie2 Movie Task 2',
      category: category,
    );

    await for (final item in stream) {
      print('Received item: $item');
      print('Domain: ${item.domain}');
      // Here you would typically create a Task from the item
      final task = item.toTask(category, ownerId: 'user123');
      print('Generated task: ${task.headline}');
    }
  }

  /// Example: Import from text for adding to existing category
  static Future<void> importFromTextForAddToCategory() async {
    print('=== Importing from Text for Add to Category ===');
    final category = Category(
        id: 1,
        ownerId: 'user123',
        headline: 'Test Category',
        createdAt: DateTime.now());
    final stream = TextImporter.processTextData(
      'Test Task 1\n{"title": "JSON Task", "link": "https://example.com", "domain": "custom-domain.com"}',
      category: category,
    );

    await for (final item in stream) {
      print('Received item: $item');
      print('Domain: ${item.domain}');
      // Here you would typically add the item to existing category tasks
      final task = item.toTask(category, ownerId: 'user123');
      print('Generated task: ${task.headline}');
    }
  }

  /// Example: Import from text for adding links to a task
  static Future<void> importFromTextForAddToTask() async {
    print('=== Importing from Text for Add to Task ===');

    final task = Task(
      id: 1,
      categoryId: 1,
      ownerId: 'user123',
      headline: 'Test Task',
      notes: null,
      links: null,
      processedLinks: null,
      createdAt: DateTime.now(),
      suggestibleAt: DateTime.now(),
      finished: false,
    );

    final stream = TextImporter.processTextData(
      'https://example.com/link1\n[Markdown Link](https://example.com/link2)',
      task: task,
    );

    await for (final item in stream) {
      print('Received item: $item');
      print('Domain: ${item.domain}');
      // Here you would typically convert the item to a link
      final link = item.toLink();
      print('Generated link: ${link.title} - ${link.url}');
    }
  }

  /// Example: Process all items at once (alternative to stream)
  static Future<List<ImportItem>> importAllFromText({
    Category? category,
    Task? task,
  }) async {
    final stream = TextImporter.processTextData(
      'Test Task 1\nhttps://example.com/movie2 Movie Task 2',
      category: category,
      task: task,
    );
    final items = <ImportItem>[];

    await for (final item in stream) {
      items.add(item);
    }

    return items;
  }

  /// Example: Process items with custom filtering
  static Future<void> importWithFilter({
    Category? category,
    Task? task,
  }) async {
    final stream = TextImporter.processTextData(
      'Test Task 1\nhttps://example.com/movie2 Movie Task 2',
      category: category,
      task: task,
    );

    await for (final item in stream.where((item) => item.title.length > 3)) {
      print('Filtered item: $item');
      print('Domain: ${item.domain}');
    }
  }

  /// Example: Use the new processWithContext method
  static Future<void> processWithContextExample() async {
    print('=== Processing with Context Examples ===');
    final category = Category(
        id: 1,
        ownerId: 'user123',
        headline: 'Test Category',
        createdAt: DateTime.now());
    // New category context
    print('--- New Category Context ---');
    final newCategoryStream = TextImporter.processWithContext(
      'Test Task 1\nhttps://example.com/movie2 Movie Task 2',
      category: category,
      ownerId: 'user123',
    );

    await for (final item in newCategoryStream) {
      print('New category item: $item');
    }

    // Add to category context
    print('--- Add to Category Context ---');
    final addToCategoryStream = TextImporter.processWithContext(
      'Test Task 1\nhttps://example.com/movie2 Movie Task 2',
      category: category,
      ownerId: 'user123',
    );

    await for (final item in addToCategoryStream) {
      print('Add to category item: $item');
    }

    // Add to task context (task specified)
    print('--- Add to Task Context ---');
    final task = Task(
      id: 1,
      categoryId: 1,
      ownerId: 'user123',
      headline: 'Test Task',
      notes: null,
      links: null,
      processedLinks: null,
      createdAt: DateTime.now(),
      suggestibleAt: DateTime.now(),
      finished: false,
    );

    final addToTaskStream = TextImporter.processWithContext(
      'https://example.com/link1\n[Markdown Link](https://example.com/link2)',
      task: task,
    );

    await for (final item in addToTaskStream) {
      print('Add to task item: $item');
    }
  }

  /// Example: Convert imported items to Tasks for a new category
  static Future<List<Task>> convertToTasks(
    List<ImportItem> items,
    Category category,
    String ownerId,
  ) async {
    final tasks = <Task>[];

    for (final item in items) {
      final task = item.toTask(category, ownerId: ownerId);
      tasks.add(task);
    }

    return tasks;
  }

  /// Example: Demonstrate domain handling
  static void demonstrateDomainHandling() {
    print('=== Domain Handling Examples ===');

    // Domain explicitly set
    final item1 = ImportItem(
      title: 'Movie with Custom Domain',
      link: 'https://example.com/movie',
      domain: 'custom-domain.com',
    );
    print('Item 1 - Explicit domain: ${item1.domain}');

    // Domain automatically extracted from link
    final item2 = ImportItem(
      title: 'Movie with Auto-Extracted Domain',
      link: 'https://letterboxd.com/movie',
    );
    print('Item 2 - Extracted domain: ${item2.domain}');

    // No domain (no link)
    final item3 = ImportItem(
      title: 'Movie without Link',
    );
    print('Item 3 - No domain: ${item3.domain}');
  }
}

/// Example data formats that the TextImporter can handle:

/*
1. Plain text (one item per line):
Movie Title 1
Movie Title 2
https://example.com/movie3 Movie Title 3

2. JSON objects (one per line):
{"title": "Movie 1", "description": "A great movie", "link": "https://example.com/movie1"}
{"title": "Movie 2", "notes": "Another great movie", "url": "https://example.com/movie2"}
{"title": "Movie 3", "link": "https://example.com/movie3", "domain": "custom-domain.com"}

3. JSON array:
[{"title": "Movie 1"}, {"title": "Movie 2", "link": "https://example.com/movie2"}]

4. Markdown links:
[Inception](https://example.com/inception)
[The Matrix](https://example.com/matrix)

5. URLs with titles:
https://example.com/movie1 Movie Title 1
https://example.com/movie2 Movie Title 2

6. Mixed formats:
Movie Title 1
{"title": "Movie 2", "link": "https://example.com/movie2"}
[Inception](https://example.com/inception)
https://example.com/movie4 Movie Title 4

7. Domain handling examples:
{"title": "Movie with custom domain", "link": "https://example.com/movie", "domain": "custom-domain.com"}
{"title": "Movie with auto-extracted domain", "link": "https://letterboxd.com/movie"}
*/
