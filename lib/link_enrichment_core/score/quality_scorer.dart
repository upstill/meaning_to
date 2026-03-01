import 'package:meaning_to/link_enrichment_core/models/enrichment_error.dart';

enum QualitySourceKind {
  siteApi,
  structuredMetadata,
  siteSpecificSelector,
  genericTitleTag,
  urlFallback,
}

class QualitySignals {
  final QualitySourceKind sourceKind;
  final bool hasTitle;
  final bool hasSynopsis;
  final bool hasCategoryHints;
  final bool hasCanonicalUrl;
  final bool titleLooksLikeSlugOrDomain;
  final bool synopsisLooksBoilerplate;
  final bool matchedExplicitSiteRule;
  final bool hadRetries;
  final int responseMs;
  final List<EnrichmentErrorCode> errors;

  const QualitySignals({
    required this.sourceKind,
    required this.hasTitle,
    required this.hasSynopsis,
    this.hasCategoryHints = false,
    this.hasCanonicalUrl = true,
    this.titleLooksLikeSlugOrDomain = false,
    this.synopsisLooksBoilerplate = false,
    this.matchedExplicitSiteRule = false,
    this.hadRetries = false,
    this.responseMs = 0,
    this.errors = const [],
  });
}

class QualityScorer {
  static int score(QualitySignals s) {
    if (s.errors.contains(EnrichmentErrorCode.blocked)) {
      return 10;
    }

    var total = 0;
    total += _sourcePoints(s.sourceKind);

    if (s.hasTitle) total += 10;
    if (s.hasSynopsis) total += 8;
    if (s.hasCategoryHints) total += 6;
    if (s.hasCanonicalUrl) total += 4;

    if (s.matchedExplicitSiteRule) total += 8;
    if (!s.hadRetries) total += 5;
    if (s.responseMs > 0 && s.responseMs <= 2000) total += 5;

    if (s.titleLooksLikeSlugOrDomain) total -= 10;
    if (s.synopsisLooksBoilerplate) total -= 8;
    if (s.errors.contains(EnrichmentErrorCode.parseFailure)) total -= 8;
    if (s.errors.contains(EnrichmentErrorCode.timeout)) total -= 6;

    if (total < 0) return 0;
    if (total > 100) return 100;
    return total;
  }

  static int _sourcePoints(QualitySourceKind kind) {
    switch (kind) {
      case QualitySourceKind.siteApi:
        return 35;
      case QualitySourceKind.structuredMetadata:
        return 28;
      case QualitySourceKind.siteSpecificSelector:
        return 24;
      case QualitySourceKind.genericTitleTag:
        return 16;
      case QualitySourceKind.urlFallback:
        return 6;
    }
  }
}
