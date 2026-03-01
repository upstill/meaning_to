import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:meaning_to/link_enrichment_core/models/enrichment_context.dart';
import 'package:meaning_to/link_enrichment_core/models/enrichment_error.dart';
import 'package:meaning_to/link_enrichment_core/models/enrichment_provenance.dart';
import 'package:meaning_to/link_enrichment_core/models/enrichment_request.dart';
import 'package:meaning_to/link_enrichment_core/models/enrichment_result.dart';
import 'package:meaning_to/link_enrichment_core/models/enrichment_status.dart';
import 'package:meaning_to/link_enrichment_core/rules/default_site_rule_provider.dart';
import 'package:meaning_to/link_enrichment_core/rules/site_rule.dart';
import 'package:meaning_to/link_enrichment_core/rules/site_rule_provider.dart';
import 'package:meaning_to/link_enrichment_core/score/quality_scorer.dart';
import 'package:meaning_to/link_enrichment_core/sink/fetch_outcome_sink.dart';
import 'package:meaning_to/link_enrichment_core/utils/url_canonicalizer.dart';

typedef HttpGet = Future<http.Response> Function(
  Uri uri, {
  Map<String, String>? headers,
});

class YoutubeVideoInfo {
  final String title;
  final String? description;

  const YoutubeVideoInfo({required this.title, this.description});
}

typedef YoutubeResolver = Future<YoutubeVideoInfo?> Function(String url);

/// Enrichment service with parallel fetch racing.
///
/// All fetch methods for a URL are fired concurrently; the first that returns
/// a usable title wins.  This eliminates the cumulative latency of sequential
/// fallback chains.
class EnrichmentService {
  final SiteRuleProvider _ruleProvider;
  final HttpGet _httpGet;
  final YoutubeResolver? _youtubeResolver;
  final FetchOutcomeSink _sink;

  EnrichmentService({
    SiteRuleProvider? ruleProvider,
    HttpGet? httpGet,
    YoutubeResolver? youtubeResolver,
    FetchOutcomeSink sink = FetchOutcomeSink.noOp,
  })  : _ruleProvider = ruleProvider ?? DefaultSiteRuleProvider(),
        _httpGet = httpGet ?? http.get,
        _youtubeResolver = youtubeResolver,
        _sink = sink;

  Future<EnrichmentResult> bootstrapFromUrl(
    String url, {
    EnrichmentContext context = EnrichmentContext.native,
    int deadlineMs = 5000,
    bool allowDeferred = true,
  }) async {
    return enrich(
      EnrichmentRequest(
        url: url,
        context: context,
        deadlineMs: deadlineMs,
        allowDeferred: allowDeferred,
      ),
    );
  }

  Future<EnrichmentResult> enrich(EnrichmentRequest request) async {
    final normalizedUrl = UrlCanonicalizer.normalize(request.url);
    final rule = _ruleProvider.matchRuleForUrl(normalizedUrl);
    final methods =
        _ruleProvider.fetchMethodsFor(normalizedUrl, request.context);

    if (methods.isEmpty) {
      return _deferredResult(
        normalizedUrl: normalizedUrl,
        rule: rule,
        context: request.context,
      );
    }

    final deadline = request.deadlineMs > 0
        ? Duration(milliseconds: request.deadlineMs)
        : const Duration(seconds: 10);

    // Fire all fetch methods concurrently — first non-null title wins.
    final futures = methods
        .map((method) => _tryMethod(
              method: method,
              normalizedUrl: normalizedUrl,
              rule: rule,
              context: request.context,
              timeout: deadline,
              synopsisEnabled: request.synopsisEnabled,
            ))
        .toList();

    EnrichmentResult? winner;
    var sawTimeout = false;
    try {
      winner = await _firstNonNull(futures).timeout(deadline);
    } on TimeoutException {
      sawTimeout = true;
    }

    if (winner != null) return winner;

    if (sawTimeout && request.allowDeferred) {
      return _deferredResult(
        normalizedUrl: normalizedUrl,
        rule: rule,
        context: request.context,
        code: EnrichmentErrorCode.timeout,
        message: 'Deadline exceeded before enrichment completed.',
      );
    }

    return EnrichmentResult(
      normalizedUrl: normalizedUrl,
      qualityScore: QualityScorer.score(
        QualitySignals(
          sourceKind: QualitySourceKind.urlFallback,
          hasTitle: false,
          hasSynopsis: false,
          hasCanonicalUrl: true,
          matchedExplicitSiteRule: _isExplicitRule(rule),
          errors: [
            sawTimeout
                ? EnrichmentErrorCode.timeout
                : EnrichmentErrorCode.parseFailure,
          ],
        ),
      ),
      status: EnrichmentStatus.failed,
      errors: [
        EnrichmentError(
          sawTimeout
              ? EnrichmentErrorCode.timeout
              : EnrichmentErrorCode.parseFailure,
          sawTimeout
              ? 'Deadline exceeded before enrichment completed.'
              : 'No fetch strategy produced a usable title.',
        ),
      ],
    );
  }

