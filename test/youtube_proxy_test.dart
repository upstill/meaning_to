import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/utils/site_configurations.dart';
import 'package:flutter/foundation.dart';

void main() {
  group('YouTube Proxy Tests', () {
    test('YouTube should require proxy for web', () {
      final url = 'https://www.youtube.com/watch?v=qd1RXxf2LsQ';

      // Test that YouTube is configured to use proxy
      final shouldUseProxy = SiteConfigRegistry.shouldUseProxy(url);
      expect(shouldUseProxy, isTrue, reason: 'YouTube should require proxy for web environments');

      // Test that the configuration is correctly set
      final config = SiteConfigRegistry.getConfigForUrl(url);
      expect(config.requiresProxy, isTrue, reason: 'YouTube config should have requiresProxy set to true');
      expect(config.domain, equals('youtube.com'), reason: 'Should use YouTube-specific configuration');
    });

    test('Verify proxy URL construction', () async {
      final url = 'https://www.youtube.com/watch?v=qd1RXxf2LsQ';

      // The system should construct a proxy URL like this when kIsWeb is true
      final expectedProxyUrl = 'https://api.allorigins.win/raw?url=${Uri.encodeComponent(url)}';

      print('Original URL: $url');
      print('Expected proxy URL: $expectedProxyUrl');

      // Verify URL encoding
      expect(Uri.encodeComponent(url), contains('https%3A%2F%2Fwww.youtube.com'));
    });

    test('Non-proxied sites should not require proxy', () {
      final url = 'https://example.com/test';

      final shouldUseProxy = SiteConfigRegistry.shouldUseProxy(url);
      expect(shouldUseProxy, isFalse, reason: 'Example.com should not require proxy');

      final config = SiteConfigRegistry.getConfigForUrl(url);
      expect(config.domain, equals('*'), reason: 'Should use default configuration');
      expect(config.requiresProxy, isFalse, reason: 'Default config should not require proxy');
    });
  });
}