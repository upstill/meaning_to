import 'package:link_enrichment_core/models/enrichment_context.dart';
import 'package:link_enrichment_core/service/enrichment_service.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Utility class for fetching and managing task synopses.
/// Uses DB reuse + enrichment-core extraction.
class SynopsisFetcher {
  static final _supabase = Supabase.instance.client;
  static final EnrichmentService _enrichmentService = EnrichmentService();

  /// Fetch synopsis for a URL without requiring a Task object.
  /// First checks database for existing synopsis, then falls back to web fetch.
  /// Does NOT save to database (caller is responsible for that).
  static Future<String?> fetchSynopsisForUrl(String url) async {
    print('SynopsisFetcher: Fetching synopsis for URL: $url');

    // First, try to find synopsis from another task in database (fast!)
    print('SynopsisFetcher: Checking database for URL: $url');
    String? synopsis = await _findSynopsisFromDatabaseByUrl(url);

    // If not found in database, fetch from web (slow)
    if (synopsis == null || synopsis.isEmpty) {
      print('SynopsisFetcher: No synopsis in database, fetching from web');

      // Primary path: enrichment core rule-driven extraction.
      synopsis = await _fetchSynopsisFromEnrichmentCore(url);

      // Check if this is an error message
      if (synopsis != null && synopsis.isNotEmpty) {
        final isErrorMessage = synopsis.startsWith('Synopsis not available') ||
            synopsis.startsWith('Description not available') ||
            synopsis.contains('content protection');

        if (isErrorMessage) {
          print('SynopsisFetcher: Got error message, returning null');
          return null;
        }
      }
    } else {
      print('SynopsisFetcher: Found synopsis in database from another task');
    }

    return synopsis;
  }

  /// Fetch synopsis for a task from links.
  /// First checks database for existing synopsis, then falls back to web fetch.
  /// Returns the synopsis and whether it was saved to database.
  static Future<SynopsisResult?> fetchSynopsisForTask(Task task) async {
    if (task.links == null || task.links!.isEmpty) {
      return null;
    }

    print(
        'SynopsisFetcher: Starting synopsis fetch for task: ${task.headline}');

    for (final link in task.links!) {
      final url = _extractUrlFromHtmlLink(link);
      if (url == null || url.isEmpty) {
        continue;
      }

      String? synopsis;

      // First, try to find synopsis from another task in database (fast!)
      print('SynopsisFetcher: Checking database for URL: $url');
      synopsis = await _findSynopsisFromDatabase(url, task.id);

      // If not found in database, fetch from web (slow)
      if (synopsis == null || synopsis.isEmpty) {
        print('SynopsisFetcher: No synopsis in database, fetching from web');
        synopsis = await fetchSynopsisForUrl(url);

        if (synopsis != null && synopsis.isNotEmpty) {
          // Check if this is an error message
          final isErrorMessage =
              synopsis.startsWith('Synopsis not available') ||
                  synopsis.startsWith('Description not available') ||
                  synopsis.contains('content protection');

          if (!isErrorMessage) {
            // Format and save to database
            // Always include a reference link to enable accurate pattern matching
            final formattedSynopsis = synopsis.length > 200
                ? '${synopsis.substring(0, 200)}... <a href="$url">(more)</a>'
                : '$synopsis <a href="$url">(reference)</a>';

            await _saveSynopsisToDatabase(task.id, formattedSynopsis);
            print('SynopsisFetcher: Saved synopsis to database');
            return SynopsisResult(
              synopsis: formattedSynopsis,
              source: SynopsisSource.web,
              savedToDatabase: true,
            );
          }
        }
      } else {
        print('SynopsisFetcher: Found synopsis in database from another task');
        // Save this synopsis to the current task so we don't have to look it up again
        await _saveSynopsisToDatabase(task.id, synopsis);
        print('SynopsisFetcher: Copied synopsis to current task');
        return SynopsisResult(
          synopsis: synopsis,
          source: SynopsisSource.database,
          savedToDatabase: true,
        );
      }
    }

    return null;
  }

  /// Fetch synopsis using enrichment-core rules/extractors.
  static Future<String?> _fetchSynopsisFromEnrichmentCore(String url) async {
    try {
      final result = await _enrichmentService.bootstrapFromUrl(
        url,
        context: EnrichmentContext.native,
      );

      if (result.synopsis != null && result.synopsis!.trim().isNotEmpty) {
        print('SynopsisFetcher: Found synopsis via enrichment core');
        return result.synopsis!.trim();
      }
    } catch (e) {
      print('SynopsisFetcher: Enrichment core synopsis fetch failed: $e');
    }
    return null;
  }

