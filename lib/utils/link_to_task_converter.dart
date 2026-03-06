import 'package:meaning_to/models/category.dart';
import 'package:link_enrichment_core/models/enrichment_context.dart';
import 'package:link_enrichment_core/service/enrichment_service.dart';
import 'package:link_enrichment_core/utils/url_canonicalizer.dart';
import 'package:meaning_to/utils/category_suggestion_registry.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/utils/streaming_media_constants.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/synopsis_fetcher.dart';

/// Represents a proposed task created from a link
class ProposedTask {
  final String headline;
  final String? notes;
  final List<String> links;
  final String? synopsis;
  final List<int> suggestedCategoryOriginalIds;
  final int? existingTaskOriginalId; // If this link matches an existing task

  ProposedTask({
    required this.headline,
    this.notes,
    required this.links,
    this.synopsis,
    required this.suggestedCategoryOriginalIds,
    this.existingTaskOriginalId,
  });

  @override
  String toString() {
    return 'ProposedTask(headline: "$headline", notes: "$notes", '
        'links: ${links.length}, synopsis: ${synopsis != null ? "present" : "null"}, '
        'suggestedCategories: $suggestedCategoryOriginalIds, '
        'existingTaskOriginalId: $existingTaskOriginalId)';
  }
}

/// Converts a link into a proposed Task with all relevant metadata
class LinkToTaskConverter {
  static final EnrichmentService _enrichmentService = EnrichmentService();

  /// Creates a proposed task from a link URL
  ///
  /// Parameters:
  /// - [url]: The URL to process
  /// - [userId]: Current user ID for finding existing tasks
  /// - [currentCategory]: Optional current category for context-aware processing
  ///
  /// Returns a [ProposedTask] with:
  /// - headline: Extracted title or artist name
  /// - notes: Work title for streaming media, or description
  /// - links: Single-entry list with HTML link
  /// - synopsis: Description from webpage or existing task
  /// - suggestedCategoryOriginalIds: List of category original_ids based on link domain
  /// - existingTaskOriginalId: ID of original task if this link exists elsewhere
  static Future<ProposedTask> createProposedTaskFromLink(
    String url,
    String userId, {
    Category? currentCategory,
  }) async {
    print('LinkToTaskConverter: Processing URL: $url');

    // Normalize URL via the enrichment core facade.
    final normalizedUrl = (await _enrichmentService.bootstrapFromUrl(url,
            context: EnrichmentContext.native))
        .normalizedUrl;
    print('LinkToTaskConverter: Normalized URL: $normalizedUrl');

    // Fetch webpage metadata
    final webpageContent =
        await LinkProcessor.validateAndProcessLink(normalizedUrl);
    final pageTitle = webpageContent.title ?? 'Untitled';
    final pageDescription = webpageContent.description;

    print('LinkToTaskConverter: Page title: "$pageTitle"');
    print(
        'LinkToTaskConverter: Page description: ${pageDescription?.substring(0, pageDescription.length > 100 ? 100 : pageDescription.length)}...');

    // Analyze URL to suggest categories
    var suggestedCategoryIds = analyzeLinkForCategorySuggestions(normalizedUrl);
    print('LinkToTaskConverter: Suggested category IDs: $suggestedCategoryIds');

    // Check if this is a streaming media link
    final isStreamingUrl = isStreamingMediaUrl(normalizedUrl);
    final isInStreamingCategory = currentCategory?.originalId != null &&
        STREAMING_MEDIA_CATEGORY_IDS.contains(currentCategory!.originalId);

    print('LinkToTaskConverter: Is streaming URL: $isStreamingUrl');
    print(
        'LinkToTaskConverter: Is in streaming category: $isInStreamingCategory');

    String headline;
    String? notes;
    String? synopsis;

    // Process based on link type
    if (isStreamingUrl &&
        (isInStreamingCategory ||
            suggestedCategoryIds
                .any((id) => STREAMING_MEDIA_CATEGORY_IDS.contains(id)))) {
      // Streaming media: extract artist and work
      // Try Spotify first, then TIDAL
      var artistWorkInfo = extractArtistAndWorkFromSpotify(pageTitle);
      if (artistWorkInfo == null) {
        artistWorkInfo = extractArtistAndWorkFromTidal(pageTitle);
      }

      if (artistWorkInfo != null) {
        // For streaming media: headline is the artist name
        // and notes is the work (album/track/playlist name)
        headline = artistWorkInfo.artist;
        notes = artistWorkInfo.work;
        synopsis = pageDescription;
        print(
            'LinkToTaskConverter: Extracted streaming media - Artist: "$headline", Work: "$notes"');
      } else {
        // Fallback if extraction fails
        headline = pageTitle;
        notes = null;
        synopsis = pageDescription;
        print(
            'LinkToTaskConverter: Could not extract artist/work, using page title');
      }
    } else if (normalizedUrl.contains('imdb.com')) {
      // IMDb: clean up title and use SynopsisFetcher for synopsis
      headline = LinkProcessor.cleanImdbTitle(pageTitle);
      notes = null;
      synopsis = await SynopsisFetcher.fetchSynopsisForUrl(normalizedUrl);

      print('🎯 LinkToTaskConverter: IMDb processing complete:');
      print('   - Headline: "$headline"');
      print(
          '   - Synopsis: ${synopsis != null ? "${synopsis.length} chars" : "null"}');
      print(
          '   - Synopsis preview: ${synopsis != null ? synopsis.substring(0, synopsis.length > 100 ? 100 : synopsis.length) : "N/A"}...');

      print('LinkToTaskConverter: IMDb link - cleaned headline: "$headline"');
    } else if (normalizedUrl.contains('letterboxd.com') ||
        normalizedUrl.contains('boxd.it')) {
      // Letterboxd: use SynopsisFetcher
      headline = pageTitle;
      notes = null;
      synopsis = await SynopsisFetcher.fetchSynopsisForUrl(normalizedUrl);
      print('LinkToTaskConverter: Letterboxd link - headline: "$headline"');
    } else {
      // General link: use page title as headline
      headline = pageTitle;
      notes = null;
      synopsis = pageDescription;
      print('LinkToTaskConverter: General link - headline: "$headline"');
    }

    // Create HTML link
    final htmlLink = '<a href="$normalizedUrl">$pageTitle</a>';

    // Check for existing task with this link (for original_id)
    final existingTaskOriginalId =
        await findExistingTaskOriginalId(normalizedUrl, userId);
    print(
        'LinkToTaskConverter: Existing task original_id: $existingTaskOriginalId');

    // If we found an existing task, try to use its synopsis if we don't have one
    if (existingTaskOriginalId != null && synopsis == null) {
      synopsis = await _getExistingTaskSynopsis(normalizedUrl, userId);
      print('LinkToTaskConverter: Retrieved synopsis from existing task');
    }

    print('📦 LinkToTaskConverter: Creating ProposedTask with:');
    print('   - Headline: "$headline"');
    print('   - Notes: ${notes != null ? "\"$notes\"" : "null"}');
    print('   - Links: ${[htmlLink].length} link(s)');
    print(
        '   - Synopsis: ${synopsis != null ? "${synopsis.length} chars" : "null"}');
    print('   - Suggested categories: $suggestedCategoryIds');
    print('   - Existing task original_id: $existingTaskOriginalId');

    return ProposedTask(
      headline: headline,
      notes: notes,
      links: [htmlLink],
      synopsis: synopsis,
      suggestedCategoryOriginalIds: suggestedCategoryIds,
      existingTaskOriginalId: existingTaskOriginalId,
    );
  }

