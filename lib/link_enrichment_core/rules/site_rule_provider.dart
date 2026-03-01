import 'package:meaning_to/link_enrichment_core/models/enrichment_context.dart';
import 'package:meaning_to/link_enrichment_core/rules/site_rule.dart';

abstract class SiteRuleProvider {
  SiteRule matchRuleForUrl(String url);
  List<FetchMethod> fetchMethodsFor(String url, EnrichmentContext context);
}
