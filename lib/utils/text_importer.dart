import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:meaning_to/models/link.dart';

/// Enum defining the context for text import operations
enum ImportContext {
  /// Creating a new Category
  newCategory,

  /// Adding items to the Tasks of a Category
  addToCategory,

  /// Adding Links to a Task
  addToTask,
}

/// Represents an item that can be imported from text data
class ImportItem {
  final String title;
  final String? description;
  final String? link;
  final Map<String, dynamic> metadata;

  ImportItem({
    required this.title,
    this.description,
    this.link,
    this.metadata = const {},
  });

  @override
  String toString() =>
      'ImportItem(title: $title, description: $description, link: $link)';

  /// Converts the ImportItem to a Task
  Task toTask(int categoryId, {required String ownerId}) {
    final now = DateTime.now();
    return Task(
      id: now.millisecondsSinceEpoch, // Temporary ID
      categoryId: categoryId,
      ownerId: ownerId,
      headline: title,
      notes: description,
      links: link != null ? [link!] : null,
      createdAt: now,
      suggestibleAt: now,
      finished: false,
    );
  }

  /// Converts the ImportItem to a Link
  Link toLink() {
    return Link(
      title: title,
      url: link ?? '',
      description: description,
    );
  }
}

/// A class for importing items from text data sources
class TextImporter {
  /// Process text data into a list of ImportItems
  static Future<List<ImportItem?>> processTextData(
    String text,
    ImportContext context,
    int categoryId,
  ) async {
    final lines = text.split('\n');
    final items = <ImportItem?>[];

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      ImportItem? item;
      if (line.trim().startsWith('{')) {
        // Try parsing as JSON
        item = parseJsonItem(line);
      } else {
        // Try parsing as plain text
        item = parsePlainTextItem(line);
      }

      if (item != null) {
        items.add(item);
      }
    }

