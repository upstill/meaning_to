import 'package:flutter/foundation.dart';

/// Utility class for generating deep links to categories
class DeepLinkGenerator {
  /// Base URL for web deep links
  static const String _webBaseUrl = 'https://your-domain.com';

  /// Custom scheme for mobile deep links
  static const String _customScheme = 'meaningto';

  /// Generate a deep link to a specific category
  ///
  /// [categoryId] - The ID of the category to link to
  /// [platform] - The platform to generate the link for (web, mobile, or auto)
  static String generateCategoryLink(int categoryId, {String? platform}) {
    final targetPlatform = platform ?? _getCurrentPlatform();

    switch (targetPlatform) {
      case 'web':
        return '$_webBaseUrl/category/$categoryId';
      case 'mobile':
        return '$_customScheme://category/$categoryId';
      case 'auto':
      default:
        // Return web link for auto detection
        return '$_webBaseUrl/category/$categoryId';
    }
  }

  /// Generate a shareable link that works across platforms
  static String generateShareableCategoryLink(int categoryId) {
    return '$_webBaseUrl/category/$categoryId';
  }

  /// Generate a link with query parameters for web
  static String generateWebCategoryLink(int categoryId) {
    return '$_webBaseUrl/?category=$categoryId';
  }

  /// Get the current platform
  static String _getCurrentPlatform() {
    if (kIsWeb) {
      return 'web';
    } else if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return 'mobile';
    } else {
      return 'auto';
    }
  }

  /// Check if a URL is a valid category deep link
  static bool isValidCategoryLink(String url) {
    try {
      final uri = Uri.parse(url);

      // Check for web links
      if (uri.scheme == 'https' && uri.host == 'your-domain.com') {
        return uri.path.startsWith('/category/') ||
            uri.queryParameters.containsKey('category');
      }

      // Check for custom scheme links
      if (uri.scheme == _customScheme && uri.host == 'category') {
        return uri.pathSegments.isNotEmpty;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Extract category ID from a deep link URL
  static int? extractCategoryId(String url) {
    try {
      final uri = Uri.parse(url);

      // Handle web links
      if (uri.scheme == 'https' && uri.host == 'your-domain.com') {
        if (uri.path.startsWith('/category/')) {
          final pathSegments = uri.pathSegments;
          if (pathSegments.length >= 2 && pathSegments[0] == 'category') {
            return int.tryParse(pathSegments[1]);
          }
        } else if (uri.queryParameters.containsKey('category')) {
          return int.tryParse(uri.queryParameters['category']!);
        }
      }

      // Handle custom scheme links
      if (uri.scheme == _customScheme && uri.host == 'category') {
        if (uri.pathSegments.isNotEmpty) {
          return int.tryParse(uri.pathSegments[0]);
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }
}
