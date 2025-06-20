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

/// Represents an item that can be imported from text data
class ImportItem {
  final String title;
  final String? description;
  final String? link;
  final String? domain;
  final Map<String, dynamic> metadata;

  ImportItem({
    required this.title,
    this.description,
    String? link,
    String? domain,
    this.metadata = const {},
  })  : link =
            (link != null && TextImporter.extractedDomainFromUrl(link) != null)
                ? link
                : null,
        domain = domain ??
            ((link != null && TextImporter.extractedDomainFromUrl(link) != null)
                ? TextImporter.extractedDomainFromUrl(link)
                : null);

  @override
  String toString() =>
      'ImportItem(title: $title, description: $description, link: $link, domain: $domain)';

  /// Converts the ImportItem to a Task
  Task toTask(Category category, {required String ownerId}) {
    final now = DateTime.now();
    return Task(
      id: now.millisecondsSinceEpoch, // Temporary ID
      categoryId: category.id,
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
  /// Import items from text data
  static Stream<ImportItem> importFromText(
    String textData, {
    Category? category,
    Task? task,
  }) {
    return processTextData(
      textData,
      category: category,
      task: task,
    );
  }

  /// Process text data into a stream of ImportItems
  static Stream<ImportItem> processTextData(
    String textData, {
    Category? category,
    Task? task,
  }) async* {
    final items = await _parseTextData(textData, category);
    for (final item in items) {
      if (item != null) {
        yield item;
      }
    }
  }

  /// Parse text data into a list of ImportItems
  static Future<List<ImportItem?>> _parseTextData(
    String text,
    Category? category,
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

  /// Process text data for creating a new category
  static Stream<Task> processForNewCategory(
    String text, {
    required Category category,
    required String ownerId,
  }) async* {
    final now = DateTime.now();
    final items = await _parseTextData(text, category);
    for (final item in items) {
      if (item == null) continue;
      final tempId = now.millisecondsSinceEpoch;
      final links = item.link != null ? [item.link!] : null;
      yield Task(
        id: tempId,
        categoryId: category.id,
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
    required Category category,
    required String ownerId,
  }) async* {
    final now = DateTime.now();
    final items = await _parseTextData(text, category);
    for (final item in items) {
      if (item == null) continue;
      final tempId = now.millisecondsSinceEpoch;
      final links = item.link != null ? [item.link!] : null;
      yield Task(
        id: tempId,
        categoryId: category.id,
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
    final items = await _parseTextData(text, null);
    for (final item in items) {
      if (item == null || item.link == null) continue;
      yield item.toLink();
    }
  }

  /// Process text data with context determined by optional parameters
  /// - If task is specified: process as addToTask
  /// - If category is specified: process as addToCategory
  /// - If neither is specified: process as newCategory
  static Stream<dynamic> processWithContext(
    String text, {
    Category? category,
    Task? task,
    String? ownerId,
  }) async* {
    if (task != null) {
      // Add to task context
      yield* processForAddToTask(text);
    } else if (category != null) {
      // Add to category context
      if (ownerId == null) {
        throw ArgumentError('ownerId is required when category is specified');
      }
      yield* processForAddToCategory(
        text,
        category: category,
        ownerId: ownerId,
      );
    } else {
      // New category context
      if (ownerId == null) {
        throw ArgumentError('ownerId is required for new category context');
      }
      throw ArgumentError(
          'A Category must be provided for new category context');
    }
  }

  /// Parses a JSON object or array into an ImportItem
  /// This method is public for testing purposes
  static ImportItem? parseJsonItem(String json) {
    try {
      final dynamic jsonData = jsonDecode(json);

      // Handle JSON array
      if (jsonData is List) {
        for (final item in jsonData) {
          if (item is Map<String, dynamic>) {
            final result = _parseJsonObject(item);
            if (result != null) return result;
          } else if (item is String) {
            final result = parsePlainTextItem(item);
            if (result != null) return result;
          }
        }
        return null;
      }

      // Handle JSON object
      if (jsonData is Map<String, dynamic>) {
        return _parseJsonObject(jsonData);
      }

      return null;
    } catch (e) {
      print('Error parsing JSON item: $e');
      return null;
    }
  }

  /// Helper method to parse a JSON object into an ImportItem
  static ImportItem? _parseJsonObject(Map<String, dynamic> jsonData) {
    String? title = jsonData['title']?.toString() ??
        jsonData['name']?.toString() ??
        jsonData['headline']?.toString();

    if (title == null || title.trim().isEmpty) {
      return null;
    }

    // First, try to extract the link
    String? link = jsonData['link']?.toString() ??
        jsonData['url']?.toString() ??
        jsonData['fullpath']?.toString();

    // If no direct link found, try to assemble from host/domain + path
    if (link == null) {
      final host =
          jsonData['host']?.toString() ?? jsonData['domain']?.toString();
      final path = jsonData['path']?.toString();

      if (host != null && path != null) {
        final scheme = jsonData['scheme']?.toString() ?? 'https';
        link = '$scheme://$host$path';
      }
    }

    return ImportItem(
      title: title.trim(),
      description: jsonData['description']?.toString() ??
          jsonData['notes']?.toString() ??
          jsonData['summary']?.toString(),
      link: link,
      domain: jsonData['domain']?.toString(),
      metadata: jsonData,
    );
  }

  /// Parses plain text into an ImportItem
  /// This method is public for testing purposes
  static ImportItem? parsePlainTextItem(String text) {
    if (text.trim().isEmpty) {
      return null;
    }

    // Check if text is JSON and delegate to parseJsonItem
    final trimmedText = text.trim();
    if (trimmedText.startsWith('{') || trimmedText.startsWith('[')) {
      return parseJsonItem(trimmedText);
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
    required Category category,
    required String ownerId,
  }) {
    if (item.title.trim().isEmpty) {
      return null;
    }

    final now = DateTime.now();
    final links = item.link != null ? [item.link!] : null;

    return Task(
      id: now.millisecondsSinceEpoch,
      categoryId: category.id,
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

  /// Extract domain from a URL, stripping common subdomains like 'www.'
  static String? extractedDomainFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.isEmpty) return null;
      final domain = uri.host.toLowerCase();
      final isIp = RegExp(r'^(\d{1,3}\.){3}\d{1,3}\$').hasMatch(domain);
      // Only accept hosts that look like valid domains (e.g. example.com, not not-a-valid-url)
      final isValidDomain =
          RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$')
                  .hasMatch(domain) &&
              domain.split('.').last.length >= 2;
      if (!isValidDomain && !isIp) return null;
      final commonSubdomains = [
        'www.',
        'm.',
        'mobile.',
        'api.',
        'beta.',
        'dev.',
        'staging.'
      ];
      for (final subdomain in commonSubdomains) {
        if (domain.startsWith(subdomain)) {
          return domain.substring(subdomain.length);
        }
      }
      return domain;
    } catch (e) {
      print('Error extracting domain from URL: $e');
      return null;
    }
  }
}
