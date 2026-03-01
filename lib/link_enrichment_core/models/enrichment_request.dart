import 'package:meaning_to/link_enrichment_core/models/enrichment_context.dart';

class EnrichmentRequest {
  final String url;
  final EnrichmentContext context;
  final int deadlineMs;
  final bool allowDeferred;
  final bool synopsisEnabled;
  final Map<String, Object?> hints;

  const EnrichmentRequest({
    required this.url,
    required this.context,
    this.deadlineMs = 5000,
    this.allowDeferred = true,
    this.synopsisEnabled = true,
    this.hints = const {},
  });
}
