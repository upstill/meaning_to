import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:meaning_to/utils/link_processor.dart';

/// A class representing a link extracted from text.
class ExtractedLink {
  final String url;
  final String title;
  final String html;  // The HTML <a> tag representation

  ExtractedLink({
    required this.url,
    required this.title,
    required this.html,
  });
}

/// A utility class for extracting links from various text formats.
class LinkExtractor {
  /// Extracts a link from a string, which can be either a URL or an HTML <a> tag.
  /// Returns null if no valid link can be extracted.
  static Future<ExtractedLink?> extractLinkFromString(String text) async {
    String? url;
    String? title;

    // Try parsing as HTML <a> tag
    if (text.trim().startsWith('<a') && text.trim().endsWith('</a>')) {
      final document = html_parser.parse(text);
      final linkElement = document.querySelector('a');
      if (linkElement != null) {
        url = linkElement.attributes['href'];
        title = linkElement.text;
      }
    } else {
      // Try parsing as URL
      if (Uri.tryParse(text)?.hasAbsolutePath == true) {
        url = text;
      }
    }

    if (url == null) {
      return null;
    }

    // If we don't have a title, try to get it
    if (title == null || title.isEmpty) {
      // Special handling for JustWatch URLs
      if (url.contains('justwatch.com')) {
        title = await _getJustWatchTitle(url);
      }
      
      // If we still don't have a title, try the general link processor
      if (title == null || title.isEmpty) {
        try {
          final processedLink = await LinkProcessor.processLinkForDisplay('<a href="$url"></a>');
          title = processedLink.title;
        } catch (e) {
          print('Error fetching webpage title: $e');
          // Fall back to using the URL as title
          title = url;
        }
      }
    }

    // Create the HTML <a> tag
    final html = '<a href="$url">${title ?? url}</a>';

    return ExtractedLink(
      url: url,
      title: title ?? url,
      html: html,
    );
  }

  /// Parses a list of HTML <a> tags from JSON into ExtractedLink objects.
  /// Returns an empty list if the input is null or invalid.
  static Future<List<ExtractedLink>> parseLinksFromJson(List<dynamic>? jsonLinks) async {
    if (jsonLinks == null) return [];

    final links = <ExtractedLink>[];
    
    for (final linkHtml in jsonLinks) {
      if (linkHtml is! String) continue;
      
      try {
        final extractedLink = await extractLinkFromString(linkHtml);
        if (extractedLink != null) {
          links.add(extractedLink);
        }
      } catch (e) {
        print('Error parsing link from JSON: $e');
        continue;
      }
    }

    return links;
  }

  /// Gets the title from a JustWatch page by looking for the h1 element.
  static Future<String?> _getJustWatchTitle(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        print('Error fetching JustWatch page: ${response.statusCode}');
        return null;
      }

      final document = html_parser.parse(response.body);
      final titleElement = document.querySelector('h1.title-detail-hero__details__title');
      if (titleElement != null) {
        // Get only the direct text nodes, ignoring text from child elements
        final directText = titleElement.nodes
            .where((node) => node.nodeType == 3)  // 3 is the value for TEXT_NODE
            .map((node) => node.text?.trim())
            .where((text) => text != null && text.isNotEmpty)
            .join(' ')
            .trim();
        
        return directText.isEmpty ? null : directText;
      }
      return null;
    } catch (e) {
      print('Error fetching JustWatch title: $e');
      return null;
    }
  }
} 