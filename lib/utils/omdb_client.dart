import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Film/series metadata returned by the OMDb API.
///
/// See https://www.omdbapi.com/ for the full response schema.
class OmdbFilmInfo {
  final String title;
  final String? year;
  final String? plot;
  final String? posterUrl;
  final String? imdbId;
  final String? imdbRating;
  final String? type; // "movie", "series", "episode"

  OmdbFilmInfo({
    required this.title,
    this.year,
    this.plot,
    this.posterUrl,
    this.imdbId,
    this.imdbRating,
    this.type,
  });

  /// OMDb returns the string "N/A" for missing values; treat those as null.
  static String? _clean(dynamic value) {
    if (value == null) return null;
    final str = value.toString().trim();
    if (str.isEmpty || str == 'N/A') return null;
    return str;
  }

  factory OmdbFilmInfo.fromJson(Map<String, dynamic> json) {
    return OmdbFilmInfo(
      title: _clean(json['Title']) ?? 'Unknown Title',
      year: _clean(json['Year']),
      plot: _clean(json['Plot']),
      posterUrl: _clean(json['Poster']),
      imdbId: _clean(json['imdbID']),
      imdbRating: _clean(json['imdbRating']),
      type: _clean(json['Type']),
    );
  }

  @override
  String toString() => 'OmdbFilmInfo(title: $title, year: $year, imdbId: $imdbId)';
}

/// Client for the OMDb API (https://www.omdbapi.com/).
///
/// Provides sanctioned film metadata (plot, poster, IMDb id/rating) keyed by
/// IMDb id or by title+year, replacing HTML scraping of third-party movie
/// sites. All lookups return null when no API key is configured or no match is
/// found, so callers can fall back gracefully.
class OmdbClient {
  static const String baseUrl = 'https://www.omdbapi.com/';

  /// Resolves the API key from a compile-time define (production/web builds)
  /// with a dotenv fallback for local development. Mirrors [YouTubeApiService].
  static String? get apiKey {
    const apiKeyFromBuild = String.fromEnvironment('OMDB_API_KEY');
    if (apiKeyFromBuild.isNotEmpty) {
      return apiKeyFromBuild;
    }

    try {
      final apiKeyFromDotenv = dotenv.env['OMDB_API_KEY'];
      if (apiKeyFromDotenv != null && apiKeyFromDotenv.isNotEmpty) {
        return apiKeyFromDotenv;
      }
    } catch (e) {
      print('OmdbClient: Could not access dotenv variables: $e');
    }

    return null;
  }

  /// Whether a usable API key is configured.
  static bool get isAvailable {
    final key = apiKey;
    return key != null &&
        key.isNotEmpty &&
        key != 'your_omdb_api_key_here';
  }

  /// Look up a title by its IMDb id (e.g. "tt0111161"). Exact, unambiguous.
  static Future<OmdbFilmInfo?> getByImdbId(
    String imdbId, {
    bool fullPlot = false,
  }) async {
    if (imdbId.isEmpty) return null;
    return _request({
      'i': imdbId,
      'plot': fullPlot ? 'full' : 'short',
    });
  }

  /// Look up a title by name, optionally disambiguated by [year].
  ///
  /// Tries an exact title match first (with year, then without), then falls
  /// back to a fuzzy search and resolves the top hit by its IMDb id. Returns
  /// null if nothing matches.
  static Future<OmdbFilmInfo?> getByTitle(
    String title, {
    String? year,
    bool fullPlot = false,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) return null;
    final plot = fullPlot ? 'full' : 'short';
    final cleanYear = (year != null && year.trim().isNotEmpty) ? year.trim() : null;

    // 1. Exact title match with year.
    if (cleanYear != null) {
      final withYear =
          await _request({'t': trimmedTitle, 'y': cleanYear, 'plot': plot});
      if (withYear != null) return withYear;
    }

    // 2. Exact title match without year.
    final withoutYear = await _request({'t': trimmedTitle, 'plot': plot});
    if (withoutYear != null) return withoutYear;

    // 3. Fuzzy search, then resolve the top result for its full details.
    final topImdbId = await _searchTopImdbId(trimmedTitle, year: cleanYear);
    if (topImdbId != null) {
      return getByImdbId(topImdbId, fullPlot: fullPlot);
    }

    return null;
  }

  /// Runs a search (`s=`) and returns the IMDb id of the first result.
  static Future<String?> _searchTopImdbId(String title, {String? year}) async {
    final key = apiKey;
    if (key == null || key.isEmpty) return null;

    final params = {
      'apikey': key,
      's': title,
      if (year != null) 'y': year,
    };
    final uri = Uri.parse(baseUrl).replace(queryParameters: params);

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['Response'] != 'True') return null;

      final results = data['Search'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      final first = results.first as Map<String, dynamic>;
      final imdbId = first['imdbID']?.toString();
      return (imdbId != null && imdbId.isNotEmpty) ? imdbId : null;
    } catch (e) {
      print('OmdbClient: Search error for "$title": $e');
      return null;
    }
  }

  /// Performs a single OMDb request with the given query params (the API key is
  /// added automatically). Returns an [OmdbFilmInfo] on a successful match.
  static Future<OmdbFilmInfo?> _request(Map<String, String> params) async {
    final key = apiKey;
    if (key == null || key.isEmpty) {
      print('OmdbClient: No API key configured');
      return null;
    }

    final uri = Uri.parse(baseUrl).replace(queryParameters: {
      'apikey': key,
      ...params,
    });

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        print('OmdbClient: HTTP ${response.statusCode} for $params');
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['Response'] != 'True') {
        print('OmdbClient: No match for $params (${data['Error']})');
        return null;
      }

      return OmdbFilmInfo.fromJson(data);
    } catch (e) {
      print('OmdbClient: Request error for $params: $e');
      return null;
    }
  }
}
