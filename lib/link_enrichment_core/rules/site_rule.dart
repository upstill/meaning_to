import 'package:meaning_to/link_enrichment_core/models/enrichment_context.dart';

enum FetchMethod { direct, allOrigins, corsProxy, corsAnywhere, youtubeApi }

enum ExtractionSource {
  metaName,
  metaProperty,
  jsonLdField,
  cssText,
  cssDirectText,
  htmlTitle,
  h1,
  youtubeApi,
}

class ExtractionRule {
  final ExtractionSource source;
  final String? selector;

  const ExtractionRule({required this.source, this.selector});
}

class SiteRule {
  final String id;
  final List<String> domainPatterns;
  final String displayName;
  final Map<EnrichmentContext, List<FetchMethod>> fetchByContext;
  final List<ExtractionRule> titleRules;
  final List<ExtractionRule> synopsisRules;
  final List<String> stripSuffixes;
  final bool synopsisEnabled;

  const SiteRule({
    required this.id,
    required this.domainPatterns,
    required this.displayName,
    required this.fetchByContext,
    this.titleRules = const [],
    this.synopsisRules = const [],
    this.stripSuffixes = const [],
    this.synopsisEnabled = true,
  });
}
