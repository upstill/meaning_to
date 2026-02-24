import 'package:html/dom.dart' as dom;
import 'package:meaning_to/utils/youtube_api.dart';

/// Defines how content should be extracted from a specific website
enum ExtractionStrategy {
  cssSelectors, // Use CSS selectors to extract content
  api, // Use API calls (future expansion)
  custom, // Custom extraction logic (future expansion)
}

/// Configuration for extracting content from a specific website
class SiteConfig {
  final String domain;
  final String displayName;
  final ExtractionStrategy strategy;
  final Map<String, String> cssSelectors;
  final Map<String, dynamic>? customSettings;
  final bool requiresProxy;

  const SiteConfig({
    required this.domain,
    required this.displayName,
    this.strategy = ExtractionStrategy.cssSelectors,
    required this.cssSelectors,
    this.customSettings,
    this.requiresProxy = false,
  });

  /// Extract title using API first (for supported sites), then fall back to HTML parsing
  Future<String?> extractTitleWithApi(
      String url, dom.Document? document) async {
    // For YouTube, try API first
    if (domain == 'youtube.com' && YouTubeApiService.isAvailable) {
      print('SiteConfig: Attempting YouTube API extraction for: $url');
      try {
        final videoInfo = await YouTubeApiService.getVideoInfoFromUrl(url);
        if (videoInfo != null) {
          String title = videoInfo.title;
          // Apply title processing (remove "- YouTube" suffix)
          title = _processTitle(title) ?? title;
          print(
              'SiteConfig: Successfully extracted title via YouTube API: "$title"');
          return title;
        }
      } catch (e) {
        print('SiteConfig: YouTube API extraction failed: $e');
      }
      print(
          'SiteConfig: YouTube API extraction failed, will need proxy for scraping fallback');
    }

    // Fall back to HTML parsing
    if (document != null) {
      print('SiteConfig: Falling back to HTML parsing for title extraction');
      return extractTitle(document);
    }

    return null;
  }

  /// Check if this site needs proxy for fallback scraping
  bool needsProxyForFallback() {
    return domain == 'youtube.com' ||
        customSettings?['requiresProxyFallback'] == true;
  }

  /// Extract title from the document using configured selectors
  String? extractTitle(dom.Document document) {
    String? title;

    // Try primary title selector
    final titleSelector = cssSelectors['title'];
    if (titleSelector != null) {
      try {
        final element = document.querySelector(titleSelector);
        if (element != null) {
          // For meta tags, extract from content attribute; for other elements, use text
          final useMetaAttributes =
              customSettings?['useMetaAttributes'] == true;
          if (useMetaAttributes && element.localName == 'meta') {
            title = element.attributes['content']?.trim();
          } else if (domain == 'justwatch.com') {
            // For JustWatch, extract only direct text content (not nested spans)
            String directText = '';
            for (final node in element.nodes) {
              if (node.nodeType == 3) {
                // Text node
                directText += node.text ?? '';
              }
            }
            title = directText.trim();
          } else {
            title = element.text.trim();
          }
        }
      } catch (e) {
        print('SiteConfig: Error extracting title for $domain: $e');
      }
    }

    // Try fallback selector if primary failed
    if ((title == null || title.isEmpty)) {
      final fallbackSelector = cssSelectors['title_fallback'];
      if (fallbackSelector != null) {
        try {
          final element = document.querySelector(fallbackSelector);
          if (element != null) {
            // For meta tags, extract from content attribute; for other elements, use text
            final useMetaAttributes =
                customSettings?['useMetaAttributes'] == true;
            if (useMetaAttributes && element.localName == 'meta') {
              title = element.attributes['content']?.trim();
            } else {
              title = element.text.trim();
            }
          }
        } catch (e) {
          print('SiteConfig: Error extracting fallback title for $domain: $e');
        }
      }

      // For YouTube specifically, try additional fallback methods when proxies fail
      if ((title == null || title.isEmpty) && domain == 'youtube.com') {
        // Try og:title meta tag
        try {
          final ogTitleElement =
              document.querySelector('meta[property="og:title"]');
          if (ogTitleElement != null) {
            title = ogTitleElement.attributes['content']?.trim();
          }
        } catch (e) {
          print('SiteConfig: Error extracting og:title: $e');
        }

        // Try twitter:title meta tag
        if ((title == null || title.isEmpty)) {
          try {
            final twitterTitleElement =
                document.querySelector('meta[name="twitter:title"]');
            if (twitterTitleElement != null) {
              title = twitterTitleElement.attributes['content']?.trim();
            }
          } catch (e) {
            print('SiteConfig: Error extracting twitter:title: $e');
          }
        }
      }
    }

    // Apply custom title processing
    if (title != null && title.isNotEmpty) {
      title = _processTitle(title);
    }

    return title;
  }

