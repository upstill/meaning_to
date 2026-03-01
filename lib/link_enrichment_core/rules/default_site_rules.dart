import 'package:meaning_to/link_enrichment_core/models/enrichment_context.dart';
import 'package:meaning_to/link_enrichment_core/rules/site_rule.dart';

/// Default site rules for the enrichment library.
///
/// Mirrors [kSiteTable] from site_table.dart as library-native [SiteRule]
/// objects, eliminating the dependency on the app-layer adapter.
///
/// Evaluated top-to-bottom; first entry whose domainPatterns the URL host
/// matches wins.  The final entry (domainPatterns: ['']) is the fallback.
const List<SiteRule> kDefaultSiteRules = [
  SiteRule(
    id: 'justwatch.com',
    domainPatterns: ['justwatch.com'],
    displayName: 'JustWatch',
    fetchByContext: {
      EnrichmentContext.web: [FetchMethod.allOrigins, FetchMethod.corsProxy],
      EnrichmentContext.native: [FetchMethod.direct],
      EnrichmentContext.test: [FetchMethod.direct],
    },
    titleRules: [
      ExtractionRule(
        source: ExtractionSource.cssDirectText,
        selector: 'h1.title-detail-hero__details__title',
      ),
      ExtractionRule(source: ExtractionSource.h1),
    ],
    synopsisRules: [
      ExtractionRule(
        source: ExtractionSource.cssText,
        selector: 'div#synopsis article.article-block',
      ),
      ExtractionRule(
        source: ExtractionSource.cssText,
        selector: 'div#synopsis p',
      ),
      ExtractionRule(source: ExtractionSource.jsonLdField, selector: 'description'),
      ExtractionRule(source: ExtractionSource.metaName, selector: 'description'),
      ExtractionRule(source: ExtractionSource.metaProperty, selector: 'og:description'),
    ],
    stripSuffixes: [
      r'\s*\(\d{4}\).*$',
      r'\s*streaming:?\s*where to watch.*$',
    ],
  ),

  SiteRule(
    id: 'letterboxd.com',
    domainPatterns: ['letterboxd.com'],
    displayName: 'Letterboxd',
    fetchByContext: {
      EnrichmentContext.web: [FetchMethod.allOrigins, FetchMethod.corsProxy],
      EnrichmentContext.native: [FetchMethod.direct],
      EnrichmentContext.test: [FetchMethod.direct],
    },
    titleRules: [
      ExtractionRule(source: ExtractionSource.cssText, selector: 'h1.headline-1'),
      ExtractionRule(source: ExtractionSource.h1),
    ],
    synopsisRules: [
      ExtractionRule(
        source: ExtractionSource.cssText,
        selector: '.review .body-text p',
      ),
      ExtractionRule(source: ExtractionSource.metaName, selector: 'description'),
      ExtractionRule(source: ExtractionSource.metaProperty, selector: 'og:description'),
    ],
    stripSuffixes: [r'\s*\(\d{4}\).*$'],
  ),

  SiteRule(
    id: 'boxd.it',
    domainPatterns: ['boxd.it'],
    displayName: 'Letterboxd (short link)',
    fetchByContext: {
      EnrichmentContext.web: [FetchMethod.allOrigins, FetchMethod.corsProxy],
      EnrichmentContext.native: [FetchMethod.direct],
      EnrichmentContext.test: [FetchMethod.direct],
    },
    titleRules: [
      ExtractionRule(source: ExtractionSource.cssText, selector: 'h1.headline-1'),
      ExtractionRule(source: ExtractionSource.h1),
    ],
    synopsisRules: [
      ExtractionRule(
        source: ExtractionSource.cssText,
        selector: '.review .body-text p',
      ),
      ExtractionRule(source: ExtractionSource.metaName, selector: 'description'),
      ExtractionRule(source: ExtractionSource.metaProperty, selector: 'og:description'),
    ],
    stripSuffixes: [r'\s*\(\d{4}\).*$'],
  ),

  SiteRule(
    id: 'youtube.com',
    domainPatterns: ['youtube.com'],
    displayName: 'YouTube',
    fetchByContext: {
      EnrichmentContext.web: [
        FetchMethod.youtubeApi,
        FetchMethod.corsProxy,
        FetchMethod.allOrigins,
      ],
      EnrichmentContext.native: [FetchMethod.youtubeApi, FetchMethod.direct],
      EnrichmentContext.test: [FetchMethod.youtubeApi, FetchMethod.direct],
    },
    titleRules: [
      ExtractionRule(source: ExtractionSource.youtubeApi),
      ExtractionRule(source: ExtractionSource.metaName, selector: 'title'),
      ExtractionRule(source: ExtractionSource.htmlTitle),
    ],
    synopsisRules: [
      ExtractionRule(source: ExtractionSource.metaName, selector: 'description'),
      ExtractionRule(source: ExtractionSource.metaProperty, selector: 'og:description'),
    ],
    stripSuffixes: [r'\s*-\s*YouTube\s*$'],
  ),

  SiteRule(
    id: 'ted.com',
    domainPatterns: ['ted.com'],
    displayName: 'TED',
    fetchByContext: {
      EnrichmentContext.web: [FetchMethod.allOrigins, FetchMethod.corsProxy],
      EnrichmentContext.native: [FetchMethod.direct],
      EnrichmentContext.test: [FetchMethod.direct],
    },
    titleRules: [
      ExtractionRule(source: ExtractionSource.metaName, selector: 'title'),
      ExtractionRule(source: ExtractionSource.metaProperty, selector: 'og:title'),
    ],
    synopsisRules: [
      ExtractionRule(source: ExtractionSource.jsonLdField, selector: 'description'),
      ExtractionRule(source: ExtractionSource.metaName, selector: 'description'),
      ExtractionRule(source: ExtractionSource.metaProperty, selector: 'og:description'),
    ],
  ),

  SiteRule(
    id: 'tidal.com',
    domainPatterns: ['tidal.com'],
    displayName: 'TIDAL',
    fetchByContext: {
      EnrichmentContext.web: [FetchMethod.allOrigins, FetchMethod.corsProxy],
      EnrichmentContext.native: [FetchMethod.direct],
      EnrichmentContext.test: [FetchMethod.direct],
    },
    titleRules: [
      ExtractionRule(
        source: ExtractionSource.cssText,
        selector: 'h2.wave-text-title-bold',
      ),
      ExtractionRule(source: ExtractionSource.htmlTitle),
    ],
    synopsisRules: [
      ExtractionRule(
        source: ExtractionSource.cssText,
        selector: 'div[data-test="biography"]',
      ),
      ExtractionRule(source: ExtractionSource.metaProperty, selector: 'og:description'),
    ],
    synopsisEnabled: false,
  ),

  SiteRule(
    id: 'imdb.com',
    domainPatterns: ['imdb.com'],
    displayName: 'IMDb',
    fetchByContext: {
      EnrichmentContext.web: [FetchMethod.direct, FetchMethod.allOrigins],
      EnrichmentContext.native: [FetchMethod.direct],
      EnrichmentContext.test: [FetchMethod.direct],
    },
    titleRules: [
      ExtractionRule(source: ExtractionSource.htmlTitle),
      ExtractionRule(source: ExtractionSource.metaProperty, selector: 'og:title'),
    ],
    synopsisRules: [
      ExtractionRule(source: ExtractionSource.jsonLdField, selector: 'description'),
      ExtractionRule(source: ExtractionSource.metaName, selector: 'description'),
      ExtractionRule(source: ExtractionSource.metaProperty, selector: 'og:description'),
    ],
    stripSuffixes: [r'\s*\(.*$'],
  ),

  SiteRule(
    id: 'amazon.com',
    domainPatterns: ['amazon.com'],
    displayName: 'Amazon',
    fetchByContext: {
      EnrichmentContext.web: [FetchMethod.allOrigins, FetchMethod.corsProxy],
      EnrichmentContext.native: [FetchMethod.direct],
      EnrichmentContext.test: [FetchMethod.allOrigins],
    },
    titleRules: [
      ExtractionRule(source: ExtractionSource.metaName, selector: 'title'),
      ExtractionRule(source: ExtractionSource.metaProperty, selector: 'og:title'),
    ],
    synopsisRules: [
      ExtractionRule(source: ExtractionSource.metaName, selector: 'description'),
      ExtractionRule(source: ExtractionSource.metaProperty, selector: 'og:description'),
    ],
  ),

  // ── Default (must be last) ───────────────────────────────────────────────
  SiteRule(
    id: 'generic-default',
    domainPatterns: [''],
    displayName: 'Generic',
    fetchByContext: {
      EnrichmentContext.web: [FetchMethod.direct, FetchMethod.allOrigins],
      EnrichmentContext.native: [FetchMethod.direct],
      EnrichmentContext.test: [FetchMethod.direct],
    },
    titleRules: [
      ExtractionRule(source: ExtractionSource.metaProperty, selector: 'og:title'),
      ExtractionRule(source: ExtractionSource.metaName, selector: 'title'),
      ExtractionRule(source: ExtractionSource.htmlTitle),
      ExtractionRule(source: ExtractionSource.h1),
    ],
    synopsisRules: [
      ExtractionRule(source: ExtractionSource.metaName, selector: 'description'),
      ExtractionRule(source: ExtractionSource.metaProperty, selector: 'og:description'),
    ],
  ),
];
