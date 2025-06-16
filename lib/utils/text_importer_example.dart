import 'dart:async';
import 'package:meaning_to/utils/text_importer.dart';
import 'package:meaning_to/models/task.dart';

/// Example usage of the TextImporter module
class TextImporterExample {
  /// Example: Import from clipboard for creating a new category
  static Future<void> importFromClipboardForNewCategory() async {
    print('=== Importing from Clipboard for New Category ===');

    final controller =
        TextImporter.importFromClipboard(ImportContext.newCategory);

    controller.stream.listen(
      (item) {
        print('Received item: $item');
        // Here you would typically create a Task from the item
        // final task = TextImporter.importItemToTask(item, categoryId, ownerId);
      },
      onError: (error) {
        print('Error: $error');
      },
      onDone: () {
        print('Import completed');
      },
    );
  }

  /// Example: Import from file for adding to existing category
  static Future<void> importFromFileForAddToCategory() async {
    print('=== Importing from File for Add to Category ===');

    final controller =
        await TextImporter.importFromFile(ImportContext.addToCategory);

    if (controller == null) {
      print('File selection was cancelled');
      return;
    }

    controller.stream.listen(
      (item) {
        print('Received item: $item');
        // Here you would typically add the item to existing category tasks
      },
      onError: (error) {
        print('Error: $error');
      },
      onDone: () {
        print('Import completed');
      },
    );
  }

  /// Example: Import from clipboard for adding links to a task
  static Future<void> importFromClipboardForAddToTask() async {
    print('=== Importing from Clipboard for Add to Task ===');

    final controller =
        TextImporter.importFromClipboard(ImportContext.addToTask);

    controller.stream.listen(
      (item) {
        print('Received item: $item');
        // Here you would typically convert the item to a link
        final link = TextImporter.importItemToLink(item);
        if (link != null) {
          print('Generated link: $link');
        }
      },
      onError: (error) {
        print('Error: $error');
      },
      onDone: () {
        print('Import completed');
      },
    );
  }

  /// Example: Process all items at once (alternative to stream)
  static Future<List<ImportItem>> importAllFromClipboard(
      ImportContext context) async {
    final controller = TextImporter.importFromClipboard(context);
    final items = <ImportItem>[];

    await for (final item in controller.stream) {
      items.add(item);
    }

    return items;
  }

  /// Example: Process items with custom filtering
  static Future<void> importWithFilter(ImportContext context) async {
    final controller = TextImporter.importFromClipboard(context);

    controller.stream
        .where((item) => item.title.length > 3) // Filter out very short titles
        .listen(
      (item) {
        print('Filtered item: $item');
      },
      onError: (error) {
        print('Error: $error');
      },
      onDone: () {
        print('Import completed');
      },
    );
  }

  /// Example: Convert imported items to Tasks for a new category
  static Future<List<Task>> convertToTasks(
    List<ImportItem> items,
    int categoryId,
    String ownerId,
  ) async {
    final tasks = <Task>[];

    for (final item in items) {
      final task = TextImporter.importItemToTask(item, categoryId, ownerId);
      if (task != null) {
        tasks.add(task);
      }
    }

    return tasks;
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
*/
