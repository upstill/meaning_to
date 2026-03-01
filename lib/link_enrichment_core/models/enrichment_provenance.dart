import 'package:meaning_to/link_enrichment_core/rules/site_rule.dart';

class EnrichmentProvenance {
  final String siteId;
  final FetchMethod method;
  final String context;
  final String? ruleId;

  const EnrichmentProvenance({
    required this.siteId,
    required this.method,
    required this.context,
    this.ruleId,
  });
}
