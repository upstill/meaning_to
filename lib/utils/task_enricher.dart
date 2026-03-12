import 'dart:convert';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/link_processor.dart';

/// Specification for what fields should be enriched in a Task
class TaskEnrichmentSpec {
  /// Whether to enrich and validate links (fetch titles, descriptions, icons)
  final bool enrichLinks;

  /// Whether to generate descriptions from links (JustWatch, Letterboxd, etc.)
  final bool generateDescription;

  /// Whether to validate and clean the headline
  final bool cleanHeadline;

  /// Whether to process and validate the notes field
  final bool processNotes;

  /// Whether to ensure processedLinks are populated from links
  final bool ensureProcessedLinks;

  const TaskEnrichmentSpec({
    this.enrichLinks = false,
    this.generateDescription = false,
    this.cleanHeadline = false,
    this.processNotes = false,
    this.ensureProcessedLinks = false,
  });

  /// Preset for minimal enrichment (just basic validation)
  static const minimal = TaskEnrichmentSpec(
    cleanHeadline: true,
  );

  /// Preset for link-focused enrichment
  static const withLinks = TaskEnrichmentSpec(
    enrichLinks: true,
    ensureProcessedLinks: true,
    cleanHeadline: true,
  );

  /// Preset for full enrichment (everything)
  static const full = TaskEnrichmentSpec(
    enrichLinks: true,
    generateDescription: true,
    cleanHeadline: true,
    processNotes: true,
    ensureProcessedLinks: true,
  );

  /// Preset for web content enrichment (JustWatch, Letterboxd, etc.)
  static const webContent = TaskEnrichmentSpec(
    enrichLinks: true,
    generateDescription: true,
    ensureProcessedLinks: true,
    cleanHeadline: true,
  );
}

/// Results of task enrichment operation
class TaskEnrichmentResult {
  final Task enrichedTask;
  final List<String> enrichedFields;
  final List<String> errors;
  final bool hasChanges;

  const TaskEnrichmentResult({
    required this.enrichedTask,
    required this.enrichedFields,
    required this.errors,
    required this.hasChanges,
  });
}

