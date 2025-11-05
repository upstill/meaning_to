import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Utility class for fetching and managing task synopses
/// Handles database lookups and web scraping for JustWatch, Letterboxd, TED, etc.
class SynopsisFetcher {
  static final _supabase = Supabase.instance.client;

  /// Fetch synopsis for a task from links
  /// First checks database for existing synopsis, then falls back to web scraping
  /// Returns the synopsis and whether it was saved to database
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

        if (url.contains('justwatch.com')) {
          synopsis = await _fetchJustWatchSynopsis(url);
        } else if (url.contains('letterboxd.com') || url.contains('boxd.it')) {
          synopsis = await _fetchLetterboxdSynopsis(url);
        } else if (url.contains('ted.com')) {
          synopsis = await _fetchGenericSynopsis(url);
        }

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

  /// Generate reference link patterns for a given URL
  /// Returns a list of patterns that should appear at the END of synopses
  /// These patterns are checked using endsWith() to ensure we only match
  /// our appended reference links, not any links embedded in the synopsis text
  static List<String> _generateReferenceLinkPatterns(String url) {
    return [
      '... <a href="$url">(more)</a>', // For truncated synopses
      ' <a href="$url">(reference)</a>', // For short synopses
    ];
  }

  /// Find synopsis from another task in the database with the same link
  /// Searches based on the reference link embedded in the synopsis (either "(more)" or "(reference)")
  /// This ensures we match synopses derived from the same source link, preventing ambiguity
  /// when tasks have multiple links. Searches ALL tasks (not just current user's) to maximize reuse
  static Future<String?> _findSynopsisFromDatabase(
      String url, int currentTaskId) async {
    try {
      print('SynopsisFetcher: Searching database for tasks with URL: $url');

      // Search ALL tasks in the database (not filtered by user)
      final response = await _supabase.from('Tasks').select();
      final tasksData = response as List<dynamic>;

      print('SynopsisFetcher: Found ${tasksData.length} total tasks to check');

      // Generate both possible reference link patterns
      final referenceLinkPatterns = _generateReferenceLinkPatterns(url);
      print(
          'SynopsisFetcher: Looking for synopsis ending with either: ${referenceLinkPatterns.join(" OR ")}');

      int tasksWithSynopsis = 0;
      int tasksWithMatchingSynopsis = 0;

      for (final taskData in tasksData) {
        final task = Task.fromJson(taskData);

        // Skip the current task
        if (task.id == currentTaskId) {
          continue;
        }

        // Count tasks with synopsis for debugging
        if (task.synopsis != null && task.synopsis!.isNotEmpty) {
          tasksWithSynopsis++;

          // Check if this task's synopsis ENDS WITH either reference link pattern for this URL
          // Using endsWith() ensures we only match our appended reference link, not any
          // links that might be embedded in the synopsis text itself
          final hasMatchingPattern = referenceLinkPatterns.any(
            (pattern) => task.synopsis!.endsWith(pattern),
          );

          if (hasMatchingPattern) {
            tasksWithMatchingSynopsis++;
            print(
                'SynopsisFetcher: Found task #${task.id} "${task.headline}" with matching synopsis (owner: ${task.ownerId})');
            print(
                'SynopsisFetcher: Synopsis ends with the correct reference link for this URL');
            print('SynopsisFetcher: Using synopsis from task #${task.id}');
            return task.synopsis;
          }
        }
      }

      print(
          'SynopsisFetcher: Search complete. Tasks with synopsis: $tasksWithSynopsis, Tasks with matching synopsis: $tasksWithMatchingSynopsis');
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

  /// Fetch synopsis from JustWatch
  static Future<String?> _fetchJustWatchSynopsis(String url) async {
    try {
      print('SynopsisFetcher: Fetching from JustWatch: $url');

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);

        // PRIORITY 1: Try to find synopsis using the specific JustWatch selector
        final synopsisArticle =
            document.querySelector('div#synopsis article.article-block');
        if (synopsisArticle != null) {
          final synopsisText = synopsisArticle.text.trim();
          if (synopsisText.isNotEmpty) {
            print(
                'SynopsisFetcher: Found synopsis in div#synopsis article.article-block');
            return synopsisText;
          }
        }

        // PRIORITY 2: Try to find synopsis in structured data
        final scriptTags =
            document.querySelectorAll('script[type="application/ld+json"]');
        for (final script in scriptTags) {
          final jsonText = script.text;
          if (jsonText.contains('"description"')) {
            try {
              final regex = RegExp(r'"description"\s*:\s*"([^"]+)"');
              final match = regex.firstMatch(jsonText);
              if (match != null) {
                final description = match.group(1);
                if (description != null && description.isNotEmpty) {
                  print('SynopsisFetcher: Found synopsis in structured data');
                  return description;
                }
              }
            } catch (e) {
              print('SynopsisFetcher: Error parsing structured data: $e');
            }
          }
        }

        // PRIORITY 3: Fallback to meta description
        final metaDescription =
            document.querySelector('meta[name="description"]');
        if (metaDescription != null) {
          final content = metaDescription.attributes['content'];
          if (content != null && content.isNotEmpty) {
            print('SynopsisFetcher: Found synopsis in meta description');
            return content;
          }
        }

        print('SynopsisFetcher: Synopsis not found in page');
        return 'Synopsis not available';
      } else {
        print('SynopsisFetcher: HTTP error ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('SynopsisFetcher: Error fetching JustWatch synopsis: $e');
      return null;
    }
  }

  /// Fetch synopsis from Letterboxd
  static Future<String?> _fetchLetterboxdSynopsis(String url) async {
    try {
      print('SynopsisFetcher: Fetching from Letterboxd: $url');

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);

        // Try meta description
        final metaDescription =
            document.querySelector('meta[name="description"]');
        if (metaDescription != null) {
          final content = metaDescription.attributes['content'];
          if (content != null && content.isNotEmpty) {
            print('SynopsisFetcher: Found synopsis in meta description');
            return content;
          }
        }

        print('SynopsisFetcher: Synopsis not found in page');
        return 'Synopsis not available';
      } else {
        print('SynopsisFetcher: HTTP error ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('SynopsisFetcher: Error fetching Letterboxd synopsis: $e');
      return null;
    }
  }

  /// Fetch synopsis from generic URL (TED, etc.)
  static Future<String?> _fetchGenericSynopsis(String url) async {
    try {
      print('SynopsisFetcher: Fetching from generic URL: $url');

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);

        // Try meta description
        final metaDescription =
            document.querySelector('meta[name="description"]');
        if (metaDescription != null) {
          final content = metaDescription.attributes['content'];
          if (content != null && content.isNotEmpty) {
            print('SynopsisFetcher: Found description in meta description');
            return content;
          }
        }

        // Try Open Graph description
        final ogDescription =
            document.querySelector('meta[property="og:description"]');
        if (ogDescription != null) {
          final content = ogDescription.attributes['content'];
          if (content != null && content.isNotEmpty) {
            print('SynopsisFetcher: Found description in og:description');
            return content;
          }
        }

        print('SynopsisFetcher: Description not found in page');
        return 'Description not available';
      } else {
        print('SynopsisFetcher: HTTP error ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('SynopsisFetcher: Error fetching generic synopsis: $e');
      return null;
    }
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