  /// Returns the first non-null result from [futures], or null if all fail.
  static Future<T?> _firstNonNull<T>(List<Future<T?>> futures) {
    if (futures.isEmpty) return Future.value(null);
    final completer = Completer<T?>();
    var remaining = futures.length;
    for (final future in futures) {
      future.then((value) {
        if (value != null && !completer.isCompleted) {
          completer.complete(value);
        } else {
          remaining--;
          if (remaining == 0 && !completer.isCompleted) {
            completer.complete(null);
          }
        }
      }).catchError((_) {
        remaining--;
        if (remaining == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      });
    }
    return completer.future;
  }

  /// Attempts a single fetch method; returns an [EnrichmentResult] on success
  /// or null on any failure (network error, bad status, no title, timeout).
  Future<EnrichmentResult?> _tryMethod({
    required FetchMethod method,
    required String normalizedUrl,
    required SiteRule rule,
    required EnrichmentContext context,
    required Duration timeout,
    required bool synopsisEnabled,
  }) async {
    if (method == FetchMethod.youtubeApi) {
      return _tryYoutubeApi(
        method: method,
        context: context,
        normalizedUrl: normalizedUrl,
        rule: rule,
        timeout: timeout,
        synopsisEnabled: synopsisEnabled,
      );
    }

    final fetchUrl = _buildFetchUrl(method, normalizedUrl);
    if (fetchUrl == null) return null;

    final sw = Stopwatch()..start();
    try {
      final response = await _httpGet(
        Uri.parse(fetchUrl),
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        },
      ).timeout(timeout);
      final elapsedMs = sw.elapsedMilliseconds;

      _sink.record(
        url: normalizedUrl,
        siteId: rule.id,
        context: context.name,
        method: method.name,
        success: response.statusCode == 200 && response.body.length >= 100,
        responseMs: elapsedMs,
      );

      if (response.statusCode != 200 || response.body.length < 100) {
        return null;
      }

      final htmlContent =
          utf8.decode(response.bodyBytes, allowMalformed: true);
      final document = html_parser.parse(htmlContent);
      final rawTitle = _extractTextFromRules(document, rule.titleRules);
      if (rawTitle == null || rawTitle.isEmpty) return null;

      final title = _applyStripSuffixes(rawTitle, rule.stripSuffixes);
      final synopsis = (rule.synopsisEnabled && synopsisEnabled)
          ? _extractTextFromRules(document, rule.synopsisRules)
          : null;

      return EnrichmentResult(
        normalizedUrl: normalizedUrl,
        title: title,
        synopsis: synopsis,
        qualityScore: QualityScorer.score(
          QualitySignals(
            sourceKind: QualitySourceKind.siteSpecificSelector,
            hasTitle: true,
            hasSynopsis: synopsis != null && synopsis.isNotEmpty,
            hasCanonicalUrl: true,
            matchedExplicitSiteRule: _isExplicitRule(rule),
            responseMs: elapsedMs,
          ),
        ),
        source: EnrichmentProvenance(
          siteId: rule.id,
          method: method,
          context: context.name,
          ruleId: rule.id,
        ),
        status: EnrichmentStatus.success,
      );
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<EnrichmentResult?> _tryYoutubeApi({
    required FetchMethod method,
    required EnrichmentContext context,
    required String normalizedUrl,
    required SiteRule rule,
    required Duration timeout,
    required bool synopsisEnabled,
  }) async {
    if (_youtubeResolver == null) return null;
    try {
      final info = await _youtubeResolver(normalizedUrl).timeout(timeout);
      if (info == null || info.title.isEmpty) return null;
      final synopsis = synopsisEnabled ? info.description : null;
      return EnrichmentResult(
        normalizedUrl: normalizedUrl,
        title: _applyStripSuffixes(info.title, rule.stripSuffixes),
        synopsis: synopsis,
        qualityScore: QualityScorer.score(
          QualitySignals(
            sourceKind: QualitySourceKind.siteApi,
            hasTitle: true,
            hasSynopsis: synopsis != null && synopsis.isNotEmpty,
            hasCanonicalUrl: true,
            matchedExplicitSiteRule: _isExplicitRule(rule),
          ),
        ),
        source: EnrichmentProvenance(
          siteId: rule.id,
          method: method,
          context: context.name,
          ruleId: rule.id,
        ),
        status: EnrichmentStatus.success,
      );
    } catch (_) {
      return null;
    }
  }

  EnrichmentResult _deferredResult({
    required String normalizedUrl,
    required SiteRule rule,
    required EnrichmentContext context,
    EnrichmentErrorCode code = EnrichmentErrorCode.networkFailure,
    String message = 'No fetch methods available for this context.',
  }) {
    final quality = QualityScorer.score(
      QualitySignals(
        sourceKind: QualitySourceKind.urlFallback,
        hasTitle: false,
        hasSynopsis: false,
        hasCanonicalUrl: true,
        matchedExplicitSiteRule: _isExplicitRule(rule),
      ),
    );

    return EnrichmentResult(
      normalizedUrl: normalizedUrl,
      categoryHints: const [],
      qualityScore: quality,
      source: EnrichmentProvenance(
        siteId: rule.id,
        method: FetchMethod.direct,
        context: context.name,
        ruleId: rule.id,
      ),
      status: EnrichmentStatus.deferred,
      errors: [
        EnrichmentError(code, message),
      ],
    );
  }

  static bool _isExplicitRule(SiteRule rule) =>
      rule.id != 'generic-default' && !rule.domainPatterns.contains('');

  static String? _buildFetchUrl(FetchMethod method, String url) {
    switch (method) {
      case FetchMethod.direct:
        return url;
      case FetchMethod.allOrigins:
        return 'https://api.allorigins.win/raw?url=${Uri.encodeComponent(url)}';
      case FetchMethod.corsProxy:
        return 'https://corsproxy.io/?${Uri.encodeComponent(url)}';
      case FetchMethod.corsAnywhere:
        return 'https://cors-anywhere.herokuapp.com/$url';
      case FetchMethod.youtubeApi:
        return null;
    }
  }

  static String _applyStripSuffixes(String title, List<String> patterns) {
    String result = title;
    for (final pattern in patterns) {
      result =
          result.replaceFirst(RegExp(pattern, caseSensitive: false), '').trim();
    }
    return result;
  }

  static String? _extractTextFromRules(
      dom.Document document, List<ExtractionRule> rules) {
    for (final rule in rules) {
      if (rule.source == ExtractionSource.youtubeApi) continue;

      String? extracted;
      switch (rule.source) {
        case ExtractionSource.metaName:
          extracted = document
              .querySelector('meta[name="${rule.selector}"]')
              ?.attributes['content']
              ?.trim();
        case ExtractionSource.metaProperty:
          extracted = document
              .querySelector('meta[property="${rule.selector}"]')
              ?.attributes['content']
              ?.trim();
        case ExtractionSource.jsonLdField:
          final field = rule.selector;
          if (field != null && field.isNotEmpty) {
            extracted = _extractJsonLdField(document, field);
          }
        case ExtractionSource.cssText:
          extracted = document.querySelector(rule.selector!)?.text.trim();
        case ExtractionSource.cssDirectText:
          final el = document.querySelector(rule.selector!);
          if (el != null) {
            final buf = StringBuffer();
            for (final node in el.nodes) {
              if (node.nodeType == 3) {
                buf.write(node.text ?? '');
              }
            }
            extracted = buf.toString().trim();
          }
        case ExtractionSource.htmlTitle:
          extracted = document.querySelector('title')?.text.trim();
        case ExtractionSource.h1:
          extracted = document.querySelector('h1')?.text.trim();
        case ExtractionSource.youtubeApi:
          break;
      }

      if (extracted != null && extracted.isNotEmpty) return extracted;
    }
    return null;
  }

  static String? _extractJsonLdField(dom.Document document, String field) {
    final scripts =
        document.querySelectorAll('script[type="application/ld+json"]');
    for (final script in scripts) {
      final raw = script.text.trim();
      if (raw.isEmpty) continue;
      try {
        final dynamic decoded = json.decode(raw);
        final value = _findJsonField(decoded, field);
        if (value != null && value.isNotEmpty) {
          return value;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static String? _findJsonField(dynamic node, String field) {
    if (node is Map<String, dynamic>) {
      final direct = node[field];
      if (direct is String && direct.trim().isNotEmpty) {
        return direct.trim();
      }

      for (final value in node.values) {
        final found = _findJsonField(value, field);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final item in node) {
        final found = _findJsonField(item, field);
        if (found != null) return found;
      }
    }
    return null;
  }
}
