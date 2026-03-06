import 'package:flutter_test/flutter_test.dart';
import 'package:link_enrichment_core/models/enrichment_context.dart';
import 'package:link_enrichment_core/rules/default_site_rule_provider.dart';
import 'package:link_enrichment_core/rules/site_rule.dart';

void main() {
  group('DefaultSiteRuleProvider', () {
    const provider = DefaultSiteRuleProvider();

    test('matches YouTube site rule', () {
      const url = 'https://www.youtube.com/watch?v=HGJ7-GK43lg';
      final rule = provider.matchRuleForUrl(url);

      expect(rule.id, 'youtube.com');
      expect(rule.displayName, 'YouTube');
      expect(rule.domainPatterns, contains('youtube.com'));
    });

    test('returns generic default for unknown domain', () {
      const url = 'https://example.org/my-post';
      final rule = provider.matchRuleForUrl(url);

      expect(rule.id, 'generic-default');
      expect(rule.domainPatterns, contains(''));
    });

    test('maps fetch methods for web context', () {
      const url = 'https://www.youtube.com/watch?v=abc123';
      final methods = provider.fetchMethodsFor(url, EnrichmentContext.web);

      expect(methods, isNotEmpty);
      expect(
        methods.first,
        anyOf(equals(FetchMethod.youtubeApi), equals(FetchMethod.corsProxy)),
      );
    });

    test('synopsisEnabled is false for TIDAL', () {
      const tidalUrl = 'https://tidal.com/album/31826314';
      final rule = provider.matchRuleForUrl(tidalUrl);
      expect(rule.id, 'tidal.com');
      expect(rule.synopsisEnabled, isFalse);
    });
  });
}
