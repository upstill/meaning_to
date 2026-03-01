import 'package:meaning_to/link_enrichment_core/models/enrichment_error.dart';
import 'package:meaning_to/link_enrichment_core/models/enrichment_provenance.dart';
import 'package:meaning_to/link_enrichment_core/models/enrichment_status.dart';

class EnrichmentResult {
  final String normalizedUrl;
  final String? title;
  final String? synopsis;
  final List<String> categoryHints;
  final int qualityScore;
  final EnrichmentProvenance? source;
  final EnrichmentStatus status;
  final List<EnrichmentError> errors;

  const EnrichmentResult({
    required this.normalizedUrl,
    this.title,
    this.synopsis,
    this.categoryHints = const [],
    this.qualityScore = 0,
    this.source,
    this.status = EnrichmentStatus.failed,
    this.errors = const [],
  });
}
