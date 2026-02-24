import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/site_table.dart';

void main() {
  group('YouTube Proxy Tests', () {
    test('YouTube web fetch methods do not start with direct (proxy required)',
        () {
      final url = 'https://www.youtube.com/watch?v=qd1RXxf2LsQ';
      final entry = SiteTable.entryForUrl(url);
      final webMethods = entry.fetch[FetchContext.web] ?? [];

      expect(entry.domain, equals('youtube.com'),
          reason: 'Should use YouTube-specific configuration');
      expect(webMethods.contains(FetchMethod.direct), isFalse,
          reason:
              'YouTube should not use direct fetch on web (proxy or API required)');
      expect(
          webMethods.first == FetchMethod.youtubeApi ||
              webMethods.first == FetchMethod.corsproxy ||
              webMethods.first == FetchMethod.allorigins,
          isTrue,
          reason: 'YouTube web should prefer API or proxy over direct fetch');
    });

    test('Verify proxy URL construction', () {
      final url = 'https://www.youtube.com/watch?v=qd1RXxf2LsQ';
      final entry = SiteTable.entryForUrl(url);
      final webMethods = entry.fetch[FetchContext.web] ?? [];

      // At least one proxy method should be present
      final hasProxy = webMethods.any((m) =>
          m == FetchMethod.allorigins ||
          m == FetchMethod.corsproxy ||
          m == FetchMethod.corsanywhere);
      expect(hasProxy, isTrue,
          reason: 'YouTube should have at least one proxy method for web');

      // Verify URL encoding works correctly
      expect(Uri.encodeComponent(url), contains('https%3A%2F%2Fwww.youtube.com'));
    });

    test('Non-proxied sites use direct fetch first on web', () {
      final url = 'https://example.com/test';
      final entry = SiteTable.entryForUrl(url);
      final webMethods = entry.fetch[FetchContext.web] ?? [];

      expect(entry.domain, equals(''),
          reason: 'example.com should use the default (empty domain) entry');
      expect(webMethods.isNotEmpty, isTrue);
      expect(webMethods.first, equals(FetchMethod.direct),
          reason: 'Default config should try direct fetch first on web');
    });
  });
}
