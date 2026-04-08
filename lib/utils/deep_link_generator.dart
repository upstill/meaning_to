import 'package:flutter/foundation.dart';

/// Utility class for generating deep links to categories
class DeepLinkGenerator {
  /// Base URL for web deep links - use meaning-to.me for production
  static const String _webBaseUrl = 'https://meaning-to.me';

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
    String base;
    if (kIsWeb) {
      final host = Uri.base.host;
      final isLocal = host == 'localhost' || host == '127.0.0.1';
      base = isLocal
          ? 'http://${Uri.base.authority}'
          : _webBaseUrl;
    } else {
      base = kDebugMode ? 'http://localhost:$_debugPort' : _webBaseUrl;
    }
    return '$base/join?invite=$token';
  }

  /// Convert a production URL to a debug URL for local development
  static String convertToDebugUrl(String url) {
    if (!isDebugMode) return url;

    // Replace meaning-to.me with localhost and the configured debug port
    final debugUrl = url.replaceAll('meaning-to.me', 'localhost:$_debugPort');
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
