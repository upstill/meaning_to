import 'dart:convert';
import 'dart:async';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/models/link.dart';

/// Represents an item that can be imported from text data
class ImportItem {
  final String title;
  final String? description;
  final String? link;
  final String? domain;
  final Map<String, dynamic> metadata;

  /// True when the source marked this item as already done (e.g. a checked
  /// "[x]" box in a Google Keep checklist). Maps to Task.finished.
  final bool finished;

  ImportItem({
    required this.title,
    this.description,
    String? link,
    String? domain,
    this.metadata = const {},
    this.finished = false,
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
      links: link != null ? [link!] : <String>[],
      createdAt: now,
      suggestibleAt: now,
      finished: finished,
      shared:
          !category.tasksArePrivate, // Use category's tasksArePrivate setting
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
  /// Strips a leading checklist checkbox — as exported by Google Keep and
  /// similar note apps — from [line]: an optional markdown list marker
  /// ("- "/"* "), then "[ ]", "[]", "[x]" or "[X]", plus trailing whitespace.
  /// Returns the cleaned text and whether an "X" marked the item done.
  ///
  /// Deliberately leaves JSON arrays ("[{...}]") and markdown links
  /// ("[title](url)") untouched: the checkbox must contain only an optional
  /// x/X, and must not be immediately followed by "(".
  static ({String text, bool done}) stripChecklistCheckbox(String line) {
    final match = RegExp(r'^\s*(?:[-*]\s+)?\[\s*([xX]?)\s*\]\s*(?!\()')
        .firstMatch(line);
    if (match == null) return (text: line, done: false);
    final done = (match.group(1) ?? '').toLowerCase() == 'x';
    return (text: line.substring(match.end), done: done);
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
    print('=== TextImporter._parseTextData ===');
    print('Input text: "$text"');
    print('Text length: ${text.length}');
    print('Text bytes: ${text.codeUnits}');
    print('Contains \\r: ${text.contains('\r')}');
    print('Contains \\n: ${text.contains('\n')}');

    // Handle various line break formats including literal ^M characters
    List<String> lines;
    if (text.contains('\r') || text.contains('\n')) {
      // Split on actual line breaks
      lines = text
          .split('\r')
          .expand((line) => line.split('\n'))
          .where((line) => line.isNotEmpty)
          .toList();
    } else if (text.contains('^M')) {
      // Handle literal ^M characters (carriage return representation)
      lines = text.split('^M').where((line) => line.isNotEmpty).toList();
    } else {
      // No line breaks found, treat as single line
      lines = [text];
    }
    print('Split into ${lines.length} lines');
    for (int i = 0; i < lines.length; i++) {
      print('  Line $i: "${lines[i]}" (length: ${lines[i].length})');
    }

    final items = <ImportItem?>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      print('Processing line $i: "$line"');

      if (line.trim().isEmpty) {
        print('  -> Skipping empty line');
        continue;
      }

      ImportItem? item;
      final trimmedLine = line.trim();
      if (trimmedLine.startsWith('{') || trimmedLine.startsWith('[')) {
        print('  -> Attempting JSON parsing');
        // Try parsing as JSON
        try {
          final jsonData = jsonDecode(trimmedLine);
          if (jsonData is List) {
            // Handle JSON array - process all items
            print(
                '  -> JSON array detected, processing ${jsonData.length} items');
            for (final arrayItem in jsonData) {
              final parsedItem = parseJsonItem(arrayItem);
              if (parsedItem != null) {
                print(
                    '  -> Created item from JSON array: "${parsedItem.title}"');
                items.add(parsedItem);
              }
            }
            continue; // Skip adding a single item since we processed the array
          } else {
            item = parseJsonItem(jsonData);
            if (item != null) {
              print('  -> Created item from JSON: "${item.title}"');
            }
          }
        } catch (e) {
          print('  -> JSON parsing failed: $e, trying as plain text');
          // If JSON parsing fails, try as plain text
          item = importFromText(line);
        }
      } else {
        print('  -> Attempting plain text parsing');
        // Try parsing as plain text
        item = importFromText(line);
      }

      if (item != null) {
        print('  -> Created item: "${item.title}"');
        items.add(item);
      } else {
        print('  -> No item created for this line');
      }
    }

    print('Total items created: ${items.length}');
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
      final links = item.link != null ? [item.link!] : <String>[];
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
        finished: item.finished,
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
      final links = item.link != null ? [item.link!] : <String>[];
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
        finished: item.finished,
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
  static ImportItem? parseJsonItem(dynamic jsonData) {
    try {
      // Handle JSON object
      if (jsonData is Map<String, dynamic>) {
        return _parseJsonObject(jsonData);
      }

      // Handle string items — try JSON decode first, then fall back to importFromText
      if (jsonData is String) {
        try {
          final decoded = jsonDecode(jsonData);
          if (decoded is Map<String, dynamic>) {
            return _parseJsonObject(decoded);
          }
          if (decoded is List) {
            return null; // JSON arrays yield null
          }
        } catch (_) {
          // Not valid JSON, fall through to importFromText
        }
        return importFromText(jsonData);
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
  static ImportItem? importFromText(String text) {
    print('    importFromText called with: "$text"');

    if (text.trim().isEmpty) {
      print('    -> Text is empty, returning null');
      return null;
    }

    // Strip a leading checklist checkbox (e.g. Google Keep exports each item as
    // "[ ] Title" or "[x] Title"); a checked box marks the item already done.
    final checkbox = stripChecklistCheckbox(text.trim());
    final bool finished = checkbox.done;
    final trimmedInput = checkbox.text.trim();
    if (trimmedInput.isEmpty) {
      print('    -> Only a checkbox with no title, returning null');
      return null;
    }
    if (finished) {
      print('    -> Detected checked checklist item (finished)');
    }

    // 1. Try JSON object detection first (before any URL extraction)
    if (trimmedInput.startsWith('{')) {
      try {
        final jsonObj = jsonDecode(trimmedInput);
        if (jsonObj is Map<String, dynamic>) {
          print('    -> Detected JSON object, delegating to parseJsonItem');
          return parseJsonItem(jsonObj);
        }
      } catch (_) {
        // Not valid JSON, continue with normal processing
      }
    }

    // 2. Try JSON array detection — arrays yield null from importFromText
    if (trimmedInput.startsWith('[')) {
      try {
        jsonDecode(trimmedInput);
        print('    -> Detected JSON array, returning null');
        return null;
      } catch (_) {
        // Not valid JSON, continue
      }
    }

    // 3. Check if text is an HTML link (before URL extraction)
    if (trimmedInput.startsWith('<a') && trimmedInput.endsWith('</a>')) {
      print('    -> Attempting HTML link parsing');
      final (url, title) = LinkProcessor.parseHtmlLink(trimmedInput);
      if (url != trimmedInput) {
        final item = ImportItem(
          title: title ?? 'Link',
          link: url,
          metadata: {'source': 'html_link'},
          finished: finished,
        );
        print('    -> Created ImportItem from HTML link: "${item.title}"');
        return item;
      }
    }

    // 4. Check for markdown list prefix
    String processableText = trimmedInput;
    if (processableText.startsWith('- ') || processableText.startsWith('* ')) {
      processableText = processableText.substring(2);
      print('    -> Removed markdown list prefix, text now: "$processableText"');
    }

    // 5. Check for markdown link [title](url) with optional description (before URL extraction)
    final markdownMatch =
        RegExp(r'\[([^\]]+)\]\(([^)]*)\)(.*)').firstMatch(processableText);
    if (markdownMatch != null) {
      final title = markdownMatch.group(1) ?? 'Link';
      final url = markdownMatch.group(2) ?? '';
      final description = markdownMatch.group(3)?.trim();
      print('    -> Found markdown link - title: "$title", url: "$url"');

      final item = ImportItem(
        title: title,
        link: url.isEmpty ? null : url,
        description: description?.isNotEmpty == true ? description : null,
        metadata: {'source': 'markdown_link'},
        finished: finished,
      );
      print('    -> Created ImportItem from markdown: "${item.title}"');
      return item;
    }

    // 6. Extract URL from text
    String? extractedURL;
    final urlMatch = RegExp(r'https?://[^\s:]+').firstMatch(processableText);
    if (urlMatch != null) {
      extractedURL = urlMatch.group(0)!;
      print('    -> Found URL: $extractedURL');
      // Remove trailing colon if present
      if (extractedURL.endsWith(':')) {
        extractedURL = extractedURL.substring(0, extractedURL.length - 1);
      }
      final urlStart = urlMatch.start;
      final urlEnd = urlMatch.end;
      final beforeURL = processableText.substring(0, urlStart);
      final afterURL = processableText.substring(urlEnd);
      final colonMaybe =
          beforeURL.lastIndexOf(':') >= 0 || afterURL.contains(':') ? '' : ':';
      processableText = beforeURL + colonMaybe + afterURL;
      print('    -> Text after URL extraction: "$processableText"');
    }

    // 7. Check if text contains a colon separator (title: description)
    final colonIndex = processableText.indexOf(':');
    if (colonIndex > 0 &&
        !processableText.trim().startsWith('{') &&
        !processableText.trim().startsWith('[')) {
      final title = processableText.substring(0, colonIndex).trim();
      String description = processableText.substring(colonIndex + 1).trim();
      print(
          '    -> Found colon separator - title: "$title", description: "$description"');

      // Check for parentheses in the title and move them to description if description is empty
      String cleanTitle = title;
      if (description.isEmpty) {
        final parenthesesMatch = RegExp(r'\(([^)]+)\)').firstMatch(title);
        if (parenthesesMatch != null) {
          final parenthesesContent = parenthesesMatch.group(1)?.trim();
          if (parenthesesContent != null && parenthesesContent.isNotEmpty) {
            description = '($parenthesesContent)';
            // Remove the parentheses and their content from the title
            cleanTitle =
                title.replaceAll(RegExp(r'\s*\([^)]+\)\s*'), ' ').trim();
            print(
                '    -> Moved parentheses from title to description: "$description"');
            print('    -> Cleaned title: "$cleanTitle"');
          }
        }
      }

      if (cleanTitle.isNotEmpty) {
        final item = ImportItem(
          title: cleanTitle,
          description: description.isNotEmpty ? description : null,
          link: extractedURL,
          metadata: {
            'source': extractedURL != null
                ? 'plain_text_with_url'
                : 'plain_text_with_colon'
          },
          finished: finished,
        );
        print('    -> Created ImportItem with colon: "${item.title}"');
        return item;
      }
    }

    // 8. Check for parentheses in the text and move them to notes
    final trimmedText = processableText.trim();
    String? notesFromParentheses;
    String cleanTitle = trimmedText;

    final parenthesesMatch = RegExp(r'\(([^)]+)\)').firstMatch(trimmedText);
    if (parenthesesMatch != null) {
      final parenthesesContent = parenthesesMatch.group(1)?.trim();
      if (parenthesesContent != null && parenthesesContent.isNotEmpty) {
        notesFromParentheses = '($parenthesesContent)';
        cleanTitle =
            trimmedText.replaceAll(RegExp(r'\s*\([^)]+\)\s*'), ' ').trim();
        print('    -> Found parentheses content: $notesFromParentheses');
        print('    -> Cleaned title: "$cleanTitle"');
      }
    }

    // 9. Treat as plain text
    print('    -> Treating as plain text: "$cleanTitle"');
    final item = ImportItem(
      title: cleanTitle,
      description: notesFromParentheses,
      metadata: {'source': 'plain_text'},
      finished: finished,
    );
    print('    -> Created ImportItem from plain text: "${item.title}"');
    return item;
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
    final links = item.link != null ? [item.link!] : <String>[];

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
      finished: item.finished,
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
