import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:meaning_to/models/icon.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:link_enrichment_core/models/enrichment_context.dart';
import 'package:link_enrichment_core/models/enrichment_request.dart';
import 'package:link_enrichment_core/models/enrichment_status.dart';
import 'package:link_enrichment_core/rules/site_rule_provider.dart';
import 'package:link_enrichment_core/rules/default_site_rule_provider.dart';
import 'package:link_enrichment_core/service/enrichment_service.dart';
import 'package:meaning_to/utils/youtube_api.dart';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

/// Container for webpage title and description extracted together
class WebpageContent {
  final String title;
  final String? description;

  WebpageContent({required this.title, this.description});
}

class ProcessedLink {
  final String url;
  final String? title;
  final String? favicon;
  final LinkType type;
  final String domain;
  final String originalLink; // Store the original/modified link text
  final String? description; // Extracted description (for JustWatch, etc.)

  ProcessedLink({
    required this.url,
    this.title,
    this.favicon,
    required this.type,
    required this.domain,
    required this.originalLink,
    this.description,
  });

  String get displayTitle => title ?? url;

  // Widget to display the link with its icon
  Widget buildLinkWidget() {
    return LinkDisplayWidget(
      linkText: originalLink,
      showIcon: true,
      showTitle: true,
    );
  }

  // Widget to display a list of links
  static Widget buildLinksList(List<ProcessedLink> links) {
    if (links.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Links:', style: TextStyle(fontWeight: FontWeight.bold)),
        ...links
            .map((link) => LinkDisplayWidget(
                  linkText: link.originalLink,
                  showIcon: true,
                  showTitle: true,
                ))
            .toList(),
      ],
    );
  }
}

enum LinkType { webpage, youtube, github, twitter, other }

class LinkProcessor {
  static String? get browserlessApiKey => dotenv.env['BROWSERLESS_API_KEY'];

  static final Map<String, List<Map<String, String>>> _cookies = {};

  // Global cache for webpage content to avoid redundant fetches
  static final Map<String, WebpageContent> _webpageContentCache = {};
  static const Duration _cacheExpiration =
      Duration(minutes: 5); // Cache for 5 minutes
  static final Map<String, DateTime> _cacheTimestamps = {};

  // Request deduplication - track in-flight requests to prevent duplicate fetches
  static final Map<String, Future<WebpageContent?>> _pendingRequests = {};
  static final SiteRuleProvider _ruleProvider = DefaultSiteRuleProvider();
  static final EnrichmentService _enrichmentService = EnrichmentService(
    youtubeResolver: (url) async {
      final info = await YouTubeApiService.getVideoInfoFromUrl(url);
      if (info == null) return null;
      return YoutubeVideoInfo(
        title: info.title,
        description: info.description,
      );
    },
  );

  static Map<String, String>? parseCookieString(String cookieStr) {
    try {
      final parts = cookieStr.split(';').map((s) => s.trim()).toList();
      if (parts.isEmpty) return null;

      final firstPart = parts.first.split('=');
      if (firstPart.length != 2) return null;

      final cookie = <String, String>{
        'name': firstPart[0],
        'value': firstPart[1],
      };

      for (var i = 1; i < parts.length; i++) {
        final part = parts[i].split('=');
        if (part.length == 2) {
          cookie[part[0].toLowerCase()] = part[1];
        } else {
          cookie[part[0].toLowerCase()] = 'true';
        }
      }

      return cookie;
    } catch (e) {
      print('Error parsing cookie string: $e');
      return null;
    }
  }

  static void addCookie(String domain, Map<String, String> cookie) {
    _cookies[domain] ??= [];
    _cookies[domain]!.add(cookie);
  }

  static void clearCookies(String domain) {
    _cookies.remove(domain);
  }

  static String _getCookieHeader(String domain) {
    final cookies = _cookies[domain] ?? [];
    return cookies.map((c) => '${c['name']}=${c['value']}').join('; ');
  }

