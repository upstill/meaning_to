import 'package:uri/uri.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:meaning_to/models/icon.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ProcessedLink {
  final String url;
  final String? title;
  final String? favicon;
  final LinkType type;
  final String domain;
  final String originalLink;  // Store the original/modified link text

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
    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: InkWell(
        onTap: () {
          launchUrl(
            Uri.parse(url),
            mode: LaunchMode.externalApplication,
          );
        },
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            children: [
              if (favicon != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Image.network(
                    favicon!,
                    width: 32,
                    height: 32,
                    errorBuilder: (context, error, stackTrace) => 
                      const SizedBox.shrink(),
                  ),
                ),
              Expanded(
                child: Text(
                  displayTitle,
                  style: const TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
        ...links.map((link) => LinkDisplayWidget(
          linkText: link.originalLink,
          showIcon: true,
          showTitle: true,
        )).toList(),
      ],
    );
  }
}

enum LinkType {
  webpage,
  youtube,
  github,
  twitter,
  other
}

class LinkProcessor {
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
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;

      final document = html_parser.parse(response.body);
      final title = document.querySelector('title')?.text;
      return title?.trim();
    } catch (e) {
      print('Error fetching webpage title: $e');
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
      originalLink: finalLink,  // Use the final HTML link with the title
    );
  }

  static Future<List<ProcessedLink>> processLinksForDisplay(List<String> links) async {
    final results = <ProcessedLink>[];
    
    for (final link in links) {
      final processed = await processLinkForDisplay(link);
      results.add(processed);
    }
    
    return results;
  }

  // Process and display links
  static Widget processAndDisplayLinks(List<String> links) {
    if (links.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: links.map((link) => LinkDisplayWidget(
        linkText: link,
        showIcon: true,
        showTitle: true,
      )).toList(),
    );
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
                    fontSize: 16,  // Increased by 4 from default
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
                    fontSize: 16,  // Increased by 4 from default
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
                    fontSize: 16,  // Increased by 4 from default
                  ),
                ),
              ),
            ],
          );
        }

        return InkWell(
          onTap: onTap ?? () {
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
                        fontSize: 16,  // Increased by 4 from default
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