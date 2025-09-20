import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/utils/hijack_detector.dart';

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

  /// Resolve boxd.it URLs and launch external browser
  static Future<void> _resolveLinkAndLaunch(String url) async {
    try {
      // Special handling for letterboxd URLs - warn user about potential hijacking
      if (url.contains('letterboxd.com') || url.contains('boxd.it')) {
        print('LinkDisplay: Detected letterboxd URL - may be hijacked by Letterboxd app');
        // For now, just launch normally but with awareness of the issue
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
      } else {
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      print('LinkDisplay: Error launching URL: $e');
    }
  }

  /// Launch URL using configured WebView if hijacking occurs
  static Future<void> _launchWithDirectIntent(String url) async {
    try {
      // Since we can't prevent hijacking, configure it properly
      bool launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
        webViewConfiguration: const WebViewConfiguration(
          enableJavaScript: true,
          enableDomStorage: true,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Android; Mobile) Flutter App',
          },
        ),
        browserConfiguration: const BrowserConfiguration(
          showTitle: true,
        ),
      );

      if (!launched) {
        print('LinkDisplay: Launch failed, trying platform default');
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.platformDefault,
        );
      }
    } catch (e) {
      print('LinkDisplay: Launch failed: $e');
      await _copyToClipboardAndNotify(url);
    }
  }

  /// Copy URL to clipboard as fallback
  static Future<void> _copyToClipboardAndNotify(String url) async {
    // Note: You'll need to add clipboard dependency to use this
    // For now, just print the URL
    print('LinkDisplay: URL copied to clipboard: $url');
    // TODO: Implement actual clipboard copy and user notification
  }

  /// Centralized function to handle any URL with letterboxd protection
  /// This can be used by other widgets to ensure consistent handling
  static Future<void> handleUrl(String url, BuildContext context) async {
    // Only show letterboxd protection on Android - web doesn't have app hijacking issues
    if (!kIsWeb && Platform.isAndroid && (url.contains('letterboxd.com') || url.contains('boxd.it'))) {
      print('LinkDisplay: Intercepting letterboxd/boxd.it URL on Android: $url');
      await _resolveLinkAndLaunchWithMonitoring(url, context);
    } else {
      print('LinkDisplay: Normal URL handling (web or non-letterboxd): $url');
      await _resolveLinkAndLaunch(url);
    }
  }

  /// Launch letterboxd URL with hijack prevention
  static Future<void> _resolveLinkAndLaunchWithMonitoring(String url, BuildContext context) async {
    // Show user a choice dialog BEFORE launching
    bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Letterboxd Link Detected'),
          content: const Text(
            'This link may be hijacked by the Letterboxd app and trap you in an in-app browser. '
            'How would you like to open it?'
          ),
          actions: [
            TextButton(
              child: const Text('Copy URL'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Try to Open'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (result == true) {
      // User chose to try opening
      try {
        print('LinkDisplay: User chose to launch letterboxd URL: $url');
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalNonBrowserApplication,
        );
      } catch (e) {
        print('LinkDisplay: Error launching letterboxd URL: $e');
        await _copyToClipboardAndShowMessage(url, context);
      }
    } else if (result == false) {
      // User chose to copy
      await _copyToClipboardAndShowMessage(url, context);
    }
    // If null (dialog dismissed), do nothing
  }

  /// Copy URL to clipboard and show message
  static Future<void> _copyToClipboardAndShowMessage(String url, BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('URL copied to clipboard'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Dismiss',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      print('LinkDisplay: Error copying to clipboard: $e');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to copy URL: $e'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Dismiss',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    }
  }

  /// Handle link clicks with special handling for internal/localhost links
  static void _handleLinkClick(ProcessedLink link, BuildContext context) {
    final url = link.url; // Use the original URL, not displayUrl

    // Initialize hijack detector
    HijackDetector().initialize(context);

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

    // Special handling for letterboxd URLs - only on Android (web doesn't have app hijacking)
    if (!kIsWeb && Platform.isAndroid && (url.contains('letterboxd.com') || url.contains('boxd.it'))) {
      print('LinkDisplay: Detected letterboxd/boxd.it URL on Android: $url');
      _resolveLinkAndLaunchWithMonitoring(url, context);
    } else {
      print('LinkDisplay: Normal URL handling (web or non-letterboxd): $url');
      _resolveLinkAndLaunch(url);
    }
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
          onTap:
              onTap ??
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
          .map(
            (link) => Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: LinkDisplay(
                key: ValueKey('link_$link'),
                linkText: link,
                showIcon: showIcon,
                showTitle: showTitle,
              ),
            ),
          )
          .toList(),
    );
  }
}
