import 'package:flutter_test/flutter_test.dart';
import 'package:link_enrichment_core/models/enrichment_error.dart';
import 'package:link_enrichment_core/score/quality_scorer.dart';

void main() {
  group('QualityScorer', () {
    test('scores API-backed complete result higher than URL fallback', () {
      const high = QualitySignals(
        sourceKind: QualitySourceKind.siteApi,
        hasTitle: true,
        hasSynopsis: true,
        hasCategoryHints: true,
        hasCanonicalUrl: true,
        matchedExplicitSiteRule: true,
        responseMs: 500,
      );

      const low = QualitySignals(
        sourceKind: QualitySourceKind.urlFallback,
        hasTitle: true,
        hasSynopsis: false,
        hasCanonicalUrl: true,
        titleLooksLikeSlugOrDomain: true,
      );

      expect(QualityScorer.score(high), greaterThan(QualityScorer.score(low)));
    });

    test('returns low score when blocked error is present', () {
      const blocked = QualitySignals(
        sourceKind: QualitySourceKind.structuredMetadata,
        hasTitle: true,
        hasSynopsis: true,
        errors: [EnrichmentErrorCode.blocked],
      );

      expect(QualityScorer.score(blocked), lessThanOrEqualTo(15));
    });

    test('always returns values in [0,100]', () {
      const signals = QualitySignals(
        sourceKind: QualitySourceKind.siteApi,
        hasTitle: true,
        hasSynopsis: true,
        hasCategoryHints: true,
        hasCanonicalUrl: true,
        matchedExplicitSiteRule: true,
        responseMs: 10,
      );

      final score = QualityScorer.score(signals);
      expect(score, inInclusiveRange(0, 100));
    });
  });
}
