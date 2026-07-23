import 'package:flutter/foundation.dart';

/// Utility class for generating deep links to categories
class DeepLinkGenerator {
  /// Base URL for web deep links. rouzme.com is the canonical domain;
  /// meaning-to.me remains a permanent alias so older links keep working.
  static const String _webBaseUrl = 'https://rouzme.com';

  /// Custom scheme for mobile deep links
  static const String _customScheme = 'meaningto';

  /// Debug port for local development - override with --dart-define=DEBUG_PORT=xxxx
  static int _debugPort =
      const int.fromEnvironment('DEBUG_PORT', defaultValue: 8080);

  /// Set the debug port for local development
  static void setDebugPort(int port) {
    _debugPort = port;
    print('DeepLinkGenerator: Debug port set to $_debugPort');
  }

  /// Get the current debug port
  static int get debugPort => _debugPort;

  /// Convenience method to set debug port with a string (e.g., "8082")
  static void setDebugPortFromString(String portString) {
    final port = int.tryParse(portString);
    if (port != null && port > 0 && port < 65536) {
      setDebugPort(port);
    } else {
      print('DeepLinkGenerator: Invalid port number: $portString');
    }
  }

  /// Generate a deep link to a category
  static String generateCategoryLink(int categoryId) {
    if (kIsWeb) {
      return '$_webBaseUrl/category/$categoryId';
    } else {
      return '$_customScheme://category/$categoryId';
    }
  }

  /// Generate a share-invitation link for the given token UUID.
  /// On web, mirrors the current host so localhost links work in dev.
  /// On native, falls back to kDebugMode → localhost, else production.
  static String generateInviteLink(String token) {
    return '${_joinBase()}/join?invite=$token';
  }

  /// Generate a reusable share link for the given share-link id.
  /// Uses the same host resolution as [generateInviteLink].
  static String generateShareLink(String linkId) {
    return '${_joinBase()}/join?share=$linkId';
  }

  /// Resolves the base URL for /join links. On web, mirrors the current host so
  /// localhost links work in dev; on native, falls back to debug localhost or
  /// production.
  static String _joinBase() {
    if (kIsWeb) {
      final host = Uri.base.host;
      final isLocal = host == 'localhost' || host == '127.0.0.1';
      return isLocal ? 'http://${Uri.base.authority}' : _webBaseUrl;
    }
    return kDebugMode ? 'http://localhost:$_debugPort' : _webBaseUrl;
  }

  /// Convert a production URL to a debug URL for local development
  static String convertToDebugUrl(String url) {
    if (!isDebugMode) return url;

    // Replace either production host with localhost and the configured debug port
    final debugUrl = url
        .replaceAll('rouzme.com', 'localhost:$_debugPort')
        .replaceAll('meaning-to.me', 'localhost:$_debugPort');
    print('DeepLinkGenerator: Converting $url to debug URL: $debugUrl');
    return debugUrl;
  }

  /// Check if we're in debug mode
  static bool get isDebugMode => kDebugMode;

  /// Get debug information for troubleshooting
  static Map<String, dynamic> get debugInfo => {
        'isDebugMode': isDebugMode,
        'isWeb': kIsWeb,
        'debugPort': _debugPort,
        'webBaseUrl': _webBaseUrl,
      };
}