/// Core task enrichment service
class TaskEnricher {
  /// Enrich an existing Task object according to the specification
  static Future<TaskEnrichmentResult> enrichTask(
    Task task,
    TaskEnrichmentSpec spec,
  ) async {
    final enrichedFields = <String>[];
    final errors = <String>[];
    bool hasChanges = false;

    // Start with a copy of the original task
    String? newHeadline = task.headline;
    String? newNotes = task.notes;
    List<String>? newLinks = task.links;
    List<ProcessedLink>? newProcessedLinks = task.processedLinks;

    try {
      // 1. Clean headline if requested
      if (spec.cleanHeadline) {
        final cleanedHeadline = await _cleanHeadline(task.headline);
        if (cleanedHeadline != task.headline) {
          newHeadline = cleanedHeadline;
          enrichedFields.add('headline');
          hasChanges = true;
        }
      }

      // 1a. Check if headline is a URL and extract it
      final urlExtractionResult =
          await _extractUrlFromHeadline(newHeadline);
      if (urlExtractionResult != null) {
        newHeadline = urlExtractionResult.title;
        if (newLinks == null) {
          newLinks = [urlExtractionResult.htmlLink];
        } else {
          newLinks = [...newLinks, urlExtractionResult.htmlLink];
        }
        enrichedFields.addAll(['headline', 'links']);
        hasChanges = true;
      }

      // 2. Extract headline from links if task has no headline
      bool headlineExtractedFromHtmlLink = false;
      if ((newHeadline.trim().isEmpty) &&
          task.links != null &&
          task.links!.isNotEmpty) {
        final extractionResult =
            await _extractHeadlineFromLinksWithDetails(task.links!);
        if (extractionResult != null && extractionResult.headline.isNotEmpty) {
          newHeadline = extractionResult.headline;
          enrichedFields.add('headline');
          hasChanges = true;
          headlineExtractedFromHtmlLink = extractionResult.fromHtmlLink;
        }
      }

      // 3. Enrich links if requested (but skip if we already used HTML link for headline)
      if (spec.enrichLinks &&
          task.links != null &&
          task.links!.isNotEmpty &&
          !headlineExtractedFromHtmlLink) {
        final linkResults = await _enrichLinks(task.links!);
        if (linkResults.hasChanges) {
          newLinks = linkResults.enrichedLinks;
          newProcessedLinks = linkResults.processedLinks;
          enrichedFields.addAll(['links', 'processedLinks']);
          hasChanges = true;
        }
        errors.addAll(linkResults.errors);
      }

      // 4. Ensure processed links exist if requested
      if (spec.ensureProcessedLinks &&
          newProcessedLinks == null &&
          newLinks != null) {
        try {
          newProcessedLinks = await _generateProcessedLinks(newLinks);
          enrichedFields.add('processedLinks');
          hasChanges = true;
        } catch (e) {
          errors.add('Failed to generate processed links: $e');
        }
      }

      // 5. Generate description from links if requested
      if (spec.generateDescription && (newNotes == null || newNotes.isEmpty)) {
        final description = await _generateDescriptionFromLinks(
            newProcessedLinks ?? task.processedLinks);
        if (description != null) {
          newNotes = description;
          enrichedFields.add('notes');
          hasChanges = true;
        }
      }

      // 6. Process notes if requested
      if (spec.processNotes && newNotes != null) {
        final processedNotes = _processNotes(newNotes);
        if (processedNotes != newNotes) {
          newNotes = processedNotes;
          enrichedFields.add('notes');
          hasChanges = true;
        }
      }

      // Create enriched task
      final enrichedTask = Task(
        id: task.id,
        categoryId: task.categoryId,
        headline: newHeadline,
        notes: newNotes,
        ownerId: task.ownerId,
        createdAt: task.createdAt,
        suggestibleAt: task.suggestibleAt,
        triggersAt: task.triggersAt,
        deferral: task.deferral,
        links: newLinks,
        processedLinks: newProcessedLinks,
        finished: task.finished,
        shared: task.shared,
        originalId: task.originalId,
        dirty: hasChanges ? true : task.dirty, // Mark dirty if we made changes
      );

      return TaskEnrichmentResult(
        enrichedTask: enrichedTask,
        enrichedFields: enrichedFields,
        errors: errors,
        hasChanges: hasChanges,
      );
    } catch (e) {
      errors.add('Enrichment failed: $e');
      return TaskEnrichmentResult(
        enrichedTask: task,
        enrichedFields: [],
        errors: errors,
        hasChanges: false,
      );
    }
  }