    return items;
  }

  /// Import items from clipboard data
  static Stream<ImportItem> importFromClipboard(
    String textData, {
    required ImportContext context,
    required int categoryId,
  }) {
    return processClipboardData(
      textData,
      context: context,
      categoryId: categoryId,
    );
  }

  /// Import items from a file
  static Future<Stream<ImportItem>?> importFromFile(
    String content, {
    required ImportContext context,
    required int categoryId,
  }) async {
    return processFileData(
      content,
      context: context,
      categoryId: categoryId,
    );
  }

  /// Process clipboard data into a stream of ImportItems
  static Stream<ImportItem> processClipboardData(
    String textData, {
    required ImportContext context,
    required int categoryId,
  }) async* {
    final items = await processTextData(textData, context, categoryId);
    for (final item in items) {
      if (item != null) {
        yield item;
      }
    }
  }

  /// Process file data into a stream of ImportItems
  static Stream<ImportItem> processFileData(
    String textData, {
    required ImportContext context,
    required int categoryId,
  }) async* {
    final items = await processTextData(textData, context, categoryId);
    for (final item in items) {
      if (item != null) {
        yield item;
      }
    }
  }

  /// Process text data for creating a new category
  static Stream<Task> processForNewCategory(
    String text, {
    required int categoryId,
    required String ownerId,
  }) async* {
    final now = DateTime.now();
    final items =
        await processTextData(text, ImportContext.newCategory, categoryId);
    for (final item in items) {
      if (item == null) continue;

      final tempId = now.millisecondsSinceEpoch;
      final links = item.link != null ? [item.link!] : null;

      yield Task(
        id: tempId,
        categoryId: categoryId,
        ownerId: ownerId,
        headline: item.title,
        notes: item.description,
        links: links,
        processedLinks: null,
        createdAt: now,
        suggestibleAt: now,
        finished: false,
      );
    }
  }

  /// Process text data for adding to an existing category
  static Stream<Task> processForAddToCategory(
    String text, {
    required int categoryId,
    required String ownerId,
  }) async* {
    final now = DateTime.now();
    final items =
        await processTextData(text, ImportContext.addToCategory, categoryId);
    for (final item in items) {
      if (item == null) continue;

      final tempId = now.millisecondsSinceEpoch;
      final links = item.link != null ? [item.link!] : null;

      yield Task(
        id: tempId,
        categoryId: categoryId,
        ownerId: ownerId,
        headline: item.title,
        notes: item.description,
        links: links,
        processedLinks: null,
        createdAt: now,
        suggestibleAt: now,
        finished: false,
      );
    }
  }

  /// Process text data for adding to an existing task
  static Stream<Link> processForAddToTask(String text) async* {
    final items = await processTextData(text, ImportContext.addToTask, 0);
    for (final item in items) {
      if (item == null || item.link == null) continue;
      yield item.toLink();
    }
  }

  /// Parses a JSON object into an ImportItem
  /// This method is public for testing purposes
  static ImportItem? parseJsonItem(String json) {
    try {
      final Map<String, dynamic> jsonData = jsonDecode(json);
      String? title = jsonData['title']?.toString() ??
          jsonData['name']?.toString() ??
          jsonData['headline']?.toString();

      if (title == null || title.trim().isEmpty) {
        return null;
      }

      return ImportItem(
        title: title.trim(),
        description: jsonData['description']?.toString() ??
            jsonData['notes']?.toString() ??
            jsonData['summary']?.toString(),
        link: jsonData['link']?.toString() ??
            jsonData['url']?.toString() ??
            jsonData['fullpath']?.toString(),
        metadata: jsonData,
      );
    } catch (e) {
      print('Error parsing JSON item: $e');
      return null;
    }
  }

  /// Parses plain text into an ImportItem
  /// This method is public for testing purposes
  static ImportItem? parsePlainTextItem(String text) {
    if (text.trim().isEmpty) {
      return null;
    }

    // Check if text is an HTML link
    if (text.trim().startsWith('<a') && text.trim().endsWith('</a>')) {
      final (url, title) = LinkProcessor.parseHtmlLink(text);
      if (url != text) {
        // If it was successfully parsed as an HTML link
        return ImportItem(
          title: title ?? 'Link',
          link: url,
          metadata: {'source': 'html_link'},
        );
      }
    }

    // Check if text is a markdown list item
    if (text.trim().startsWith('- ') || text.trim().startsWith('* ')) {
      text = text.trim().substring(2);
    }

    // Check if text contains a URL
    final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(text);
    if (urlMatch != null) {
      final url = urlMatch.group(0)!;
      final title = text.replaceAll(url, '').trim();

      return ImportItem(
        title: title.isNotEmpty ? title : 'Link',
        link: url,
        metadata: {'source': 'plain_text_with_url'},
      );
    }

    // Check if text looks like a markdown link [title](url)
    final markdownMatch = RegExp(r'\[([^\]]+)\]\(([^)]+)\)').firstMatch(text);
    if (markdownMatch != null) {
      final title = markdownMatch.group(1) ?? 'Link';
      final url = markdownMatch.group(2) ?? '';

      return ImportItem(
        title: title,
        link: url,
        metadata: {'source': 'markdown_link'},
      );
    }

    // Treat as plain text
    return ImportItem(
      title: text.trim(),
      metadata: {'source': 'plain_text'},
    );
  }

  /// Convert an ImportItem to a Task
  static Task? importItemToTask(
    ImportItem item, {
    required int categoryId,
    required String ownerId,
  }) {
    if (item.title.trim().isEmpty) {
      return null;
    }

    final now = DateTime.now();
    final links = item.link != null ? [item.link!] : null;

    return Task(
      id: now.millisecondsSinceEpoch,
      categoryId: categoryId,
      ownerId: ownerId,
      headline: item.title,
      notes: item.description,
      links: links,
      processedLinks: null,
      createdAt: now,
      suggestibleAt: now,
      finished: false,
    );
  }

  /// Helper method to convert ImportItem to link string (for add to task context)
  static String? importItemToLink(ImportItem item) {
    if (item.link != null) {
      if (item.link!.startsWith('http')) {
        return '<a href="${item.link}">${item.title}</a>';
      } else {
        return item.link!;
      }
    }
    return null;
  }
}
