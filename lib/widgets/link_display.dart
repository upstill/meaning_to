import 'package:flutter/material.dart';
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

        Widget _buildFavicon(String? favicon) {
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
              if (showIcon) _buildFavicon(processedLink.favicon),
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
    final validLinks = links.where((link) => link != null && link.isNotEmpty).map((link) => link.toString()).toList();
    if (validLinks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: validLinks.map((link) => Padding(
        padding: const EdgeInsets.only(bottom: 4.0),
        child: LinkDisplay(
          key: ValueKey('link_$link'),
          linkText: link,
          showIcon: showIcon,
          showTitle: showTitle,
        ),
      )).toList(),
    );
  }
} 