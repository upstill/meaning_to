import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:meaning_to/utils/link_processor.dart';

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

  /// Builds a widget to display a processed link with its icon and title.
  /// This is used by ProcessedLink to create its display widget.
  static Widget buildLinkWidget(ProcessedLink link, BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 4.0),
      child: InkWell(
        onTap: () {
          _handleLinkClick(link, context); // Pass context for navigation
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

  /// Handle link clicks with special handling for internal/localhost links
  static void _handleLinkClick(ProcessedLink link, BuildContext context) {
    final url = link.url; // Use the original URL, not displayUrl

    // Check if this is an internal link (meaning-to.me in debug mode)
    if (kDebugMode && url.contains('meaning-to.me')) {
      // Parse the URL to extract the path for internal navigation
      try {
        final uri = Uri.parse(url);
        if (uri.pathSegments.isNotEmpty && uri.pathSegments[0] == 'category') {
          // This is a category link - we should navigate within the app
          print('LinkDisplay: Internal category navigation to: ${uri.path}');
          print('LinkDisplay: Category ID: ${uri.pathSegments[1]}');

          // Navigate to the Home screen for this category
          Navigator.pushReplacementNamed(
            context,
            '/category',
            arguments: {'categoryId': uri.pathSegments[1]},
          );

          return; // Don't launch externally
        }
      } catch (e) {
        print('LinkDisplay: Error parsing internal URL: $e');
      }

      // Fall back to external launch if not a category link
      print('LinkDisplay: Falling back to external launch for: $url');
    }

    // For external links or fallback, use the standard external application mode
    launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
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
                _handleLinkClick(processedLink, context);
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