  /// Apply custom title processing based on site configuration
  String? _processTitle(String title) {
    final shouldTruncate = customSettings?['truncateTitle'] == true;
    if (!shouldTruncate) return title;

    String processedTitle = title;

    // Apply year truncation pattern
    final yearPattern = customSettings?['titleTruncationPattern'] as String?;
    if (yearPattern != null) {
      processedTitle =
          processedTitle.replaceFirst(RegExp(yearPattern), '').trim();
    }

    // Apply streaming text removal for JustWatch
    final streamingPattern = customSettings?['streamingPattern'] as String?;
    if (streamingPattern != null) {
      processedTitle = processedTitle
          .replaceFirst(RegExp(streamingPattern, caseSensitive: false), '')
          .trim();
    }

    // Remove invisible characters at the beginning (like zero-width space)
    processedTitle = processedTitle.replaceFirst(RegExp(r'^\u200E?'), '');

    return processedTitle;
  }

  /// Extract description from the document using configured selectors
  String? extractDescription(dom.Document document) {
    String? description;

    // Try primary description selector
    final descriptionSelector = cssSelectors['description'];
    if (descriptionSelector != null) {
      try {
        final element = document.querySelector(descriptionSelector);
        if (element != null) {
          // For meta tags, always extract from content attribute; for other elements, use text
          if (element.localName == 'meta') {
            description = element.attributes['content']?.trim();
          } else {
            description = element.text.trim();
          }
        }
      } catch (e) {
        print('SiteConfig: Error extracting description for $domain: $e');
      }
    }

    // Try fallback selector if primary failed
    if ((description == null || description.isEmpty)) {
      final fallbackSelector = cssSelectors['description_fallback'];
      if (fallbackSelector != null) {
        try {
          final element = document.querySelector(fallbackSelector);
          if (element != null) {
            // For meta tags, always extract from content attribute; for other elements, use text
            if (element.localName == 'meta') {
              description = element.attributes['content']?.trim();
            } else {
              description = element.text.trim();
            }
          }
        } catch (e) {
          print(
              'SiteConfig: Error extracting fallback description for $domain: $e');
        }
      }
    }

    return description;
  }

  /// Check if this configuration should handle the given URL
  bool shouldHandle(String url) {
    return url.contains(domain);
  }
}

