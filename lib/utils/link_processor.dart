import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:meaning_to/models/icon.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:meaning_to/widgets/link_display.dart';
import 'dart:convert';

class ProcessedLink {
  final String url;
  final String? title;
  final String? favicon;
  final LinkType type;
  final String domain;
  final String originalLink; // Store the original/modified link text

  ProcessedLink({
    required this.url,
    this.title,
    this.favicon,
    required this.type,
    required this.domain,
    required this.originalLink,
  });

  String get displayTitle => title ?? url;

  // Widget to display the link with its icon
  Widget buildLinkWidget() {
    return LinkDisplay.buildLinkWidget(this);
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

      return _processHtml(url, response.body);
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

      return _processHtml(url, response.body);
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
      return uri.host.toLowerCase();
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

  static Future<String?> fetchWebpageTitle(String url) async {
    try {
      print('LinkProcessor: Fetching title for URL: $url');

      // Try with more comprehensive headers first
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.5',
          'Accept-Encoding': 'gzip, deflate, br',
          'DNT': '1',
          'Connection': 'keep-alive',
          'Upgrade-Insecure-Requests': '1',
        },
      );
      if (response.statusCode != 200) {
        print(
            'LinkProcessor: HTTP status code ${response.statusCode} for URL: $url');
        return null;
      }

      final document = html_parser.parse(response.body);

      // First priority: <title> tag
      var title = document.querySelector('title')?.text?.trim();
      if (title != null && title.isNotEmpty) {
        print('LinkProcessor: Found title from <title> tag: "$title"');
        return title;
      }

      // Second priority: Open Graph title
      title = document
          .querySelector('meta[property="og:title"]')
          ?.attributes['content']
          ?.trim();
      if (title != null && title.isNotEmpty) {
        print('LinkProcessor: Found title from og:title: "$title"');
        return title;
      }

      // Third priority: Twitter Card title
      title = document
          .querySelector('meta[name="twitter:title"]')
          ?.attributes['content']
          ?.trim();
      if (title != null && title.isNotEmpty) {
        print('LinkProcessor: Found title from twitter:title: "$title"');
        return title;
      }

      // Fourth priority: First h1 tag
      title = document.querySelector('h1')?.text?.trim();
      if (title != null && title.isNotEmpty) {
        print('LinkProcessor: Found title from h1: "$title"');
        return title;
      }

      // Fifth priority: First h2 tag
      title = document.querySelector('h2')?.text?.trim();
      if (title != null && title.isNotEmpty) {
        print('LinkProcessor: Found title from h2: "$title"');
        return title;
      }

      print('LinkProcessor: No title found for URL: $url');
      return null;
    } catch (e) {
      print('Error fetching webpage title: $e');

      // For JustWatch URLs, try using Browserless as a fallback
      if (url.contains('justwatch.com')) {
        print('LinkProcessor: Trying Browserless for JustWatch URL: $url');
        try {
          final domain = extractDomain(url);
          final links = await fetchLinksFromBrowserless(url, domain);
          if (links.isNotEmpty) {
            final title = links.first.title;
            if (title != null && title.isNotEmpty) {
              print('LinkProcessor: Found title via Browserless: "$title"');
              return title;
            }
          }
        } catch (browserlessError) {
          print(
              'LinkProcessor: Browserless fallback also failed: $browserlessError');
        }
      }

      return null;
    }
  }

  static Future<ProcessedLink> processLinkForDisplay(String linkText) async {
    // Parse the HTML link to get URL and title
    final (url, title) = parseHtmlLink(linkText);

    if (!isValidUrl(url)) {
      return ProcessedLink(
        url: url,
        type: LinkType.other,
        domain: '',
        originalLink: linkText,
      );
    }

    final type = determineLinkType(url);
    final domain = extractDomain(url);

    // Get icon for domain with error handling
    String? favicon;
    try {
      final domainIcon = await DomainIcon.getIconForDomain(domain);
      if (domainIcon != null) {
        favicon = domainIcon.iconUrl;
      }
    } catch (e) {
      print('Error processing icon for domain $domain: $e');
    }

    // If title is empty, try to fetch it from the webpage
    String? finalTitle = title;
    if (finalTitle == null || finalTitle.isEmpty) {
      finalTitle = await fetchWebpageTitle(url);
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
    );
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

    final processedLink =
        await processLinkForDisplay('<a href="$url">${linkText ?? ""}</a>');

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

      print('LinkProcessor: Using fallback title: "$fallbackTitle"');
      return ProcessedLink(
        url: url,
        title: fallbackTitle,
        favicon: processedLink.favicon,
        type: processedLink.type,
        domain: processedLink.domain,
        originalLink: '<a href="$url">$fallbackTitle</a>',
      );
    }

    print(
        'LinkProcessor: Returning processed link with title: "${processedLink.title}"');
    return processedLink;
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
                launchUrl(
                  Uri.parse(processedLink.url),
                  mode: LaunchMode.externalApplication,
                );
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
}
