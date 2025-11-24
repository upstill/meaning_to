import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Utility class for fetching and managing task synopses
/// Handles database lookups and web scraping for JustWatch, Letterboxd, TED, etc.
class SynopsisFetcher {
  static final _supabase = Supabase.instance.client;

  /// Fetch synopsis for a URL without requiring a Task object
  /// First checks database for existing synopsis, then falls back to web scraping
  /// Does NOT save to database (caller is responsible for that)
  /// Returns just the synopsis string
  static Future<String?> fetchSynopsisForUrl(String url) async {
    print('SynopsisFetcher: Fetching synopsis for URL: $url');

    // First, try to find synopsis from another task in database (fast!)
    print('SynopsisFetcher: Checking database for URL: $url');
    String? synopsis = await _findSynopsisFromDatabaseByUrl(url);

    // If not found in database, fetch from web (slow)
    if (synopsis == null || synopsis.isEmpty) {
      print('SynopsisFetcher: No synopsis in database, fetching from web');

      if (url.contains('imdb.com')) {
        synopsis = await _fetchImdbSynopsis(url);
      } else if (url.contains('justwatch.com')) {
        synopsis = await _fetchJustWatchSynopsis(url);
      } else if (url.contains('letterboxd.com') || url.contains('boxd.it')) {
        synopsis = await _fetchLetterboxdSynopsis(url);
      } else if (url.contains('ted.com')) {
        synopsis = await _fetchGenericSynopsis(url);
      }

      // Check if this is an error message
      if (synopsis != null && synopsis.isNotEmpty) {
        final isErrorMessage =
            synopsis.startsWith('Synopsis not available') ||
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

        if (url.contains('imdb.com')) {
          synopsis = await _fetchImdbSynopsis(url);
        } else if (url.contains('justwatch.com')) {
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
        if (hasMatchingLink && task.synopsis != null && task.synopsis!.isNotEmpty) {
          tasksWithLinkAndSynopsis++;
          print(
              'SynopsisFetcher: Found task #${task.id} "${task.headline}" with matching link and synopsis (owner: ${task.ownerId})');
          print('SynopsisFetcher: Synopsis: ${task.synopsis!.substring(0, task.synopsis!.length > 100 ? 100 : task.synopsis!.length)}...');
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
        if (hasMatchingLink && task.synopsis != null && task.synopsis!.isNotEmpty) {
          tasksWithLinkAndSynopsis++;
          print(
              'SynopsisFetcher: Found task #${task.id} "${task.headline}" with matching link and synopsis (owner: ${task.ownerId})');
          print('SynopsisFetcher: Synopsis: ${task.synopsis!.substring(0, task.synopsis!.length > 100 ? 100 : task.synopsis!.length)}...');
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

  /// Fetch synopsis from IMDb using OMDb API or HTML scraping
  static Future<String?> _fetchImdbSynopsis(String url) async {
    try {
      print('SynopsisFetcher: Fetching from IMDb: $url');

      // Extract IMDb ID from URL
      final imdbId = _extractImdbId(url);
      if (imdbId == null) {
        print('SynopsisFetcher: Could not extract IMDb ID from URL: $url');
        return null;
      }

      print('SynopsisFetcher: Extracted IMDb ID: $imdbId');

      // Try OMDb API first
      print('🔍 SynopsisFetcher: Attempting to fetch IMDb data from OMDb API...');
      final omdbData = await _fetchFromOmdbApi(imdbId);
      if (omdbData != null) {
        print('✅ SynopsisFetcher: OMDb data received, building synopsis...');
        final synopsis = _buildSynopsisFromOmdbData(omdbData);
        print('📦 SynopsisFetcher: Returning OMDb synopsis - length: ${synopsis.length} chars');
        return synopsis;
      }

      // Fallback to HTML scraping if API fails
      print('⚠️  SynopsisFetcher: OMDb API returned null, falling back to HTML scraping');
      final synopsis = await _fetchImdbSynopsisFromHtml(url);
      print('📦 SynopsisFetcher: Returning HTML-scraped synopsis: ${synopsis != null ? "${synopsis.length} chars" : "null"}');
      return synopsis;
    } catch (e) {
      print('SynopsisFetcher: Error fetching IMDb synopsis: $e');
      return null;
    }
  }

  /// Extract IMDb ID from URL (e.g., tt0111161 from https://www.imdb.com/title/tt0111161/)
  static String? _extractImdbId(String url) {
    final match = RegExp(r'/title/(tt\d+)').firstMatch(url);
    return match?.group(1);
  }

  /// Fetch data from OMDb API
  static Future<Map<String, dynamic>?> _fetchFromOmdbApi(String imdbId) async {
    try {
      // Get OMDb API key with fallback to .env for local development
      String? apiKey;

      // Priority 1: Build-time environment variable (Production)
      const apiKeyFromBuild = String.fromEnvironment('OMDB_API_KEY');
      if (apiKeyFromBuild.isNotEmpty) {
        apiKey = apiKeyFromBuild;
      } else {
        // Priority 2: Local .env fallback (Development)
        try {
          print('🔍 SynopsisFetcher: Attempting to read OMDB_API_KEY from dotenv...');
          final apiKeyFromDotenv = dotenv.env['OMDB_API_KEY'];
          print('🔍 SynopsisFetcher: dotenv.env[\'OMDB_API_KEY\'] = ${apiKeyFromDotenv != null ? "***found***" : "null"}');
          if (apiKeyFromDotenv != null && apiKeyFromDotenv.isNotEmpty) {
            apiKey = apiKeyFromDotenv;
            print('✅ SynopsisFetcher: Successfully loaded OMDb API key from dotenv');
          } else {
            print('⚠️  SynopsisFetcher: dotenv.env[\'OMDB_API_KEY\'] is null or empty');
          }
        } catch (e) {
          print('❌ SynopsisFetcher: Error accessing dotenv: $e');
          // Graceful fallback if dotenv not loaded
        }
      }

      // Skip API call if no key is configured
      if (apiKey == null || apiKey.isEmpty) {
        print('❌ SynopsisFetcher: OMDb API key not configured, skipping API call');
        return null;
      }

      print('✅ SynopsisFetcher: OMDb API key found, making API call...');
      final omdbUrl =
          'http://www.omdbapi.com/?i=$imdbId&plot=full&apikey=$apiKey';
      print('🌐 SynopsisFetcher: Calling OMDb API for $imdbId');

      final response = await http
          .get(Uri.parse(omdbUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        if (data['Response'] == 'True') {
          print('✅ SynopsisFetcher: OMDb API SUCCESS!');
          print('   📝 Title: ${data['Title']}');
          print('   🎬 Type: ${data['Type']}');
          final plot = data['Plot']?.toString();
          final plotPreview = plot != null
              ? (plot.length > 100 ? plot.substring(0, 100) : plot)
              : "N/A";
          print('   📖 Plot: $plotPreview...');
          print('   ⭐ Rating: ${data['Rated']} | IMDb: ${data['imdbRating']}/10');
          print('   ⏱️  Runtime: ${data['Runtime']}');
          print('   📅 Released: ${data['Released']}');
          return data;
        } else {
          print('❌ SynopsisFetcher: OMDb API error response: ${data['Error']}');
          return null;
        }
      }

      print('❌ SynopsisFetcher: OMDb API returned HTTP status ${response.statusCode}');
      return null;
    } catch (e) {
      print('SynopsisFetcher: Error calling OMDb API: $e');
      return null;
    }
  }

  /// Build synopsis from OMDb API data
  static String _buildSynopsisFromOmdbData(Map<String, dynamic> data) {
    final parts = <String>[];

    // Add plot
    if (data['Plot'] != null && data['Plot'] != 'N/A') {
      parts.add(data['Plot']);
    }

    // Add rating
    if (data['Rated'] != null && data['Rated'] != 'N/A') {
      parts.add('Rated ${data['Rated']}');
    }

    // Add runtime
    if (data['Runtime'] != null && data['Runtime'] != 'N/A') {
      parts.add(data['Runtime']);
    }

    // Add release date
    if (data['Released'] != null && data['Released'] != 'N/A') {
      parts.add('Released ${data['Released']}');
    }

    // Add IMDb rating if available
    if (data['imdbRating'] != null && data['imdbRating'] != 'N/A') {
      parts.add('IMDb: ${data['imdbRating']}/10');
    }

    final synopsis = parts.join('. ');
    print('📝 SynopsisFetcher: Built synopsis from OMDb data:');
    print('   - Total length: ${synopsis.length} characters');
    print('   - Preview: "${synopsis.substring(0, synopsis.length > 150 ? 150 : synopsis.length)}${synopsis.length > 150 ? "..." : ""}"');
    return synopsis;
  }

  /// Fallback: Fetch synopsis from HTML scraping
  static Future<String?> _fetchImdbSynopsisFromHtml(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final html = response.body;

        // Extract plot synopsis
        String? plotText = _extractImdbPlot(html);

        // Extract metadata (rating, runtime, release date)
        final metadata = _extractImdbMetadata(html);

        // Combine plot with metadata
        if (plotText != null && plotText.isNotEmpty) {
          final parts = <String>[plotText];

          if (metadata['rating'] != null) {
            parts.add('Rated ${metadata['rating']}');
          }
          if (metadata['runtime'] != null) {
            parts.add(metadata['runtime']!);
          }
          if (metadata['releaseDate'] != null) {
            parts.add('Released ${metadata['releaseDate']}');
          }

          final fullSynopsis = parts.join('. ');
          print('SynopsisFetcher: Extracted IMDb synopsis from HTML: "${fullSynopsis.substring(0, fullSynopsis.length > 100 ? 100 : fullSynopsis.length)}..."');
          return fullSynopsis;
        }
      }

      return null;
    } catch (e) {
      print('SynopsisFetcher: Error scraping HTML: $e');
      return null;
    }
  }

  /// Extract plot text from IMDb HTML
  static String? _extractImdbPlot(String html) {
    // Try to extract the plot synopsis from IMDb's HTML
    final plotMatch = RegExp(
            r'<span[^>]*data-testid="plot[^"]*"[^>]*>(.*?)</span>',
            dotAll: true)
        .firstMatch(html);

    if (plotMatch != null) {
      final plotText = plotMatch.group(1)?.trim();
      if (plotText != null && plotText.isNotEmpty) {
        // Remove HTML tags and decode entities
        final cleanPlot = plotText
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .replaceAll('&quot;', '"')
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .trim();

        if (cleanPlot.isNotEmpty) {
          return cleanPlot;
        }
      }
    }
    return null;
  }

  /// Extract metadata (rating, runtime, release date) from IMDb HTML
  static Map<String, String?> _extractImdbMetadata(String html) {
    final result = <String, String?>{
      'rating': null,
      'runtime': null,
      'releaseDate': null,
    };

    try {
      // Find ul.ipc-metadata-list
      final metadataListMatch = RegExp(
        r'<ul[^>]*class="[^"]*ipc-metadata-list[^"]*"[^>]*>(.*?)</ul>',
        dotAll: true,
      ).firstMatch(html);

      if (metadataListMatch != null) {
        final metadataListHtml = metadataListMatch.group(1)!;

        // Find the <li> that contains a nested ul.ipc-inline-list
        final inlineListMatch = RegExp(
          r'<li[^>]*>.*?<ul[^>]*class="[^"]*ipc-inline-list[^"]*"[^>]*>(.*?)</ul>.*?</li>',
          dotAll: true,
        ).firstMatch(metadataListHtml);

        if (inlineListMatch != null) {
          final inlineListHtml = inlineListMatch.group(1)!;

          // Extract all <li> items from the inline list
          final liMatches = RegExp(r'<li[^>]*>(.*?)</li>', dotAll: true)
              .allMatches(inlineListHtml)
              .toList();

          if (liMatches.length >= 3) {
            // First item: Rating
            result['rating'] = _cleanHtmlText(liMatches[0].group(1) ?? '');

            // Second item: Runtime
            result['runtime'] = _cleanHtmlText(liMatches[1].group(1) ?? '');

            // Third item: Release date
            result['releaseDate'] = _cleanHtmlText(liMatches[2].group(1) ?? '');
          }
        }
      }
    } catch (e) {
      print('SynopsisFetcher: Error extracting IMDb metadata: $e');
    }

    return result;
  }

  /// Clean HTML text by removing tags and decoding entities
  static String _cleanHtmlText(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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
