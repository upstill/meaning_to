import 'package:meaning_to/link_enrichment_core/models/enrichment_context.dart';
import 'package:meaning_to/link_enrichment_core/rules/default_site_rules.dart';
import 'package:meaning_to/link_enrichment_core/rules/site_rule.dart';
import 'package:meaning_to/link_enrichment_core/rules/site_rule_provider.dart';

/// Library-native rule provider backed by [kDefaultSiteRules].
///
/// Replaces [SiteTableRuleProvider], eliminating the dependency on the
/// app-layer [site_table.dart].
class DefaultSiteRuleProvider implements SiteRuleProvider {
  const DefaultSiteRuleProvider();

  @override
  SiteRule matchRuleForUrl(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return kDefaultSiteRules.firstWhere(
      (r) => r.domainPatterns.any((p) => p.isNotEmpty && host.contains(p)),
      orElse: () => kDefaultSiteRules.last,
    );
  }

  @override
  List<FetchMethod> fetchMethodsFor(String url, EnrichmentContext context) =>
      matchRuleForUrl(url).fetchByContext[context] ?? const [];
}
