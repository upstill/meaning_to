import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/utils/streaming_media_constants.dart';
import 'package:meaning_to/utils/spotify_api.dart';
import 'package:meaning_to/utils/tidal_api.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/models/task.dart';

/// Normalizes whitespace in a string by replacing multiple consecutive whitespace
/// characters with a single space and trimming leading/trailing whitespace.
/// Returns null if input is null.
String? _normalizeWhitespace(String? text) {
  if (text == null) return null;
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

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

    // Normalize URL
    final normalizedUrl = normalizeUrl(url);
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

    String headline = _normalizeWhitespace(pageTitle) ?? pageTitle; // Default to page title, normalized
    String? notes;
    String? synopsis;

    // Process based on link type
    if (isStreamingUrl &&
        (isInStreamingCategory ||
            suggestedCategoryIds
                .any((id) => STREAMING_MEDIA_CATEGORY_IDS.contains(id)))) {
      // Streaming media: extract artist and work
      ArtistWorkInfo? artistWorkInfo;
      String? customLinkText; // For custom link text (album title for albums)

      // Try Spotify API first if it's a Spotify URL
      if (normalizedUrl.contains('spotify.com')) {
        print('LinkToTaskConverter: Detected Spotify URL, attempting API fetch');
        try {
          final spotifyData =
              await SpotifyApiService.getInfoFromUrl(normalizedUrl);
          if (spotifyData != null) {
            final type = spotifyData['type'];

            if (type == 'album') {
              // Album: headline = artist, link text = "album title on Spotify"
              headline = _normalizeWhitespace(spotifyData['artist'])!;
              notes = _normalizeWhitespace(spotifyData['album']);
              customLinkText =
                  '${_normalizeWhitespace(spotifyData['album'])} on Spotify'; // Link text includes " on Spotify"
              synopsis = pageDescription;
              print(
                  'LinkToTaskConverter: Successfully fetched album from Spotify API - Artist: "$headline", Album: "$notes"');
            } else if (type == 'playlist') {
              // Playlist: headline = playlist name, link text = "playlist name on Spotify"
              headline = _normalizeWhitespace(spotifyData['name'])!;
              notes = null;
              customLinkText =
                  '${_normalizeWhitespace(spotifyData['name'])} on Spotify'; // Link text includes " on Spotify"
              synopsis = pageDescription;

              // For playlists, prioritize category 74
              if (suggestedCategoryIds.contains(74)) {
                suggestedCategoryIds = [
                  74,
                  ...suggestedCategoryIds.where((id) => id != 74)
                ];
              }

              print(
                  'LinkToTaskConverter: Successfully fetched playlist from Spotify API - Name: "$headline"');
              print(
                  'LinkToTaskConverter: Reordered categories for playlist: $suggestedCategoryIds');
            } else if (type == 'track') {
              // Track: headline = artist, link text = "track name on Spotify", notes = track name
              headline = _normalizeWhitespace(spotifyData['artist'])!;
              notes = _normalizeWhitespace(spotifyData['track']);
              customLinkText =
                  '${_normalizeWhitespace(spotifyData['track'])} on Spotify'; // Link text includes " on Spotify"
              synopsis = pageDescription;
              print(
                  'LinkToTaskConverter: Successfully fetched track from Spotify API - Artist: "$headline", Track: "$notes"');
            }
          } else {
            print(
                'LinkToTaskConverter: Spotify API failed, trying title extraction');
            artistWorkInfo = extractArtistAndWorkFromSpotify(pageTitle);
          }
        } catch (e) {
          print('LinkToTaskConverter: Error fetching from Spotify API: $e');
          artistWorkInfo = extractArtistAndWorkFromSpotify(pageTitle);
        }
      } else if (normalizedUrl.contains('tidal.com')) {
        // Try Tidal API first if it's a Tidal URL
        print('LinkToTaskConverter: Detected Tidal URL, attempting API fetch');
        try {
          final tidalData = await TidalApiService.getInfoFromUrl(normalizedUrl);
          if (tidalData != null) {
            final type = tidalData['type'];

            if (type == 'album') {
              // Album: headline = artist, link text = "album title on TIDAL"
              headline = _normalizeWhitespace(tidalData['artist'])!;
              notes = _normalizeWhitespace(tidalData['album']);
              customLinkText =
                  '${_normalizeWhitespace(tidalData['album'])} on TIDAL';
              synopsis = pageDescription;
              print(
                  'LinkToTaskConverter: Successfully fetched album from Tidal API - Artist: "$headline", Album: "$notes"');
            } else if (type == 'playlist') {
              // Playlist: headline = playlist name, link text = "playlist name on TIDAL"
              headline = _normalizeWhitespace(tidalData['name'])!;
              notes = null;
              customLinkText =
                  '${_normalizeWhitespace(tidalData['name'])} on TIDAL';
              synopsis = pageDescription;

              // For playlists, prioritize category 74
              if (suggestedCategoryIds.contains(74)) {
                suggestedCategoryIds = [
                  74,
                  ...suggestedCategoryIds.where((id) => id != 74)
                ];
              }

              print(
                  'LinkToTaskConverter: Successfully fetched playlist from Tidal API - Name: "$headline"');
              print(
                  'LinkToTaskConverter: Reordered categories for playlist: $suggestedCategoryIds');
            } else if (type == 'track') {
              // Track: headline = artist, link text = "track name on TIDAL", notes = track name
              headline = _normalizeWhitespace(tidalData['artist'])!;
              notes = _normalizeWhitespace(tidalData['track']);
              customLinkText =
                  '${_normalizeWhitespace(tidalData['track'])} on TIDAL';
              synopsis = pageDescription;
              print(
                  'LinkToTaskConverter: Successfully fetched track from Tidal API - Artist: "$headline", Track: "$notes"');
            }
          } else {
            print(
                'LinkToTaskConverter: Tidal API failed, trying title extraction');
            artistWorkInfo = extractArtistAndWorkFromTidal(pageTitle);
          }
        } catch (e) {
          print('LinkToTaskConverter: Error fetching from Tidal API: $e');
          artistWorkInfo = extractArtistAndWorkFromTidal(pageTitle);
        }
      }

      if (artistWorkInfo != null) {
        headline = _normalizeWhitespace(artistWorkInfo.artist) ?? artistWorkInfo.artist;
        notes = _normalizeWhitespace(artistWorkInfo.work);
        synopsis = pageDescription;
        print(
            'LinkToTaskConverter: Extracted streaming media - Artist: "$headline", Work: "$notes"');
      } else if (customLinkText == null) {
        // Fallback if extraction fails and we don't have custom link text
        headline = _normalizeWhitespace(pageTitle) ?? pageTitle;
        notes = null;
        synopsis = pageDescription;
        print(
            'LinkToTaskConverter: Could not extract artist/work, using page title');
      }

      // Create HTML link with custom text if available
      if (customLinkText != null) {
        final htmlLink = '<a href="$normalizedUrl">$customLinkText</a>';

        // Check for existing task
        final existingTaskOriginalId =
            await _findExistingTaskOriginalId(normalizedUrl, userId);
        print(
            'LinkToTaskConverter: Existing task original_id: $existingTaskOriginalId');

        // Get synopsis from existing task if needed
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
    } else if (normalizedUrl.contains('imdb.com')) {
      // IMDb: clean up title and extract plot synopsis with type information
      headline = _normalizeWhitespace(LinkProcessor.cleanImdbTitle(pageTitle)) ?? LinkProcessor.cleanImdbTitle(pageTitle);
      notes = null;

      final imdbData = await _fetchImdbData(normalizedUrl, pageDescription);
      synopsis = imdbData['synopsis'];
      final mediaType = imdbData['type'];

      print('🎯 LinkToTaskConverter: IMDb processing complete:');
      print('   - Headline: "$headline"');
      print(
          '   - Synopsis: ${synopsis != null ? "${synopsis.length} chars" : "null"}');
      print(
          '   - Synopsis preview: ${synopsis != null ? synopsis.substring(0, synopsis.length > 100 ? 100 : synopsis.length) : "N/A"}...');
      print('   - Media type: $mediaType');

      // Override category suggestions based on OMDb API Type field
      if (mediaType != null) {
        if (mediaType == 'movie' || mediaType == 'short') {
          suggestedCategoryIds = [1]; // Movie category only
          print(
              'LinkToTaskConverter: IMDb Type is "$mediaType" - suggesting Movie category only');
        } else if (mediaType == 'series') {
          suggestedCategoryIds = [2]; // TV category only
          print(
              'LinkToTaskConverter: IMDb Type is "$mediaType" - suggesting TV category only');
        }
      }

      print('LinkToTaskConverter: IMDb link - cleaned headline: "$headline"');
    } else if (normalizedUrl.contains('letterboxd.com') ||
        normalizedUrl.contains('boxd.it')) {
      // Letterboxd: special handling
      headline = _normalizeWhitespace(pageTitle) ?? pageTitle;
      notes = null;
      synopsis = await _fetchLetterboxdSynopsis(normalizedUrl, pageDescription);
      print('LinkToTaskConverter: Letterboxd link - headline: "$headline"');
    } else {
      // General link: use page title as headline
      headline = _normalizeWhitespace(pageTitle) ?? pageTitle;
      notes = null;
      synopsis = pageDescription;
      print('LinkToTaskConverter: General link - headline: "$headline"');
    }

    // Create HTML link
    final htmlLink = '<a href="$normalizedUrl">$pageTitle</a>';

    // Check for existing task with this link (for original_id)
    final existingTaskOriginalId =
        await _findExistingTaskOriginalId(normalizedUrl, userId);
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
      String cleanUrl = url.trim();

      // Extract URL from HTML link if provided
      final htmlMatch =
          RegExp(r'<a[^>]+href="([^"]*)"[^>]*>').firstMatch(cleanUrl);
      if (htmlMatch != null) {
        cleanUrl = htmlMatch.group(1)!;
      }

      // Parse and normalize
      final uri = Uri.parse(cleanUrl);

      // For IMDb URLs, remove ALL query parameters (they're never needed)
      // The canonical IMDb URL is just: https://www.imdb.com/title/tt1234567/
      if (uri.host.contains('imdb.com')) {
        print(
            'LinkToTaskConverter: Normalizing IMDb URL - removing query parameters and extra path segments');

        // Extract the IMDb title ID (e.g., tt0111161)
        final idMatch = RegExp(r'/title/(tt\d+)').firstMatch(uri.path);
        String? imdbId;
        if (idMatch != null) {
          imdbId = idMatch.group(1);
        }

        if (imdbId == null) {
          print(
              '   Warning: Could not extract IMDb ID from path "${uri.path}". Returning original URL.');
          return cleanUrl;
        }

        // Rebuild the canonical IMDb URL: https://www.imdb.com/title/tt1234567/
        final cleanUri = Uri(
          scheme: uri.scheme,
          userInfo: uri.userInfo,
          host: uri.host,
          port: uri.hasPort ? uri.port : null,
          path: '/title/$imdbId/',
        );

        String result = cleanUri.toString();
        print('   Original: $url');
        print('   Cleaned:  $result');
        return result;
      }

      // For Spotify URLs, remove ALL query parameters
      // The canonical Spotify URL is: https://open.spotify.com/{type}/{id}
      if (uri.host.contains('spotify.com')) {
        print(
            'LinkToTaskConverter: Normalizing Spotify URL - removing query parameters');

        // Extract the type (album/playlist/track) and ID
        final pathMatch = RegExp(r'/(album|playlist|track)/([a-zA-Z0-9]+)')
            .firstMatch(uri.path);
        if (pathMatch != null) {
          final type = pathMatch.group(1);
          final id = pathMatch.group(2);

          // Rebuild the canonical Spotify URL
          final cleanUri = Uri(
            scheme: 'https',
            host: 'open.spotify.com',
            path: '/$type/$id',
          );

          String result = cleanUri.toString();
          print('   Original: $url');
          print('   Cleaned:  $result');
          return result;
        }
      }

      // For other URLs, remove common tracking parameters
      final cleanParams = Map<String, String>.from(uri.queryParameters);
      final trackingParams = {
        'utm_source',
        'utm_medium',
        'utm_campaign',
        'utm_term',
        'utm_content',
        'fbclid',
        'gclid',
        'ref',
        'source',
        '_campaign'
      };

      for (final param in trackingParams) {
        cleanParams.remove(param);
      }

      // Rebuild URL without tracking parameters
      final cleanUri = uri.replace(queryParameters: cleanParams);

      // Remove trailing ? if there are no parameters
      String result = cleanUri.toString();
      if (result.endsWith('?')) {
        result = result.substring(0, result.length - 1);
      }

      return result;
    } catch (e) {
      print('LinkToTaskConverter: Error normalizing URL "$url": $e');
      return url;
    }
  }

  /// Analyze URL to suggest appropriate categories based on domain and path
  static List<int> analyzeLinkForCategorySuggestions(String url) {
    print('LinkToTaskConverter.analyzeLinkForCategorySuggestions: Input URL: $url');

    try {
      final uri = Uri.parse(url.toLowerCase());
      final domain = uri.host;
      final path = uri.path;

      print('LinkToTaskConverter.analyzeLinkForCategorySuggestions: Domain: $domain, Path: $path');

      // IMDb links -> can be either movies or TV shows
      if (domain.contains('imdb.com')) {
        // Check if we can determine the type from the path
        if (path.contains('/tv/') || path.contains('tvseries')) {
          print('LinkToTaskConverter.analyzeLinkForCategorySuggestions: IMDb TV detected');
          return [2, 1]; // TV first, then movie
        } else if (path.contains('/title/')) {
          print('LinkToTaskConverter.analyzeLinkForCategorySuggestions: IMDb movie detected');
          return [1, 2]; // Movie first, then TV (more common)
        } else {
          print('LinkToTaskConverter.analyzeLinkForCategorySuggestions: IMDb generic');
          return [1, 2]; // Movie first, then TV
        }
      }

      // Letterboxd links -> primarily movies
      if (domain.contains('letterboxd.com')) {
        print('LinkToTaskConverter.analyzeLinkForCategorySuggestions: Letterboxd detected');
        return [1, 2]; // Movie first (primary), TV second (occasional)
      }

      // JustWatch links -> depends on path
      if (domain.contains('justwatch.com')) {
        if (path.contains('/movie/')) {
          print('LinkToTaskConverter.analyzeLinkForCategorySuggestions: JustWatch movie detected');
          return [1]; // Just movie
        } else if (path.contains('/tv-show/')) {
          print('LinkToTaskConverter.analyzeLinkForCategorySuggestions: JustWatch TV detected');
          return [2]; // Just TV
        } else {
          print('LinkToTaskConverter.analyzeLinkForCategorySuggestions: JustWatch generic');
          return [1, 2]; // Both options
        }
      }

      // Tidal and other streaming services
      if (domain.contains('tidal.com')) {
        print('LinkToTaskConverter.analyzeLinkForCategorySuggestions: Tidal detected, returning: $STREAMING_MEDIA_CATEGORY_IDS');
        return STREAMING_MEDIA_CATEGORY_IDS.toList();
      }

      // Spotify streaming service
      if (domain.contains('spotify.com')) {
        print('LinkToTaskConverter.analyzeLinkForCategorySuggestions: Spotify detected, returning: $STREAMING_MEDIA_CATEGORY_IDS');
        return STREAMING_MEDIA_CATEGORY_IDS.toList();
      }

      // Future: Apple Music, YouTube Music
      // if (domain.contains('music.apple.com')) {
      //   return STREAMING_MEDIA_CATEGORY_IDS.toList();
      // }

      print('LinkToTaskConverter.analyzeLinkForCategorySuggestions: No match found, returning empty list');
      return [];
    } catch (e) {
      print('LinkToTaskConverter: Error analyzing URL for categories: $e');
      return [];
    }
  }

  /// Fetch IMDb data from OMDb API, returns map with 'synopsis' and 'type' keys
  static Future<Map<String, String?>> _fetchImdbData(
      String url, String? pageDescription) async {
    try {
      // Extract IMDb ID from URL
      final imdbId = _extractImdbId(url);
      if (imdbId == null) {
        print('LinkToTaskConverter: Could not extract IMDb ID from URL: $url');
        return {'synopsis': pageDescription, 'type': null};
      }

      print('LinkToTaskConverter: Extracted IMDb ID: $imdbId');

      // Try OMDb API first
      print(
          '🔍 LinkToTaskConverter: Attempting to fetch IMDb data from OMDb API...');
      final omdbData = await _fetchFromOmdbApi(imdbId);
      if (omdbData != null) {
        print(
            '✅ LinkToTaskConverter: OMDb data received, building synopsis...');
        final synopsis = _buildSynopsisFromOmdbData(omdbData);
        final type = omdbData['Type']
            as String?; // "movie", "series", "short", or "episode"
        print(
            '📦 LinkToTaskConverter: Returning OMDb data - synopsis length: ${synopsis.length} chars, type: $type');
        return {'synopsis': synopsis, 'type': type};
      }

      // Fallback to HTML scraping if API fails
      print(
          '⚠️  LinkToTaskConverter: OMDb API returned null, falling back to HTML scraping');
      final synopsis = await _fetchImdbSynopsisFromHtml(url, pageDescription);
      print(
          '📦 LinkToTaskConverter: Returning HTML-scraped data - synopsis: ${synopsis != null ? "${synopsis.length} chars" : "null"}');
      return {'synopsis': synopsis, 'type': null};
    } catch (e) {
      print('LinkToTaskConverter: Error fetching IMDb data: $e');
      return {'synopsis': pageDescription, 'type': null};
    }
  }

  /// Fetch synopsis specifically for IMDb links using OMDb API (backward compatibility)
  static Future<String?> _fetchImdbSynopsis(
      String url, String? pageDescription) async {
    final data = await _fetchImdbData(url, pageDescription);
    return data['synopsis'];
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
          final apiKeyFromDotenv = dotenv.env['OMDB_API_KEY'];
          if (apiKeyFromDotenv != null && apiKeyFromDotenv.isNotEmpty) {
            apiKey = apiKeyFromDotenv;
          }
        } catch (e) {
          // Graceful fallback if dotenv not loaded
        }
      }

      // Skip API call if no key is configured
      if (apiKey == null || apiKey.isEmpty) {
        print(
            '❌ LinkToTaskConverter: OMDb API key not configured, skipping API call');
        print(
            '   - Build-time key: ${apiKeyFromBuild.isNotEmpty ? "present but empty" : "not set"}');
        print(
            '   - Runtime .env key: ${apiKey == null ? "not found" : "empty"}');
        return null;
      }

      print('✅ LinkToTaskConverter: OMDb API key found, making API call...');
      final omdbUrl =
          'http://www.omdbapi.com/?i=$imdbId&plot=full&apikey=$apiKey';
      print('🌐 LinkToTaskConverter: Calling OMDb API for $imdbId');

      final response =
          await http.get(Uri.parse(omdbUrl)).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        if (data['Response'] == 'True') {
          print('✅ LinkToTaskConverter: OMDb API SUCCESS!');
          print('   📝 Title: ${data['Title']}');
          print('   🎬 Type: ${data['Type']}');
          final plot = data['Plot']?.toString();
          final plotPreview = plot != null
              ? (plot.length > 100 ? plot.substring(0, 100) : plot)
              : "N/A";
          print('   📖 Plot: $plotPreview...');
          print(
              '   ⭐ Rating: ${data['Rated']} | IMDb: ${data['imdbRating']}/10');
          print('   ⏱️  Runtime: ${data['Runtime']}');
          print('   📅 Released: ${data['Released']}');
          return data;
        } else {
          print(
              '❌ LinkToTaskConverter: OMDb API error response: ${data['Error']}');
          return null;
        }
      }

      print(
          '❌ LinkToTaskConverter: OMDb API returned HTTP status ${response.statusCode}');
      return null;
    } catch (e) {
      print('LinkToTaskConverter: Error calling OMDb API: $e');
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
    print('📝 LinkToTaskConverter: Built synopsis from OMDb data:');
    print('   - Total length: ${synopsis.length} characters');
    print(
        '   - Preview: "${synopsis.substring(0, synopsis.length > 150 ? 150 : synopsis.length)}${synopsis.length > 150 ? "..." : ""}"');
    print(
        '   - Parts included: ${parts.length} (${parts.map((p) => p.split('.').first).join(", ")})');
    return synopsis;
  }

  /// Fallback: Fetch synopsis from HTML scraping
  static Future<String?> _fetchImdbSynopsisFromHtml(
      String url, String? pageDescription) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        },
      ).timeout(Duration(seconds: 10));

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
          print(
              'LinkToTaskConverter: Extracted IMDb synopsis from HTML: "${fullSynopsis.substring(0, fullSynopsis.length > 100 ? 100 : fullSynopsis.length)}..."');
          return fullSynopsis;
        }
      }

      return pageDescription;
    } catch (e) {
      print('LinkToTaskConverter: Error scraping HTML: $e');
      return pageDescription;
    }
  }

  /// Extract plot text from IMDb HTML
  static String? _extractImdbPlot(String html) {
    // Try to extract the plot synopsis from IMDb's HTML
    // IMDb typically has the plot in a <span data-testid="plot-xl"> or similar
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

          print(
              'LinkToTaskConverter: Found ${liMatches.length} metadata items in ipc-inline-list');

          if (liMatches.length >= 3) {
            // First item: Rating
            result['rating'] = _cleanHtmlText(liMatches[0].group(1) ?? '');

            // Second item: Runtime
            result['runtime'] = _cleanHtmlText(liMatches[1].group(1) ?? '');

            // Third item: Release date (may include country/format)
            result['releaseDate'] = _cleanHtmlText(liMatches[2].group(1) ?? '');

            print('LinkToTaskConverter: Rating: ${result['rating']}');
            print('LinkToTaskConverter: Runtime: ${result['runtime']}');
            print('LinkToTaskConverter: Release: ${result['releaseDate']}');
          }
        }
      }
    } catch (e) {
      print('LinkToTaskConverter: Error extracting IMDb metadata: $e');
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

  /// Fetch synopsis specifically for Letterboxd links
  static Future<String?> _fetchLetterboxdSynopsis(
      String url, String? pageDescription) async {
    // If we already have a good description from the page, use it
    if (pageDescription != null && pageDescription.isNotEmpty) {
      // Truncate if too long
      if (pageDescription.length > 200) {
        return '${pageDescription.substring(0, 200)}... <a href="$url">(more)</a>';
      } else {
        return '$pageDescription <a href="$url">(reference)</a>';
      }
    }

    // For Letterboxd, we could do additional scraping if needed
    // For now, just return the page description
    return pageDescription;
  }

  /// Find the original_id of an existing task with this link
  static Future<int?> _findExistingTaskOriginalId(
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
            final linkUrl = _extractUrlFromHtmlLink(linkText);
            if (linkUrl != null && _urlsMatch(url, linkUrl)) {
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
            final linkUrl = _extractUrlFromHtmlLink(linkText);
            if (linkUrl != null && _urlsMatch(url, linkUrl)) {
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
  static String? _extractUrlFromHtmlLink(String htmlLink) {
    final match = RegExp(r'<a[^>]+href="([^"]*)"').firstMatch(htmlLink);
    return match?.group(1);
  }

  /// Compare two URLs for matching (handles normalization)
  static bool _urlsMatch(String url1, String url2) {
    final normalized1 = normalizeUrl(url1);
    final normalized2 = normalizeUrl(url2);
    return normalized1 == normalized2;
  }
}