  /// Find synopsis from a task in the database with the same link (without excluding a task)
  /// Searches for tasks that have this URL in their links array and have a non-empty synopsis
  /// Searches ALL tasks (not just current user's) to maximize reuse
  static Future<String?> _findSynopsisFromDatabaseByUrl(String url) async {
    try {
      print('SynopsisFetcher: Searching database for tasks with URL: $url');

      // Search ALL tasks in the database (not filtered by user)
      final response = await _supabase.from('Tasks').select();
      final tasksData = response as List<dynamic>;

      print('SynopsisFetcher: Found ${tasksData.length} total tasks to check');

      int tasksWithLink = 0;
      int tasksWithLinkAndSynopsis = 0;

      for (final taskData in tasksData) {
        final task = Task.fromJson(taskData);

        // Check if this task has links
        if (task.links == null || task.links!.isEmpty) {
          continue;
        }

        // Check if any of the task's links contain this URL
        bool hasMatchingLink = false;
        for (final link in task.links!) {
          // Extract URL from HTML link if needed
          String? linkUrl;
          if (link.startsWith('http://') || link.startsWith('https://')) {
            linkUrl = link;
          } else {
            final regex = RegExp(r'href=["\\x27]([^"\\x27]+)["\\x27]');
            final match = regex.firstMatch(link);
            linkUrl = match?.group(1);
          }

          if (linkUrl == url) {
            hasMatchingLink = true;
            tasksWithLink++;
            break;
          }
        }

        // If this task has the matching link and a synopsis, return it
        if (hasMatchingLink &&
            task.synopsis != null &&
            task.synopsis!.isNotEmpty) {
          tasksWithLinkAndSynopsis++;
          print(
              'SynopsisFetcher: Found task #${task.id} "${task.headline}" with matching link and synopsis (owner: ${task.ownerId})');
          print(
              'SynopsisFetcher: Synopsis: ${task.synopsis!.substring(0, task.synopsis!.length > 100 ? 100 : task.synopsis!.length)}...');
          print('SynopsisFetcher: Using synopsis from task #${task.id}');
          return task.synopsis;
        }
      }

      print(
          'SynopsisFetcher: Search complete. Tasks with matching link: $tasksWithLink, Tasks with link and synopsis: $tasksWithLinkAndSynopsis');
      return null;
    } catch (e) {
      print('SynopsisFetcher: Error finding synopsis from database: $e');
      return null;
    }
  }

  /// Find synopsis from another task in the database with the same link
  /// Searches for tasks that have this URL in their links array and have a non-empty synopsis
  /// Searches ALL tasks (not just current user's) to maximize reuse
  static Future<String?> _findSynopsisFromDatabase(
      String url, int currentTaskId) async {
    try {
      print('SynopsisFetcher: Searching database for tasks with URL: $url');

      // Search ALL tasks in the database (not filtered by user)
      final response = await _supabase.from('Tasks').select();
      final tasksData = response as List<dynamic>;

      print('SynopsisFetcher: Found ${tasksData.length} total tasks to check');

      int tasksWithLink = 0;
      int tasksWithLinkAndSynopsis = 0;

      for (final taskData in tasksData) {
        final task = Task.fromJson(taskData);

        // Skip the current task
        if (task.id == currentTaskId) {
          continue;
        }

        // Check if this task has links
        if (task.links == null || task.links!.isEmpty) {
          continue;
        }

        // Check if any of the task's links contain this URL
        bool hasMatchingLink = false;
        for (final link in task.links!) {
          // Extract URL from HTML link if needed
          String? linkUrl;
          if (link.startsWith('http://') || link.startsWith('https://')) {
            linkUrl = link;
          } else {
            final regex = RegExp(r'href=["\x27]([^"\x27]+)["\x27]');
            final match = regex.firstMatch(link);
            linkUrl = match?.group(1);
          }

          if (linkUrl == url) {
            hasMatchingLink = true;
            tasksWithLink++;
            break;
          }
        }

        // If this task has the matching link and a synopsis, return it
        if (hasMatchingLink &&
            task.synopsis != null &&
            task.synopsis!.isNotEmpty) {
          tasksWithLinkAndSynopsis++;
          print(
              'SynopsisFetcher: Found task #${task.id} "${task.headline}" with matching link and synopsis (owner: ${task.ownerId})');
          print(
              'SynopsisFetcher: Synopsis: ${task.synopsis!.substring(0, task.synopsis!.length > 100 ? 100 : task.synopsis!.length)}...');
          print('SynopsisFetcher: Using synopsis from task #${task.id}');
          return task.synopsis;
        }
      }

      print(
          'SynopsisFetcher: Search complete. Tasks with matching link: $tasksWithLink, Tasks with link and synopsis: $tasksWithLinkAndSynopsis');
      return null;
    } catch (e) {
      print('SynopsisFetcher: Error finding synopsis from database: $e');
      return null;
    }
  }

  /// Save synopsis to database for a task
  static Future<void> _saveSynopsisToDatabase(
      int taskId, String synopsis) async {
    try {
      print('SynopsisFetcher: Saving synopsis for task ID $taskId');
      await ApiClient.updateTask(taskId.toString(), {'synopsis': synopsis});
      print('SynopsisFetcher: Successfully saved synopsis');
    } catch (e) {
      print('SynopsisFetcher: Error saving synopsis: $e');
      rethrow;
    }
  }

  /// Extract URL from HTML link or return plain URL
  static String? _extractUrlFromHtmlLink(String linkText) {
    // If it's already a plain URL, return it as-is
    if (linkText.startsWith('http://') || linkText.startsWith('https://')) {
      return linkText;
    }

    // Otherwise, try to extract from HTML format
    final regex = RegExp(r'href=["\x27]([^"\x27]+)["\x27]');
    final match = regex.firstMatch(linkText);
    return match?.group(1);
  }
}

/// Result of a synopsis fetch operation
class SynopsisResult {
  final String synopsis;
  final SynopsisSource source;
  final bool savedToDatabase;

  SynopsisResult({
    required this.synopsis,
    required this.source,
    required this.savedToDatabase,
  });
}

/// Source of a synopsis
enum SynopsisSource {
  database, // Found in database from another task
  web, // Fetched from web
}
