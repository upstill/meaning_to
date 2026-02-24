import 'package:meaning_to/utils/streaming_media_constants.dart';

/// A single rule mapping a domain (and optional path pattern) to a list of
/// suggested category originalIds.
class CategorySuggestionRule {
  final String domain;        // matched via uri.host.contains(domain)
  final String? pathPattern;  // optional, matched via uri.path.contains(pathPattern)
  final List<int> categoryIds;

  const CategorySuggestionRule({
    required this.domain,
    this.pathPattern,
    required this.categoryIds,
  });
}

/// Registry of domain/path → category suggestion rules.
///
/// Two-pass evaluation ensures path-specific rules always beat domain-only
/// fallbacks regardless of insertion order.
class CategorySuggestionRegistry {
  static final List<CategorySuggestionRule> _rules = [
    // JustWatch — path-specific first, domain fallback last
    CategorySuggestionRule(domain: 'justwatch.com', pathPattern: '/movie/', categoryIds: [1]),
    CategorySuggestionRule(domain: 'justwatch.com', pathPattern: '/tv-show/', categoryIds: [2]),
    CategorySuggestionRule(domain: 'justwatch.com', categoryIds: [1, 2]),

    // IMDb — TV path patterns first
    CategorySuggestionRule(domain: 'imdb.com', pathPattern: '/tv/', categoryIds: [2, 1]),
    CategorySuggestionRule(domain: 'imdb.com', pathPattern: 'tvseries', categoryIds: [2, 1]),
    CategorySuggestionRule(domain: 'imdb.com', categoryIds: [1, 2]),

    // Letterboxd — film path first
    CategorySuggestionRule(domain: 'letterboxd.com', pathPattern: '/film/', categoryIds: [1]),
    CategorySuggestionRule(domain: 'letterboxd.com', categoryIds: [1, 2]),

    // boxd.it (Letterboxd short links)
    CategorySuggestionRule(domain: 'boxd.it', categoryIds: [1, 2]),

    // YouTube — watch URLs suggest movies/shows
    CategorySuggestionRule(domain: 'youtube.com', pathPattern: '/watch', categoryIds: [1]),

    // Streaming music services — path-specific first, domain fallback last
    CategorySuggestionRule(domain: 'tidal.com', pathPattern: '/playlist/', categoryIds: [74, 41]),
    CategorySuggestionRule(domain: 'tidal.com', categoryIds: STREAMING_MEDIA_CATEGORY_IDS),
    CategorySuggestionRule(domain: 'spotify.com', categoryIds: STREAMING_MEDIA_CATEGORY_IDS),
  ];

  /// Returns the ordered list of suggested category originalIds for [url].
  ///
  /// Pass 1: path-specific rules (those with a non-null [pathPattern]).
  /// Pass 2: domain-only fallbacks (those with a null [pathPattern]).
  /// Returns [] if no rule matches.
  static List<int> getSuggestionsForUrl(String url) {
    try {
      final uri = Uri.parse(url.toLowerCase());

      // Pass 1: path-specific rules
      for (final rule in _rules.where((r) => r.pathPattern != null)) {
        if (uri.host.contains(rule.domain) &&
            uri.path.contains(rule.pathPattern!)) {
          return rule.categoryIds;
        }
      }

      // Pass 2: domain-only fallbacks
      for (final rule in _rules.where((r) => r.pathPattern == null)) {
        if (uri.host.contains(rule.domain)) {
          return rule.categoryIds;
        }
      }

      return [];
    } catch (e) {
      print('CategorySuggestionRegistry: Error parsing URL "$url": $e');
      return [];
    }
  }

  /// Appends a new rule to the registry at runtime.
  static void addRule(CategorySuggestionRule rule) => _rules.add(rule);
}