  /// Process a single line of text input like the Add Tasks screen does
  /// Returns a TaskEnrichmentResult with the processed task
  static Future<TaskEnrichmentResult> processSingleLineInput({
    required String inputLine,
    required int categoryId,
    required String ownerId,
    TaskEnrichmentSpec spec = TaskEnrichmentSpec.webContent,
  }) async {
    final trimmedLine = inputLine.trim();

    if (trimmedLine.isEmpty) {
      throw Exception('Input line is empty');
    }

    // Remove @ prefix if present for URL validation
    String urlToCheck = trimmedLine;
    if (urlToCheck.startsWith('@')) {
      urlToCheck = urlToCheck.substring(1);
    }

    // Check if this is already an HTML link (including malformed ones)
    if (trimmedLine.startsWith('<a href="') && trimmedLine.contains('">')) {
      String htmlToProcess = trimmedLine;

      // Fix common malformed HTML patterns
      if (trimmedLine.endsWith('<a>')) {
        // Fix malformed closing tag: <a href="...">Title<a> -> <a href="...">Title</a>
        htmlToProcess = trimmedLine.replaceAll(RegExp(r'<a>$'), '</a>');
        print('TaskEnricher: Fixed malformed HTML link - changed <a> to </a>');
      } else if (!trimmedLine.endsWith('</a>')) {
        // If it doesn't end with </a> but starts like an HTML link, try to fix it
        if (trimmedLine.contains('<a>')) {
          htmlToProcess = trimmedLine.replaceAll('<a>', '</a>');
          print(
              'TaskEnricher: Fixed malformed HTML link - changed <a> to </a>');
        } else {
          // Add missing closing tag if it seems to be a complete link
          htmlToProcess = '$trimmedLine</a>';
          print('TaskEnricher: Added missing closing tag </a>');
        }
      }

      // Parse the fixed HTML link to extract URL and title
      final (url, title) = LinkProcessor.parseHtmlLink(htmlToProcess);

      try {
        // Always fetch webpage content to validate URL and get description
        final processedLink = await LinkProcessor.validateAndProcessLink(
          url,
          linkText: title, // Use the title from the HTML link
        );

        // Create task with webpage-fetched description but preserve the original title
        return await createAndEnrichTask(
          id: DateTime.now().millisecondsSinceEpoch,
          categoryId: categoryId,
          headline: title ??
              processedLink.title ??
              'Link Task', // Prefer HTML title, fall back to fetched title
          notes: processedLink.description, // Use description from webpage
          ownerId: ownerId,
          links: [htmlToProcess], // Use the corrected HTML link
          spec: const TaskEnrichmentSpec(
            enrichLinks: false, // Don't re-enrich since we already processed
            generateDescription:
                false, // Don't generate since we already have it
            ensureProcessedLinks:
                true, // Still create ProcessedLinks for display
            cleanHeadline: true, // Clean the headline as usual
          ),
        );
      } catch (e) {
        // If webpage fetch fails, create a fallback task with the HTML link data
        return await createAndEnrichTask(
          id: DateTime.now().millisecondsSinceEpoch,
          categoryId: categoryId,
          headline: title ?? 'Link Task',
          notes: 'Failed to validate URL: $url',
          ownerId: ownerId,
          links: [htmlToProcess], // Use the corrected HTML link
          spec: const TaskEnrichmentSpec(
            enrichLinks: false,
            generateDescription: false,
            ensureProcessedLinks: true,
            cleanHeadline: true,
          ),
        );
      }
    }

    // Check if this is a single URL
    if (LinkProcessor.isValidUrl(urlToCheck)) {
      try {
        // Process the URL through LinkProcessor
        final processedLink = await LinkProcessor.validateAndProcessLink(
          urlToCheck,
          linkText: '', // Let LinkProcessor fetch the title
        );

        // Create task and enrich it - use the ProcessedLink's description directly
        // Use a spec that preserves the existing notes and doesn't regenerate ProcessedLinks
        return await createAndEnrichTask(
          id: DateTime.now().millisecondsSinceEpoch,
          categoryId: categoryId,
          headline: processedLink.title ?? 'Link Task',
          notes: processedLink
              .description, // Use the description from ProcessedLink
          ownerId: ownerId,
          links: [processedLink.originalLink],
          spec: const TaskEnrichmentSpec(
            enrichLinks:
                false, // Don't re-enrich the links since we already processed them
            generateDescription:
                false, // Don't generate description since we already have it
            ensureProcessedLinks:
                true, // Still create ProcessedLinks for display
            cleanHeadline: true, // Still clean the headline
          ),
        );
      } catch (e) {
        // If URL processing fails, create a fallback task
        String fallbackTitle = _createFallbackTitleFromUrl(urlToCheck);

        return await createAndEnrichTask(
          id: DateTime.now().millisecondsSinceEpoch,
          categoryId: categoryId,
          headline: fallbackTitle,
          notes: 'Failed to fetch webpage title',
          ownerId: ownerId,
          links: ['<a href="$urlToCheck">$fallbackTitle</a>'],
          spec: spec,
        );
      }
    } else {
      // Process as regular text line (headline with optional notes)
      String headline = trimmedLine;
      String? notes;

      // Check for "Task: Note" format
      if (trimmedLine.contains(': ')) {
        final parts = trimmedLine.split(': ');
        if (parts.length >= 2) {
          headline = parts[0].trim();
          notes = parts.sublist(1).join(': ').trim();
        }
      }

      return await createAndEnrichTask(
        id: DateTime.now().millisecondsSinceEpoch,
        categoryId: categoryId,
        headline: headline,
        notes: notes,
        ownerId: ownerId,
        spec: spec,
      );
    }
  }

