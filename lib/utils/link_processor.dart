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

  ProcessedLink({
    required this.url,
    this.title,
    this.favicon,
    required this.type,
    required this.domain,
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
        ...links.map((link) => link.buildLinkWidget()).toList(),
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

  static Future<ProcessedLink> processLink(String linkText) async {
    // Parse HTML if present
    final (url, title) = parseHtmlLink(linkText);
    
    if (!isValidUrl(url)) {
      return ProcessedLink(
        url: url,
        type: LinkType.other,
        domain: '',
      );
    }

    final type = determineLinkType(url);
    final domain = extractDomain(url);
    
    // If no title is provided, try to fetch it from the webpage
    String? displayTitle = title;
    if (displayTitle == null || displayTitle.isEmpty) {
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          final document = html_parser.parse(response.body);
          
          // Try to get title from various meta tags in order of preference
          displayTitle = document.querySelector('meta[property="og:title"]')?.attributes['content'] ??
                        document.querySelector('meta[name="twitter:title"]')?.attributes['content'] ??
                        document.querySelector('title')?.text ??
                        url; // Fallback to URL if no title found
        }
      } catch (e) {
        print('Error fetching webpage title for $url: $e');
        displayTitle = url; // Fallback to URL on error
      }
    }
    
    // Get icon for domain with error handling
    String? favicon;
    try {
      final domainIcon = await DomainIcon.getIconForDomain(domain);
      if (domainIcon != null) {
        // Validate the icon URL before using it
        final isValid = await DomainIcon.validateIconUrl(domainIcon.iconUrl);
        if (isValid) {
          favicon = domainIcon.iconUrl;
        } else {
          print('Invalid icon URL for domain $domain: ${domainIcon.iconUrl}');
        }
      }
    } catch (e) {
      print('Error processing icon for domain $domain: $e');
    }

    return ProcessedLink(
      url: url,
      title: displayTitle,
      favicon: favicon,
      type: type,
      domain: domain,
    );
  }

  static Future<List<ProcessedLink>> processLinks(List<String> links) async {
    final results = <ProcessedLink>[];
    for (final link in links) {
      results.add(await processLink(link));
    }
    return results;
  }

  // Process and display links
  static Widget processAndDisplayLinks(List<String> links) {
    return FutureBuilder<List<ProcessedLink>>(
      future: processLinks(links),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 4.0),
            child: SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        if (snapshot.hasError) {
          print('Error processing links: ${snapshot.error}');
          return const SizedBox.shrink();
        }

        final processedLinks = snapshot.data;
        if (processedLinks == null || processedLinks.isEmpty) {
          return const SizedBox.shrink();
        }

        return ProcessedLink.buildLinksList(processedLinks);
      },
    );
  }
} 