  static Future<List<ProcessedLink>> fetchLinks(String url) async {
    try {
      final uri = Uri.parse(url);
      final domain = uri.host;
      final cookieHeader = _getCookieHeader(domain);

      final response = await http.get(
        uri,
        headers: {
          if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch URL: ${response.statusCode}');
      }

      // Explicitly decode as UTF-8 to handle special characters (e.g., Björk)
      final htmlContent = utf8.decode(response.bodyBytes, allowMalformed: true);
      return _processHtml(url, htmlContent);
    } catch (e) {
      print('Error fetching links: $e');
      rethrow;
    }
  }

  static Future<List<ProcessedLink>> fetchLinksFromBrowserless(
    String url,
    String domain,
  ) async {
    final apiKey = browserlessApiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Browserless API key not found');
    }

    try {
      final cookieHeader = _getCookieHeader(domain);
      final response = await http.post(
        Uri.parse('https://chrome.browserless.io/content'),
        headers: {
          'Cache-Control': 'no-cache',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'url': url,
          'waitFor': 5000, // Wait for 5 seconds to let JavaScript execute
          'headers': {
            if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
            'User-Agent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36',
          },
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Browserless request failed: ${response.statusCode}');
      }

      // Explicitly decode as UTF-8 to handle special characters (e.g., Björk)
      final htmlContent = utf8.decode(response.bodyBytes, allowMalformed: true);
      return _processHtml(url, htmlContent);
    } catch (e) {
      print('Error fetching links from Browserless: $e');
      rethrow;
    }
  }

  static List<ProcessedLink> _processHtml(String baseUrl, String html) {
    final document = html_parser.parse(html);
    final links = <ProcessedLink>[];
    final baseUri = Uri.parse(baseUrl);

    // Find all links
    for (final element in document.querySelectorAll('a[href]')) {
      final href = element.attributes['href'];
      if (href == null || href.isEmpty) continue;

      try {
        // Resolve relative URLs
        final uri = baseUri.resolve(href);
        final url = uri.toString();

        // Skip if not http/https
        if (!url.startsWith('http://') && !url.startsWith('https://')) continue;

        // Get link text, fallback to URL if no text
        var title = element.text.trim();
        if (title.isEmpty) title = url;

        // Try to find favicon
        String? favicon;
        final faviconElement = document
            .querySelector('link[rel="icon"], link[rel="shortcut icon"]');
        if (faviconElement != null) {
          final faviconHref = faviconElement.attributes['href'];
          if (faviconHref != null) {
            favicon = baseUri.resolve(faviconHref).toString();
          }
        }

        // Create HTML for display
        final displayHtml = '<a href="$url">$title</a>';

        links.add(ProcessedLink(
          url: url,
          title: title,
          favicon: favicon,
          type: LinkType.webpage,
          domain: baseUri.host,
          originalLink: displayHtml,
        ));
      } catch (e) {
        print('Error processing link: $e');
      }
    }

    return links;
  }

  static bool isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && uri.hasAuthority;
    } catch (e) {
      return false;
    }
  }

  static String extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      final rawDomain = uri.host.toLowerCase();
      return rawDomain;
    } catch (e) {
      return '';
    }
  }

  static (String, String?) parseHtmlLink(String html) {
    if (!html.startsWith('<a href="')) {
      return (html, null);
    }

    final document = html_parser.parse(html);
    final anchor = document.querySelector('a');
    if (anchor == null) {
      return (html, null);
    }

    final href = anchor.attributes['href'];
    final text = anchor.text;
    return (href ?? html, text.isEmpty ? null : text);
  }

  static LinkType determineLinkType(String url) {
    final uri = Uri.parse(url);
    final host = uri.host.toLowerCase();

    if (host.contains('youtube.com') || host.contains('youtu.be')) {
      return LinkType.youtube;
    } else if (host.contains('github.com')) {
      return LinkType.github;
    } else if (host.contains('twitter.com') || host.contains('x.com')) {
      return LinkType.twitter;
    } else if (uri.hasScheme && uri.hasAuthority) {
      return LinkType.webpage;
    }
    return LinkType.other;
  }

  // ── site_table.dart helpers ───────────────────────────────────────────────

  /// Determine the current [EnrichmentContext] based on the runtime environment.
  static EnrichmentContext _getFetchContext() {
    if (kIsWeb) return EnrichmentContext.web;
    bool isTest = false;
    try {
      isTest = Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {}
    return isTest ? EnrichmentContext.test : EnrichmentContext.native;
  }

  // ─────────────────────────────────────────────────────────────────────────

  /// Fetches both title and description from a webpage in one request
  static Future<WebpageContent?> fetchWebpageContent(String url) async {
    try {
      // Check cache first
      final cachedContent = _getCachedContent(url);
      if (cachedContent != null) {
        return cachedContent;
      }

      // Check if request is already in progress
      if (_pendingRequests.containsKey(url)) {
        return await _pendingRequests[url];
      }

      // Start new request and track it
      final requestFuture = _performWebpageContentFetch(url);
      _pendingRequests[url] = requestFuture;

      try {
        final result = await requestFuture;
        return result;
      } finally {
        // Clean up pending request
        _pendingRequests.remove(url);
      }
    } catch (e) {
      print('Error fetching webpage content: $e');
      return null;
    }
  }

  /// Internal method to perform webpage enrichment via the core service.
  static Future<WebpageContent?> _performWebpageContentFetch(String url) async {
    try {
      final result = await _enrichmentService.enrich(
        EnrichmentRequest(
          url: url,
          context: _getFetchContext(),
          allowDeferred: true,
        ),
      );

      if (result.title != null && result.title!.isNotEmpty) {
        final content = WebpageContent(
          title: result.title!,
          description: result.synopsis,
        );
        _cacheContent(url, content);
        return content;
      }

      if (result.status == EnrichmentStatus.deferred) {
        print('LinkProcessor: Enrichment deferred for $url');
      }
      return null;
    } catch (e) {
      print('LinkProcessor: Error in _performWebpageContentFetch: $e');
      return null;
    }
  }

  // Cache helper methods for webpage content
  static WebpageContent? _getCachedContent(String url) {
    final cachedContent = _webpageContentCache[url];

    if (cachedContent != null) {
      final timestamp = _cacheTimestamps[url];

      if (timestamp != null) {
        final age = DateTime.now().difference(timestamp);

        if (age < _cacheExpiration) {
          return cachedContent;
        } else {
          // Cache expired, remove it
          _webpageContentCache.remove(url);
          _cacheTimestamps.remove(url);
        }
      }
    }
    return null;
  }

  static void _cacheContent(String url, WebpageContent content) {
    _webpageContentCache[url] = content;
    _cacheTimestamps[url] = DateTime.now();
  }

  // Method to clear cache if needed
  static void clearWebpageContentCache() {
    _webpageContentCache.clear();
    _cacheTimestamps.clear();
  }

  static Future<String?> fetchWebpageTitle(String url) async {
    try {
      print('LinkProcessor: Fetching title for URL: $url');
      final content = await fetchWebpageContent(url);
      return content?.title;
    } catch (e) {
      print('LinkProcessor: Exception in fetchWebpageTitle for URL $url: $e');
      return null;
    }
  }

  static Future<ProcessedLink> processLinkForDisplay(String linkText) async {
    print(
        'LinkProcessor.processLinkForDisplay: Processing linkText: "$linkText"');
    // Parse the HTML link to get URL and title
    final (url, title) = parseHtmlLink(linkText);
    print(
        'LinkProcessor.processLinkForDisplay: Extracted URL: "$url", title: "$title"');

    if (!isValidUrl(url)) {
      return ProcessedLink(
        url: url,
        type: LinkType.other,
        domain: '',
        originalLink: linkText,
        description: null,
      );
    }

    final type = determineLinkType(url);
    final domain = extractDomain(url);

    // Special debugging for JustWatch
    if (url.contains('justwatch')) {}

    // Check if this is an internal link to a category
    String? finalTitle = title;
    print(
        'LinkProcessor.processLinkForDisplay: Initial finalTitle: "$finalTitle"');

    if (finalTitle == null || finalTitle.isEmpty) {
      finalTitle = await _handleInternalCategoryLink(url, domain);
      print(
          'LinkProcessor.processLinkForDisplay: After internal link check: "$finalTitle"');
    }

    // If we still don't have a title and it's not an internal link, try to fetch it from the webpage
    if (finalTitle == null || finalTitle.isEmpty) {
      print(
          'LinkProcessor.processLinkForDisplay: No title found, attempting to fetch from webpage...');
      final content = await fetchWebpageContent(url);
      if (content != null) {
        finalTitle = content.title;
        print(
            'LinkProcessor.processLinkForDisplay: After webpage fetch: "$finalTitle"');
        // Note: Description is available in content.description but not used here
        // as this method only returns ProcessedLink for display purposes
      }
    } else {
      print(
          'LinkProcessor.processLinkForDisplay: Using existing title, skipping webpage fetch');
    }

    // Get icon for domain with error handling (skip for internal links)
    String? favicon;
    if (finalTitle == null || !_isInternalCategoryLink(url, domain)) {
      try {
        if (url.contains('justwatch') || url.contains('boxd.it')) {
          // Skip favicon fetching for these domains
        }
        final domainIcon = await DomainIcon.getIconForDomain(domain);
        if (domainIcon != null) {
          favicon = domainIcon.iconUrl;
          if (url.contains('justwatch') || url.contains('boxd.it')) {}
        } else if (url.contains('justwatch') || url.contains('boxd.it')) {}
      } catch (e) {
        print('Error processing icon for domain $domain: $e');
        if (url.contains('justwatch')) {}
      }
    }

    // Clean IMDb titles before creating final link
    if (finalTitle != null && url.contains('imdb.com')) {
      finalTitle = cleanImdbTitle(finalTitle);
      print(
          'LinkProcessor.processLinkForDisplay: Cleaned IMDb title: "$finalTitle"');
    }

    // Create the final HTML link with the title
    final finalLink = '<a href="$url">${finalTitle ?? url}</a>';

    return ProcessedLink(
      url: url,
      title: finalTitle,
      favicon: favicon,
      type: type,
      domain: domain,
      originalLink: finalLink, // Use the final HTML link with the title
      description: null, // Description not fetched in processLinkForDisplay
    );
  }

  /// Checks if a URL is an internal link to a category
  static bool _isInternalCategoryLink(String url, String domain) {
    return domain == 'meaning-to.me' && url.contains('/category/');
  }

  /// Handles internal category links by looking up the category in the database
  static Future<String?> _handleInternalCategoryLink(
      String url, String domain) async {
    if (!_isInternalCategoryLink(url, domain)) {
      return null;
    }

    try {
      // Extract category ID directly from the meaning-to.me URL
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;

      if (pathSegments.length >= 2 && pathSegments[0] == 'category') {
        final categoryIdStr = pathSegments[1];
        final categoryId = int.tryParse(categoryIdStr);

        if (categoryId != null) {
          final headline = await ApiClient.getCategoryHeadlineById(categoryId);
          if (headline != null) {
            print('LinkProcessor: Found internal category headline: $headline');
            return headline;
          }
        }
      }
    } catch (e) {
      print('Error handling internal category link: $e');
    }

    return null;
  }

  static Future<List<ProcessedLink>> processLinksForDisplay(
      List<String> links) async {
    final processedLinks = <ProcessedLink>[];

    for (final link in links) {
      try {
        // Parse the HTML link
        final document = html_parser.parse(link);
        final anchor = document.querySelector('a');
        if (anchor == null) continue;

        final url = anchor.attributes['href'];
        if (url == null || url.isEmpty) continue;

        final title = anchor.text.trim();
        if (title.isEmpty) continue;

        // Create a simple display HTML
        final displayHtml = '<a href="$url">$title</a>';

        processedLinks.add(ProcessedLink(
          url: url,
          title: title,
          favicon: null,
          type: LinkType.webpage,
          domain: extractDomain(url),
          originalLink: displayHtml,
        ));
      } catch (e) {
        print('Error processing link for display: $e');
      }
    }

    return processedLinks;
  }

  /// Clean up IMDb title by removing year and IMDb-specific suffixes.
  /// Ensures consistent title formatting for both UI display and task creation.
  static String cleanImdbTitle(String title) {
    String cleaned = title.trim();

    // Remove everything from the first parenthesis or hyphen suffix onward.
    // Examples handled:
    //   "Movie Title (1994) - IMDb"                -> "Movie Title"
    //   "Series Name (TV Series 2008–2013) - IMDb" -> "Series Name"
    //   "Short Film (Short 2020) - Reference view" -> "Short Film"
    final truncationMatch =
        RegExp(r'^(.*?)\s*(?:\(|\s-\s).*$').firstMatch(cleaned);
    if (truncationMatch != null &&
        truncationMatch.group(1)?.isNotEmpty == true) {
      cleaned = truncationMatch.group(1)!;
    } else {
      // Fallback: remove trailing IMDb/Reference view suffixes if no parentheses found.
      cleaned =
          cleaned.replaceAll(RegExp(r'\s*-\s*(IMDb|Reference view)\s*$'), '');
    }

    // Remove only the specific suffix patterns that include a parenthesis ending in a year
    // Examples handled:
    //   "Movie Title (1994)"                  -> "Movie Title"
    //   "Series Name (TV Series 2008–2013)"  -> "Series Name"
    cleaned = cleaned.replaceAll(
        RegExp(r'\s*\((?:[^()]*?)\d{4}(?:[–-]\d{4})?\)\s*$'), '');

    return cleaned.trim();
  }

  // Process and display links
  static Widget processAndDisplayLinks(List<String> links) {
    if (links.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: links
          .map((link) => LinkDisplayWidget(
                linkText: link,
                showIcon: true,
                showTitle: true,
              ))
          .toList(),
    );
  }

  /// Checks if a URL leads to a valid page by attempting to fetch its title.
  /// Returns true if the URL is valid and leads to a page, false otherwise.
  static Future<bool> isUrlValid(String url) async {
    try {
      final processedLink = await processLinkForDisplay('<a href="$url"></a>');
      return processedLink.title != null;
    } catch (e) {
      print('Error validating URL: $e');
      return false;
    }
  }

  /// Validates a URL and returns a ProcessedLink if valid, or throws an exception if invalid.
  /// This is used when you need both validation and the processed link data.
  static Future<ProcessedLink> validateAndProcessLink(String url,
      {String? linkText}) async {
    print('LinkProcessor: validateAndProcessLink called for URL: $url');
    print('LinkProcessor: linkText: "$linkText"');

    String? description;

    // Determine if we should fetch webpage content
    final shouldFetchContent = _shouldFetchWebpageContent(url, linkText);

    if (shouldFetchContent) {
      if (linkText == null || linkText.isEmpty) {
        print(
            'LinkProcessor: No linkText provided, fetching title and description from webpage...');
      } else {
        print(
            'LinkProcessor: linkText provided ("$linkText"), fetching description from webpage for validation...');
      }

      final webpageContentStartTime = DateTime.now();
      print(
          '🕐 LinkProcessor: Starting fetchWebpageContent for $url at ${webpageContentStartTime.toIso8601String()}');

      final content = await fetchWebpageContent(url);

      final webpageContentEndTime = DateTime.now();
      final webpageContentDuration =
          webpageContentEndTime.difference(webpageContentStartTime);
      print(
          '🕐 LinkProcessor: fetchWebpageContent completed in ${webpageContentDuration.inMilliseconds}ms');
      if (content != null) {
        // If no linkText was provided, use the fetched title
        if (linkText == null || linkText.isEmpty) {
          linkText = content.title;
        }
        // Always use the fetched description
        description = content.description;
        print(
            'LinkProcessor: Fetched title: "${content.title}", description: "${description?.substring(0, description.length > 100 ? 100 : description.length)}..."');
      }
    }

    // Create HTML link
    final htmlLink = (linkText == null || linkText.isEmpty)
        ? '<a href="$url"></a>'
        : '<a href="$url">$linkText</a>';

    final processedLink = await processLinkForDisplay(htmlLink);

    print('LinkProcessor: processedLink.title: "${processedLink.title}"');

    // If we couldn't fetch the title but the URL is valid, still return the processed link
    // The caller can decide how to handle missing titles
    if (processedLink.title == null) {
      print('LinkProcessor: No title found, creating fallback title');
      // Try to extract a reasonable title from the URL itself
      final uri = Uri.parse(url);
      final domain = uri.host;
      final path = uri.path;

      String fallbackTitle = domain;
      if (path.isNotEmpty && path != '/') {
        // Extract the last part of the path as a title
        final pathParts =
            path.split('/').where((part) => part.isNotEmpty).toList();
        if (pathParts.isNotEmpty) {
          final lastPart = pathParts.last;

          // Special handling for JustWatch URLs
          if (domain.contains('justwatch.com')) {
            // Extract movie/show name from JustWatch URL path
            if (pathParts.length >= 2 &&
                pathParts[pathParts.length - 2] == 'movie') {
              final movieSlug = lastPart;
              // Convert slug to title (replace dashes with spaces, title case)
              fallbackTitle =
                  movieSlug.replaceAll('-', ' ').split(' ').map((word) {
                if (word.isEmpty) return word;
                return word[0].toUpperCase() + word.substring(1).toLowerCase();
              }).join(' ');
            } else if (pathParts.length >= 2 &&
                pathParts[pathParts.length - 2] == 'tv-show') {
              final showSlug = lastPart;
              // Convert slug to title (replace dashes with spaces, title case)
              fallbackTitle =
                  showSlug.replaceAll('-', ' ').split(' ').map((word) {
                if (word.isEmpty) return word;
                return word[0].toUpperCase() + word.substring(1).toLowerCase();
              }).join(' ');
            } else {
              fallbackTitle = 'JustWatch Content';
            }
          }
          // Special handling for The Atlantic URLs
          else if (domain.contains('theatlantic.com')) {
            // For The Atlantic, use a generic but descriptive title since URL paths don't reflect actual article titles
            fallbackTitle = 'The Atlantic Article';
          }

          // If we didn't get a good title from the special handling, use the regular logic
          if (fallbackTitle == domain) {
            // Clean up the path part (remove file extensions, replace dashes/underscores with spaces)
            fallbackTitle = lastPart
                .replaceAll(RegExp(r'\.(html|htm|php|asp|aspx)$'), '')
                .replaceAll(RegExp(r'[-_]'), ' ')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();

            // Properly capitalize the title (title case)
            if (fallbackTitle.isNotEmpty) {
              fallbackTitle = fallbackTitle.split(' ').map((word) {
                if (word.isEmpty) return word;
                return word[0].toUpperCase() + word.substring(1).toLowerCase();
              }).join(' ');
            }

            // If the cleaned title is too short, use the domain
            if (fallbackTitle.length < 3) {
              fallbackTitle = domain;
            }
          }
        }
      }

      print('LinkProcessor: Using fallback title: "$fallbackTitle"');
      return ProcessedLink(
        url: url,
        title: fallbackTitle,
        favicon: processedLink.favicon,
        type: processedLink.type,
        domain: processedLink.domain,
        originalLink: '<a href="$url">$fallbackTitle</a>',
        description: description, // Include the fetched description
      );
    }

    print(
        'LinkProcessor: Returning processed link with title: "${processedLink.title}"');

    // If we fetched a description, include it in the returned ProcessedLink
    if (description != null) {
      return ProcessedLink(
        url: processedLink.url,
        title: processedLink.title,
        favicon: processedLink.favicon,
        type: processedLink.type,
        domain: processedLink.domain,
        originalLink: processedLink.originalLink,
        description: description, // Include the fetched description
      );
    }

    return processedLink;
  }

  /// Determines whether webpage content should be fetched for a given URL.
  ///
  /// Always fetches for sites with a specific [SiteTable] entry.  For the
  /// generic fallback (empty domain), only fetches when no descriptive
  /// [linkText] is available.
  static bool _shouldFetchWebpageContent(String url, String? linkText) {
    // Always fetch for specifically registered sites.
    final rule = _ruleProvider.matchRuleForUrl(url);
    final isGenericDefault =
        rule.id == 'generic-default' || rule.domainPatterns.contains('');
    if (!isGenericDefault) return true;

    // For generic/unregistered sites, fetch only if we need a title
    return linkText == null || linkText.isEmpty || linkText == url;
  }
}