  /// Parse and process bulk input (CSV, JSON, or plain text) into multiple tasks
  /// Returns a list of TaskEnrichmentResult for each created task
  static Future<List<TaskEnrichmentResult>> processBulkInput({
    required String inputText,
    required int categoryId,
    required String ownerId,
    String? originSiteHint, // e.g., "justwatch.com", "letterboxd.com"
    TaskEnrichmentSpec spec = TaskEnrichmentSpec.webContent,
  }) async {
    final results = <TaskEnrichmentResult>[];

    if (inputText.trim().isEmpty) {
      return results;
    }

    // Detect input format
    final format = _BulkInputParsing._detectInputFormat(inputText);

    try {
      switch (format) {
        case _InputFormat.json:
          final jsonTasks = await _BulkInputParsing._parseJsonInput(
              inputText, originSiteHint);
          for (final taskData in jsonTasks) {
            final result = await createAndEnrichTask(
              id: DateTime.now().millisecondsSinceEpoch + results.length,
              categoryId: categoryId,
              headline: taskData.headline,
              notes: taskData.notes,
              ownerId: ownerId,
              links: taskData.links,
              spec: spec,
            );
            results.add(result);
          }
          break;

        case _InputFormat.csv:
          final csvTasks =
              await _BulkInputParsing._parseCsvInput(inputText, originSiteHint);
          for (final taskData in csvTasks) {
            final result = await createAndEnrichTask(
              id: DateTime.now().millisecondsSinceEpoch + results.length,
              categoryId: categoryId,
              headline: taskData.headline,
              notes: taskData.notes,
              ownerId: ownerId,
              links: taskData.links,
              spec: spec,
            );
            results.add(result);
          }
          break;

        case _InputFormat.plainText:
          final lines = inputText
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList();

          for (int i = 0; i < lines.length; i++) {
            final result = await processSingleLineInput(
              inputLine: lines[i],
              categoryId: categoryId,
              ownerId: ownerId,
              spec: spec,
            );
            results.add(result);
          }
          break;
      }
    } catch (e) {
      // If parsing fails, fall back to plain text processing
      final lines = inputText
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      for (int i = 0; i < lines.length; i++) {
        try {
          final result = await processSingleLineInput(
            inputLine: lines[i],
            categoryId: categoryId,
            ownerId: ownerId,
            spec: spec,
          );
          results.add(result);
        } catch (lineError) {
          // Skip problematic lines but continue processing
          continue;
        }
      }
    }

    return results;
  }

  /// Create a new Task from parameters and enrich it
  static Future<TaskEnrichmentResult> createAndEnrichTask({
    required int id,
    required int categoryId,
    required String headline,
    String? notes,
    required String ownerId,
    DateTime? createdAt,
    DateTime? suggestibleAt,
    DateTime? triggersAt,
    int? deferral,
    List<String>? links,
    bool finished = false,
    bool shared = false,
    int? originalId,
    TaskEnrichmentSpec spec = TaskEnrichmentSpec.minimal,
  }) async {
    // Create basic task
    final task = Task(
      id: id,
      categoryId: categoryId,
      headline: headline,
      notes: notes,
      ownerId: ownerId,
      createdAt: createdAt ?? DateTime.now(),
      suggestibleAt: suggestibleAt,
      triggersAt: triggersAt,
      deferral: deferral,
      links: links,
      processedLinks: null, // Will be generated if needed
      finished: finished,
      shared: shared,
      originalId: originalId,
      dirty: true, // New tasks are always dirty
    );

    // Enrich the task
    return await enrichTask(task, spec);
  }

  // Private helper methods

