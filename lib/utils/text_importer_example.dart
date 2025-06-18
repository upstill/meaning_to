import 'dart:async';
import 'package:meaning_to/utils/text_importer.dart';
import 'package:meaning_to/models/task.dart';

/// Example usage of the TextImporter module
class TextImporterExample {
  /// Example: Import from clipboard for creating a new category
  static Future<void> importFromClipboardForNewCategory() async {
    print('=== Importing from Clipboard for New Category ===');

    final stream = TextImporter.importFromClipboard(
      'Test Task 1\nhttps://example.com/movie2 Movie Task 2',
      context: ImportContext.newCategory,
      categoryId: 1,
    );

    await for (final item in stream) {
      print('Received item: $item');
      print('Domain: ${item.extractedDomain}');
      // Here you would typically create a Task from the item
      // final task = TextImporter.importItemToTask(item, categoryId, ownerId);
    }
  }

  /// Example: Import from file for adding to existing category
  static Future<void> importFromFileForAddToCategory() async {
    print('=== Importing from File for Add to Category ===');

    final stream = await TextImporter.importFromFile(
      'Test Task 1\n{"title": "JSON Task", "link": "https://example.com", "domain": "custom-domain.com"}',
      context: ImportContext.addToCategory,
      categoryId: 1,
    );

    if (stream == null) {
      print('File selection was cancelled');
      return;
    }

    await for (final item in stream) {
      print('Received item: $item');
      print('Domain: ${item.extractedDomain}');
      // Here you would typically add the item to existing category tasks
    }
  }

  /// Example: Import from clipboard for adding links to a task
  static Future<void> importFromClipboardForAddToTask() async {
    print('=== Importing from Clipboard for Add to Task ===');

    final stream = TextImporter.importFromClipboard(
      'https://example.com/link1\n[Markdown Link](https://example.com/link2)',
      context: ImportContext.addToTask,
      categoryId: 1,
    );

    await for (final item in stream) {
      print('Received item: $item');
      print('Domain: ${item.extractedDomain}');
      // Here you would typically convert the item to a link
      final link = TextImporter.importItemToLink(item);
      if (link != null) {
        print('Generated link: $link');
      }
    }
  }

  /// Example: Process all items at once (alternative to stream)
  static Future<List<ImportItem>> importAllFromClipboard(
      ImportContext context) async {
    final stream = TextImporter.importFromClipboard(
      'Test Task 1\nhttps://example.com/movie2 Movie Task 2',
      context: context,
      categoryId: 1,
    );
    final items = <ImportItem>[];

    await for (final item in stream) {
      items.add(item);
    }

    return items;
  }

  /// Example: Process items with custom filtering
  static Future<void> importWithFilter(ImportContext context) async {
    final stream = TextImporter.importFromClipboard(
      'Test Task 1\nhttps://example.com/movie2 Movie Task 2',
      context: context,
      categoryId: 1,
    );

    await for (final item in stream.where((item) => item.title.length > 3)) {
      print('Filtered item: $item');
      print('Domain: ${item.extractedDomain}');
    }
  }

  /// Example: Convert imported items to Tasks for a new category
  static Future<List<Task>> convertToTasks(
    List<ImportItem> items,
    int categoryId,
    String ownerId,
  ) async {
    final tasks = <Task>[];

    for (final item in items) {
      final task = TextImporter.importItemToTask(
        item,
        categoryId: categoryId,
        ownerId: ownerId,
      );
      if (task != null) {
        tasks.add(task);
      }
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
    print('Item 1 - Explicit domain: ${item1.extractedDomain}');

    // Domain automatically extracted from link
    final item2 = ImportItem(
      title: 'Movie with Auto-Extracted Domain',
      link: 'https://letterboxd.com/movie',
    );
    print('Item 2 - Extracted domain: ${item2.extractedDomain}');

    // No domain (no link)
    final item3 = ImportItem(
      title: 'Movie without Link',
    );
    print('Item 3 - No domain: ${item3.extractedDomain}');
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