class LinkDisplayWidget extends StatelessWidget {
  final String linkText;
  final bool showIcon;
  final bool showTitle;
  final VoidCallback? onTap;
  final bool isEditing;

  const LinkDisplayWidget({
    super.key,
    required this.linkText,
    this.showIcon = true,
    this.showTitle = true,
    this.onTap,
    this.isEditing = false,
  });

  Widget _buildFavicon(String? faviconUrl) {
    if (faviconUrl == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Image.network(
        faviconUrl,
        width: 32,
        height: 32,
        errorBuilder: (context, error, stackTrace) {
          // Return a generic link icon on error
          return const Icon(
            Icons.link,
            size: 32,
            color: Colors.grey,
          );
        },
        // Add a loading placeholder
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
            ),
          );
        },
        // Add a timeout for loading
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: frame != null ? child : const SizedBox.shrink(),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProcessedLink>(
      future: LinkProcessor.processLinkForDisplay(linkText),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 32,
            width: 32,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }

        if (snapshot.hasError) {
          print('Error processing link: ${snapshot.error}');
          // Show a simple link with error styling
          return Row(
            children: [
              const Icon(
                Icons.link,
                size: 32,
                color: Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  linkText,
                  style: const TextStyle(
                    color: Colors.red,
                    decoration: TextDecoration.underline,
                    fontSize: 16, // Increased by 4 from default
                  ),
                ),
              ),
            ],
          );
        }

        final processedLink = snapshot.data;
        if (processedLink == null) {
          return Row(
            children: [
              const Icon(
                Icons.link,
                size: 32,
                color: Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  linkText,
                  style: const TextStyle(
                    color: Colors.red,
                    decoration: TextDecoration.underline,
                    fontSize: 16, // Increased by 4 from default
                  ),
                ),
              ),
            ],
          );
        }

        if (isEditing) {
          return Row(
            children: [
              if (showIcon) _buildFavicon(processedLink.favicon),
              Expanded(
                child: Text(
                  processedLink.displayTitle,
                  style: const TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                    fontSize: 16, // Increased by 4 from default
                  ),
                ),
              ),
            ],
          );
        }

        return InkWell(
          onTap: onTap ??
              () {
                _handleLinkClick(context, processedLink);
              },
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                if (showIcon) _buildFavicon(processedLink.favicon),
                if (showTitle)
                  Expanded(
                    child: Text(
                      processedLink.displayTitle,
                      style: const TextStyle(
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                        fontSize: 16, // Increased by 4 from default
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Handle link clicks with special handling for internal/localhost links
  Future<void> _handleLinkClick(
      BuildContext context, ProcessedLink link) async {
    final url = link.url; // Use the original URL, not displayUrl

    // Check if this is an internal link (meaning-to.me in debug mode)
    if (kDebugMode && url.contains('meaning-to.me')) {
      // Parse the URL to extract the path for internal navigation
      try {
        final uri = Uri.parse(url);
        if (uri.pathSegments.isNotEmpty && uri.pathSegments[0] == 'category') {
          // This is a category link - we should navigate within the app
          print(
              'LinkDisplayWidget: Internal category navigation to: ${uri.path}');
          print('LinkDisplayWidget: Category ID: ${uri.pathSegments[1]}');

          // Navigate to the Home screen for this category
          Navigator.pushReplacementNamed(
            context,
            '/category',
            arguments: {'categoryId': uri.pathSegments[1]},
          );

          return;
        }
      } catch (e) {
        print('LinkDisplayWidget: Error parsing internal URL: $e');
      }

      // If it's not a category link or parsing failed, fall back to external launch
      print('LinkDisplayWidget: Falling back to external launch for: $url');
    }

    // For external links or fallback, use Android-optimized external application mode
    try {
      bool launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
        webViewConfiguration: const WebViewConfiguration(
          enableJavaScript: false,
          enableDomStorage: false,
        ),
      );
      if (!launched) {
        // Fallback to platform default
        await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      print('LinkDisplayWidget: Failed to launch URL: $url, error: $e');
    }
  }
}