  static Future<String> _cleanHeadline(String headline) async {
    // Remove extra whitespace, normalize line breaks, etc.
    return headline.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static Future<_LinkEnrichmentResult> _enrichLinks(List<String> links) async {
    final enrichedLinks = <String>[];
    final processedLinks = <ProcessedLink>[];
    final errors = <String>[];
    bool hasChanges = false;

    for (final link in links) {
      try {
        // Extract URL from HTML link if needed
        final (url, title) = LinkProcessor.parseHtmlLink(link);

        // Always validate and process the link to fetch description and confirm URL validity
        // For HTML links, pass the existing title to preserve it
        final processedLink = await LinkProcessor.validateAndProcessLink(
          url,
          linkText: title, // Preserve HTML link title if available
        );

        // Create enriched HTML link
        final enrichedLink = processedLink.originalLink;

        enrichedLinks.add(enrichedLink);
        processedLinks.add(processedLink);

        // Check if we made changes
        if (enrichedLink != link) {
          hasChanges = true;
        }
      } catch (e) {
        errors.add('Failed to enrich link "$link": $e');
        enrichedLinks.add(link); // Keep original on error
      }
    }

    return _LinkEnrichmentResult(
      enrichedLinks: enrichedLinks,
      processedLinks: processedLinks,
      errors: errors,
      hasChanges: hasChanges,
    );
  }

  static Future<List<ProcessedLink>> _generateProcessedLinks(
      List<String> links) async {
    final processedLinks = <ProcessedLink>[];

    for (final link in links) {
      try {
        final processedLink = await LinkProcessor.processLinkForDisplay(link);
        processedLinks.add(processedLink);
      } catch (e) {
        // Create a minimal processed link for failed cases
        final (url, title) = LinkProcessor.parseHtmlLink(link);
        processedLinks.add(ProcessedLink(
          url: url,
          title: title,
          type: LinkType.other,
          domain: LinkProcessor.extractDomain(url),
          originalLink: link,
          description: null,
        ));
      }
    }

    return processedLinks;
  }

  static Future<String?> _generateDescriptionFromLinks(
      List<ProcessedLink>? processedLinks) async {
    if (processedLinks == null || processedLinks.isEmpty) return null;

    // Look for links with descriptions (JustWatch, Letterboxd, etc.)
    for (final link in processedLinks) {
      if (link.description != null && link.description!.isNotEmpty) {
        // Format description with link
        final description = link.description!;
        if (description.length > 200) {
          return '${description.substring(0, 200)}... <a href="${link.url}">(more)</a>';
        } else {
          return description;
        }
      }
    }

    return null;
  }

  static String _processNotes(String notes) {
    // Clean up notes: normalize whitespace, handle HTML, etc.
    return notes.trim();
  }

  static Future<_HeadlineExtractionResult?>
      _extractHeadlineFromLinksWithDetails(List<String> links) async {
    if (links.isEmpty) return null;

    // Process the first link to extract a title
    final firstLink = links.first;

    // Check if it's an HTML link first
    if (firstLink.startsWith('<a href="') &&
        firstLink.contains('">') &&
        firstLink.endsWith('</a>')) {
      final (url, title) = LinkProcessor.parseHtmlLink(firstLink);
      if (title != null && title.isNotEmpty) {
        return _HeadlineExtractionResult(headline: title, fromHtmlLink: true);
      }
    }

    // Check if it's a plain URL
    if (LinkProcessor.isValidUrl(firstLink)) {
      try {
        final processedLink =
            await LinkProcessor.validateAndProcessLink(firstLink);
        if (processedLink.title != null && processedLink.title!.isNotEmpty) {
          return _HeadlineExtractionResult(
              headline: processedLink.title!, fromHtmlLink: false);
        }
      } catch (e) {
        // If processing fails, try to create a fallback title from URL
        final fallbackTitle = _createFallbackTitleFromUrl(firstLink);
        return _HeadlineExtractionResult(
            headline: fallbackTitle, fromHtmlLink: false);
      }
    }

    return null;
  }

  static Future<_UrlExtractionResult?> _extractUrlFromHeadline(
      String headline) async {
    // Check if headline looks like a URL
    final urlPattern = RegExp(r'^https?://[^\s]+$');
    if (!urlPattern.hasMatch(headline.trim())) {
      return null;
    }

    final url = headline.trim();
    try {
      // Try to fetch the title from the webpage
      final processedLink = await LinkProcessor.validateAndProcessLink(url);
      if (processedLink.title != null && processedLink.title!.isNotEmpty) {
        return _UrlExtractionResult(
          title: processedLink.title!,
          htmlLink: '<a href="$url">${processedLink.title}</a>',
        );
      }
    } catch (e) {
      // Fall back to extracting from URL structure
      final fallbackTitle = _createFallbackTitleFromUrl(url);
      return _UrlExtractionResult(
        title: fallbackTitle,
        htmlLink: '<a href="$url">$fallbackTitle</a>',
      );
    }

    return null;
  }

  static String _createFallbackTitleFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;

      // For JustWatch URLs like /us/movie/wonder-boys
      if (path.contains('/movie/') || path.contains('/tv/')) {
        final segments = path.split('/');
        final titleSegment = segments.last;
        // Convert kebab-case to Title Case
        return titleSegment
            .split('-')
            .map((word) =>
                word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1))
            .join(' ');
      }

      // Generic fallback
      return uri.host.replaceAll('www.', '');
    } catch (e) {
      return 'Link';
    }
  }
}

/// Internal result class for link enrichment
class _LinkEnrichmentResult {
  final List<String> enrichedLinks;
  final List<ProcessedLink> processedLinks;
  final List<String> errors;
  final bool hasChanges;

