import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'dart:html' as html;

/// A widget that displays a link with an optional icon and title.
/// Used in both the home screen and import screen for consistent link display.
class LinkDisplay extends StatelessWidget {
  final String linkText;
  final bool showIcon;
  final bool showTitle;
  final VoidCallback? onTap;
  final bool isEditing;

  const LinkDisplay({
    super.key,
    required this.linkText,
    this.showIcon = true,
    this.showTitle = true,
    this.onTap,
    this.isEditing = false,
  });

  /// Checks if a URL is an internal link to the app
  static bool _isInternalLink(String url) {
    try {
      final uri = Uri.parse(url);
      final domain = uri.host.toLowerCase();
      return (domain == 'localhost' || domain == 'meaning-to.me') &&
          uri.path.startsWith('/category/');
    } catch (e) {
      return false;
    }
  }

  /// Handles link clicks with appropriate behavior for internal vs external links
  static void _handleLinkClick(String url) {
    if (_isInternalLink(url)) {
      // For internal links in web app, use app navigation
      if (kIsWeb) {
        // Extract category ID from URL path like /category/123
        try {
          final uri = Uri.parse(url);
          final pathSegments = uri.pathSegments;

          if (pathSegments.length >= 2 && pathSegments[0] == 'category') {
            final categoryId = pathSegments[1];

            // Use the browser's history API to change the URL
            // Only push the path, not the full URL to avoid protocol/port mismatch
            html.window.history.pushState({}, '', uri.path);

            // Dispatch a popstate event to trigger the app's routing system
            html.window.dispatchEvent(html.Event('popstate'));
          }
        } catch (e) {
          print('Error handling internal link navigation: $e');
        }
      } else {
        // For mobile apps, use inAppWebView
        launchUrl(
          Uri.parse(url),
          mode: LaunchMode.inAppWebView,
        );
      }
    } else {
      // For external links, open in new tab
      launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  /// Builds a widget to display a processed link with its icon and title.
  /// This is used by ProcessedLink to create its display widget.
  static Widget buildLinkWidget(ProcessedLink link) {
    return Container(
      padding: const EdgeInsets.only(top: 4.0),
      child: InkWell(
        onTap: () {
          _handleLinkClick(link.url);
        },
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            children: [
              if (link.favicon != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Image.network(
                    link.favicon!,
                    width: 32,
                    height: 32,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
              Expanded(
                child: Text(
                  link.displayTitle,
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProcessedLink>(
      future: LinkProcessor.processLinkForDisplay(linkText),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          print('Error processing link: ${snapshot.error}');
          return const Text('Error loading link');
        }

        if (!snapshot.hasData) {
          return const SizedBox(
            height: 32,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final processedLink = snapshot.data!;

        Widget buildFavicon(String? favicon) {
          if (favicon == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Image.network(
              favicon,
              width: 32,
              height: 32,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          );
        }

        if (isEditing) {
          return Row(
            children: [
              if (showIcon) buildFavicon(processedLink.favicon),
              Expanded(
                child: Text(
                  processedLink.displayTitle,
                  style: const TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          );
        }

        return InkWell(
          onTap: onTap ??
              () {
                _handleLinkClick(processedLink.url);
              },
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                if (showIcon) buildFavicon(processedLink.favicon),
                if (showTitle)
                  Expanded(
                    child: Text(
                      processedLink.displayTitle,
                      style: const TextStyle(
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                        fontSize: 16,
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

/// A widget that displays a list of links.
class LinkListDisplay extends StatelessWidget {
  final List<String> links;
  final bool showIcon;
  final bool showTitle;

  const LinkListDisplay({
    super.key,
    required this.links,
    this.showIcon = true,
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) {
      return const SizedBox.shrink();
    }

    // Filter out null links and ensure all links are strings
    final validLinks = links
        .where((link) => link.isNotEmpty)
        .map((link) => link.toString())
        .toList();
    if (validLinks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: validLinks
          .map((link) => Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: LinkDisplay(
                  key: ValueKey('link_$link'),
                  linkText: link,
                  showIcon: showIcon,
                  showTitle: showTitle,
                ),
              ))
          .toList(),
    );
  }
}