/// Registry of site configurations for content extraction
class SiteConfigRegistry {
  static final Map<String, SiteConfig> _configs = {
    'justwatch.com': const SiteConfig(
      domain: 'justwatch.com',
      displayName: 'JustWatch',
      cssSelectors: {
        'title': 'h1.title-detail-hero__details__title',
        'description': 'div#synopsis p',
        'title_fallback': 'h1',
      },
      requiresProxy: true,
      customSettings: {
        'truncateTitle': true,
        'titleTruncationPattern': r'\s*\(\d{4}\).*$', // Remove year and after
        'streamingPattern':
            r'\s*streaming:?\s*where to watch.*$', // Remove streaming text
      },
    ),
    'letterboxd.com': const SiteConfig(
      domain: 'letterboxd.com',
      displayName: 'Letterboxd',
      cssSelectors: {
        'title': 'h1.headline-1',
        'description': '.review .body-text p',
        'title_fallback': 'h1',
      },
      requiresProxy: true,
      customSettings: {
        'truncateTitle': true,
        'titleTruncationPattern': r'\s*\(\d{4}\).*$', // Remove year and after
      },
    ),
    'boxd.it': const SiteConfig(
      domain: 'boxd.it',
      displayName: 'Letterboxd',
      cssSelectors: {
        'title': 'h1.headline-1',
        'description': '.review .body-text p',
        'title_fallback': 'h1',
      },
      requiresProxy: true,
      customSettings: {
        'truncateTitle': true,
        'titleTruncationPattern': r'\s*\(\d{4}\).*$', // Remove year and after
      },
    ),
    'youtube.com': const SiteConfig(
      domain: 'youtube.com',
      displayName: 'YouTube',
      cssSelectors: {
        'title': 'meta[name="title"]',
        'description': 'meta[name="description"]',
        'title_fallback': 'title',
        'description_fallback': 'meta[property="og:description"]',
      },
      requiresProxy: false, // Use YouTube API first, proxy only as fallback
      customSettings: {
        'useMetaAttributes': true, // Extract from attributes, not text content
        'truncateTitle': true,
        'titleTruncationPattern':
            r'\s*-\s*YouTube\s*$', // Remove "- YouTube" suffix
      },
    ),
    'ted.com': const SiteConfig(
      domain: 'ted.com',
      displayName: 'TED',
      cssSelectors: {
        'title': 'meta[name="title"]', // Primary: Meta title tag
        'title_fallback': 'meta[property="og:title"]', // Fallback: OG title
        'description': 'meta[name="description"]',
        'description_fallback': 'meta[property="og:description"]',
      },
      requiresProxy: true, // TED.com blocks direct requests
      customSettings: {
        'useMetaAttributes': true, // Extract from attributes, not text content
      },
    ),
    'amazon.com': const SiteConfig(
      domain: 'amazon.com',
      displayName: 'Amazon',
      cssSelectors: {
        'title': 'meta[name="title"]',         // Primary: meta name="title"
        'title_fallback': 'meta[property="og:title"]', // Fallback: OG title
        'description': 'meta[name="description"]',
        'description_fallback': 'meta[property="og:description"]',
      },
      requiresProxy: true, // Amazon blocks direct non-browser requests
      customSettings: {
        'useMetaAttributes': true,
      },
    ),
    'tidal.com': const SiteConfig(
      domain: 'tidal.com',
      displayName: 'TIDAL',
      cssSelectors: {
        'title': 'h2.wave-text-title-bold', // Primary: TIDAL title element
        'title_fallback': 'title', // Fallback: HTML title tag
        'description': 'div[data-test="biography"]', // Primary: Biography div
        'description_fallback':
            'meta[property="og:description"]', // Fallback: OG description
      },
      requiresProxy: true, // TIDAL requires proxy due to CORS
      customSettings: {
        'useMetaAttributes':
            false, // Extract text content from h2, but meta tags always use attributes
      },
    ),
  };

  /// Get configuration for a specific domain
  static SiteConfig? getConfigForDomain(String domain) {
    return _configs[domain];
  }

  /// Default configuration for unregistered sites
  static const SiteConfig _defaultConfig = SiteConfig(
    domain: '*',
    displayName: 'Generic Site',
    cssSelectors: {
      'title': 'title', // HTML title tag
      'title_fallback': 'h1', // First h1 as fallback
      'description': 'meta[name="description"]', // Meta description
      'description_fallback':
          'meta[property="og:description"]', // OG description fallback
    },
    customSettings: {
      'useMetaAttributes': true, // Extract from attributes, not text content
    },
  );

  /// Get configuration for a URL
  static SiteConfig getConfigForUrl(String url) {
    for (final config in _configs.values) {
      if (config.shouldHandle(url)) {
        return config;
      }
    }
    // Return default configuration for unregistered sites
    return _defaultConfig;
  }

  /// Check if a URL should use proxy based on its configuration
  static bool shouldUseProxy(String url) {
    final config = getConfigForUrl(url);
    return config?.requiresProxy ?? false;
  }

  /// Get all supported domains
  static List<String> getSupportedDomains() {
    return _configs.keys.toList();
  }

  /// Add a new site configuration (for future extensibility)
  static void addConfig(String domain, SiteConfig config) {
    _configs[domain] = config;
  }

  /// Remove a site configuration
  static void removeConfig(String domain) {
    _configs.remove(domain);
  }

  /// Get all configurations
  static Map<String, SiteConfig> getAllConfigs() {
    return Map.unmodifiable(_configs);
  }
}