  const _LinkEnrichmentResult({
    required this.enrichedLinks,
    required this.processedLinks,
    required this.errors,
    required this.hasChanges,
  });
}

/// Internal result class for URL extraction from headlines
class _UrlExtractionResult {
  final String title;
  final String htmlLink;

  const _UrlExtractionResult({
    required this.title,
    required this.htmlLink,
  });
}

/// Internal result class for headline extraction from links
class _HeadlineExtractionResult {
  final String headline;
  final bool fromHtmlLink;

  const _HeadlineExtractionResult({
    required this.headline,
    required this.fromHtmlLink,
  });
}

/// Input format detection enum
enum _InputFormat {
  json,
  csv,
  plainText,
}

/// Internal class for parsed task data
class _ParsedTaskData {
  final String headline;
  final String? notes;
  final List<String>? links;

  const _ParsedTaskData({
    required this.headline,
    this.notes,
    this.links,
  });
}

/// Helper methods for bulk input parsing
extension _BulkInputParsing on TaskEnricher {
  static _InputFormat _detectInputFormat(String input) {
    final trimmed = input.trim();

    // Check for JSON (array or object)
    if ((trimmed.startsWith('[') && trimmed.endsWith(']')) ||
        (trimmed.startsWith('{') && trimmed.endsWith('}'))) {
      try {
        // Basic JSON validation
        if (trimmed.startsWith('[')) {
          // Should contain objects or be a simple array
          return _InputFormat.json;
        } else {
          // Single object, treat as JSON
          return _InputFormat.json;
        }
      } catch (e) {
        // Fall back to CSV/plain text detection
      }
    }

    // Check for CSV (look for common CSV patterns)
    final lines = trimmed.split('\n');
    if (lines.length > 1) {
      final firstLine = lines[0];
      final secondLine = lines[1];

      // Look for comma-separated values with potential headers
      if (firstLine.contains(',') && secondLine.contains(',')) {
        final firstLineParts = firstLine.split(',').length;
        final secondLineParts = secondLine.split(',').length;

        // If both lines have the same number of comma-separated parts, likely CSV
        if (firstLineParts == secondLineParts && firstLineParts > 1) {
          return _InputFormat.csv;
        }
      }
    }

    // Default to plain text
    return _InputFormat.plainText;
  }

  static Future<List<_ParsedTaskData>> _parseJsonInput(
      String input, String? originSiteHint) async {
    final tasks = <_ParsedTaskData>[];

    try {
      final dynamic jsonData = jsonDecode(input);

      if (jsonData is List) {
        // Array of objects
        for (final item in jsonData) {
          if (item is Map<String, dynamic>) {
            final taskData = _parseJsonObject(item, originSiteHint);
            if (taskData != null) {
              tasks.add(taskData);
            }
          }
        }
      } else if (jsonData is Map<String, dynamic>) {
        // Single object
        final taskData = _parseJsonObject(jsonData, originSiteHint);
        if (taskData != null) {
          tasks.add(taskData);
        }
      }
    } catch (e) {
      // JSON parsing failed, return empty list
    }

    return tasks;
  }