  /// Normalize URL for comparison (remove tracking parameters, etc.)
  static String normalizeUrl(String url) {
    try {
      return UrlCanonicalizer.normalize(url);
    } catch (e) {
      print('LinkToTaskConverter: Error normalizing URL "$url": $e');
      return url;
    }
  }

  /// Analyze URL to suggest appropriate categories based on domain and path
  static List<int> analyzeLinkForCategorySuggestions(String url) {
    return CategorySuggestionRegistry.getSuggestionsForUrl(url);
  }

  /// Find the original_id of an existing task with this link
  /// This method is public so it can be used by other parts of the app
  static Future<int?> findExistingTaskOriginalId(
      String url, String userId) async {
    try {
      // Fetch ALL tasks in the database to find the original
      final response = await supabase
          .from('Tasks')
          .select()
          .order('created_at', ascending: true); // Oldest first

      final tasksData = response as List<dynamic>;

      for (final taskData in tasksData) {
        try {
          final task = Task.fromJson(taskData);

          // Check each link in the task
          for (final linkText in task.links ?? []) {
            final linkUrl = extractUrlFromHtmlLink(linkText);
            if (linkUrl != null && urlsMatch(url, linkUrl)) {
              // Found a task with this link
              // If it has an original_id, use that; otherwise use its own id
              final originalId = task.originalId ?? task.id;
              print(
                  'LinkToTaskConverter: Found original_id: $originalId (from task: "${task.headline}")');
              return originalId;
            }
          }
        } catch (e) {
          continue;
        }
      }

      return null;
    } catch (e) {
      print('LinkToTaskConverter: Error finding original_id: $e');
      return null;
    }
  }

  /// Get synopsis from an existing task with this link
  static Future<String?> _getExistingTaskSynopsis(
      String url, String userId) async {
    try {
      // Search user's tasks for this link
      final response =
          await supabase.from('Tasks').select().eq('owner_id', userId);

      final tasksData = response as List<dynamic>;

      for (final taskData in tasksData) {
        try {
          final task = Task.fromJson(taskData);

          // Check each link in the task
          for (final linkText in task.links ?? []) {
            final linkUrl = extractUrlFromHtmlLink(linkText);
            if (linkUrl != null && urlsMatch(url, linkUrl)) {
              // Found matching task, return its synopsis
              if (task.synopsis != null && task.synopsis!.isNotEmpty) {
                print(
                    'LinkToTaskConverter: Retrieved synopsis from task: "${task.headline}"');
                return task.synopsis;
              }
            }
          }
        } catch (e) {
          continue;
        }
      }

      return null;
    } catch (e) {
      print('LinkToTaskConverter: Error getting existing task synopsis: $e');
      return null;
    }
  }

  /// Extract URL from HTML link string
  static String? extractUrlFromHtmlLink(String htmlLink) {
    final extracted = UrlCanonicalizer.extractUrl(htmlLink);
    return extracted.isEmpty ? null : extracted;
  }

  /// Compare two URLs for matching (handles normalization)
  static bool urlsMatch(String url1, String url2) {
    final normalized1 = normalizeUrl(url1);
    final normalized2 = normalizeUrl(url2);
    return normalized1 == normalized2;
  }
}