  static _ParsedTaskData? _parseJsonObject(
      Map<String, dynamic> obj, String? originSiteHint) {
    String? headline;
    String? notes;
    List<String>? links;

    // Map common field names to task properties
    // Try multiple possible field names for each property
    final titleFields = ['title', 'headline', 'name', 'task', 'item'];
    final notesFields = [
      'notes',
      'description',
      'summary',
      'synopsis',
      'details'
    ];
    final linkFields = ['url', 'link', 'href', 'uri', 'website'];

    // Find headline
    for (final field in titleFields) {
      if (obj.containsKey(field) && obj[field] != null) {
        headline = obj[field].toString();
        break;
      }
    }

    // Find notes
    for (final field in notesFields) {
      if (obj.containsKey(field) && obj[field] != null) {
        notes = obj[field].toString();
        break;
      }
    }

    // Find links
    for (final field in linkFields) {
      if (obj.containsKey(field) && obj[field] != null) {
        final linkValue = obj[field];
        if (linkValue is String) {
          links = [linkValue];
        } else if (linkValue is List) {
          links = linkValue.map((e) => e.toString()).toList();
        }
        break;
      }
    }

    // Site-specific mappings
    if (originSiteHint != null) {
      if (originSiteHint.contains('justwatch')) {
        // Handle both flat structure and nested structure
        headline ??= obj['movie_title'] ?? obj['show_title'];
        notes ??= obj['synopsis'] ?? obj['plot'];
        links ??= obj['justwatch_url'] != null
            ? [obj['justwatch_url'].toString()]
            : null;

        // Handle nested JustWatch API structure
        if (obj.containsKey('node') && obj['node'] is Map<String, dynamic>) {
          final node = obj['node'] as Map<String, dynamic>;
          if (node.containsKey('content') &&
              node['content'] is Map<String, dynamic>) {
            final content = node['content'] as Map<String, dynamic>;
            headline ??= content['title']?.toString();
            notes ??= content['shortDescription']?.toString();

            final fullPath = content['fullPath']?.toString();
            if (fullPath != null) {
              links ??= ['https://justwatch.com$fullPath'];
            }
          }
        }
      } else if (originSiteHint.contains('letterboxd')) {
        headline ??= obj['film_title'] ?? obj['movie'];
        notes ??= obj['review'] ?? obj['rating'];
        links ??= obj['letterboxd_url'] != null
            ? [obj['letterboxd_url'].toString()]
            : null;
      }
    }

    if (headline != null && headline.isNotEmpty) {
      return _ParsedTaskData(
        headline: headline,
        notes: notes,
        links: links,
      );
    }

    return null;
  }

  static Future<List<_ParsedTaskData>> _parseCsvInput(
      String input, String? originSiteHint) async {
    final tasks = <_ParsedTaskData>[];
    final lines = input.trim().split('\n');

    if (lines.isEmpty) return tasks;

    // Parse header row
    final headers =
        lines[0].split(',').map((h) => h.trim().toLowerCase()).toList();

    // Find column indices for task properties
    int? titleIndex;
    int? notesIndex;
    int? linkIndex;

    for (int i = 0; i < headers.length; i++) {
      final header = headers[i];

      // Map headers to task properties
      if (titleIndex == null &&
          (header.contains('title') ||
              header.contains('headline') ||
              header.contains('name') ||
              header.contains('task') ||
              header.contains('item'))) {
        titleIndex = i;
      } else if (notesIndex == null &&
          (header.contains('notes') ||
              header.contains('description') ||
              header.contains('summary') ||
              header.contains('synopsis'))) {
        notesIndex = i;
      } else if (linkIndex == null &&
          (header.contains('url') ||
              header.contains('link') ||
              header.contains('href') ||
              header.contains('website'))) {
        linkIndex = i;
      }
    }

    // Site-specific header mappings
    if (originSiteHint != null) {
      if (originSiteHint.contains('justwatch')) {
        for (int i = 0; i < headers.length; i++) {
          final header = headers[i];
          if (titleIndex == null &&
              (header.contains('movie') || header.contains('show'))) {
            titleIndex = i;
          } else if (linkIndex == null && header.contains('justwatch')) {
            linkIndex = i;
          }
        }
      } else if (originSiteHint.contains('letterboxd')) {
        for (int i = 0; i < headers.length; i++) {
          final header = headers[i];
          if (titleIndex == null &&
              (header.contains('name') ||
                  header.contains('film') ||
                  header.contains('movie'))) {
            titleIndex = i;
          } else if (notesIndex == null && header.contains('review')) {
            notesIndex = i;
          } else if (linkIndex == null &&
              (header.contains('letterboxd') || header.contains('uri'))) {
            linkIndex = i;
          }
        }
      }
    }

    // Parse data rows
    for (int lineIndex = 1; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex].trim();
      if (line.isEmpty) continue;

      final columns = line.split(',').map((c) => c.trim()).toList();

      String? headline;
      String? notes;
      List<String>? links;

      if (titleIndex != null && titleIndex < columns.length) {
        headline = columns[titleIndex];
      }

      if (notesIndex != null && notesIndex < columns.length) {
        notes = columns[notesIndex];
      }

      if (linkIndex != null && linkIndex < columns.length) {
        final linkValue = columns[linkIndex];
        if (linkValue.isNotEmpty) {
          links = [linkValue];
        }
      }

      if (headline != null && headline.isNotEmpty) {
        tasks.add(_ParsedTaskData(
          headline: headline,
          notes: notes,
          links: links,
        ));
      }
    }

    return tasks;
  }
}
