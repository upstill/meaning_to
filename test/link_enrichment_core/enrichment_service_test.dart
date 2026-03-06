import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:link_enrichment_core/models/enrichment_context.dart';
import 'package:link_enrichment_core/models/enrichment_error.dart';
import 'package:link_enrichment_core/models/enrichment_request.dart';
import 'package:link_enrichment_core/models/enrichment_status.dart';
import 'package:link_enrichment_core/rules/site_rule.dart';
import 'package:link_enrichment_core/rules/site_rule_provider.dart';
import 'package:link_enrichment_core/service/enrichment_service.dart';

class _FakeRuleProvider implements SiteRuleProvider {
  const _FakeRuleProvider();

  static const SiteRule _rule = SiteRule(
    id: 'fake',
    domainPatterns: ['example.com'],
    displayName: 'Fake',
    fetchByContext: {
      EnrichmentContext.test: [FetchMethod.direct],
    },
    titleRules: [
      ExtractionRule(source: ExtractionSource.htmlTitle),
    ],
    synopsisRules: [
      ExtractionRule(
        source: ExtractionSource.metaName,
        selector: 'description',
      ),
    ],
  );

  @override
  List<FetchMethod> fetchMethodsFor(String url, EnrichmentContext context) {
    return _rule.fetchByContext[context] ?? const [];
  }

  @override
  SiteRule matchRuleForUrl(String url) => _rule;
}

class _SynopsisDisabledRuleProvider implements SiteRuleProvider {
  const _SynopsisDisabledRuleProvider();

  static const SiteRule _rule = SiteRule(
    id: 'synopsis-disabled',
    domainPatterns: ['nosynopsis.example'],
    displayName: 'NoSynopsis',
    fetchByContext: {
      EnrichmentContext.test: [FetchMethod.direct],
    },
    titleRules: [
      ExtractionRule(source: ExtractionSource.htmlTitle),
    ],
    synopsisRules: [
      ExtractionRule(
        source: ExtractionSource.metaName,
        selector: 'description',
      ),
    ],
    synopsisEnabled: false,
  );

  @override
  List<FetchMethod> fetchMethodsFor(String url, EnrichmentContext context) {
    return _rule.fetchByContext[context] ?? const [];
  }

  @override
  SiteRule matchRuleForUrl(String url) => _rule;
}

class _NoMethodRuleProvider implements SiteRuleProvider {
  const _NoMethodRuleProvider();

  static const SiteRule _rule = SiteRule(
    id: 'no-methods',
    domainPatterns: ['nomethods.example'],
    displayName: 'NoMethods',
    fetchByContext: {EnrichmentContext.test: []},
  );

  @override
  List<FetchMethod> fetchMethodsFor(String url, EnrichmentContext context) =>
      const [];

  @override
  SiteRule matchRuleForUrl(String url) => _rule;
}

void main() {
  group('EnrichmentService', () {
    final service = EnrichmentService(
      ruleProvider: const _FakeRuleProvider(),
      httpGet: (uri, {headers}) async {
        final body = '''
          <html>
            <head>
              <title>Example Title</title>
              <meta name="description" content="Example synopsis">
            </head>
            <body></body>
          </html>
        ''';
        return http.Response(body, 200);
      },
    );

    test('bootstrapFromUrl normalizes URL through facade', () async {
      final result = await service.bootstrapFromUrl(
        'https://example.com/path?utm_source=test&keep=yes',
        context: EnrichmentContext.test,
      );

      expect(result.normalizedUrl, 'https://example.com/path?keep=yes');
      expect(result.title, 'Example Title');
      expect(result.synopsis, 'Example synopsis');
      expect(result.status, EnrichmentStatus.success);
    });

    test('returns success status when strategy fetch and extraction succeed',
        () async {
      final result = await service.bootstrapFromUrl(
        'https://example.com/a',
        context: EnrichmentContext.test,
      );

      expect(result.status, EnrichmentStatus.success);
      expect(result.qualityScore, inInclusiveRange(0, 100));
    });

    test('returns deferred when no methods are available for context',
        () async {
      final deferredService = EnrichmentService(
        ruleProvider: const _NoMethodRuleProvider(),
      );

      final result = await deferredService.bootstrapFromUrl(
        'https://nomethods.example/item',
        context: EnrichmentContext.test,
      );

      expect(result.status, EnrichmentStatus.deferred);
    });

    test('suppresses synopsis when synopsisEnabled is false', () async {
      final noSynopsisService = EnrichmentService(
        ruleProvider: const _SynopsisDisabledRuleProvider(),
        httpGet: (uri, {headers}) async {
          return http.Response(
            '''
            <html>
              <head>
                <title>Title</title>
                <meta name="description" content="Hidden synopsis">
              </head>
              <body>
                <p>This fixture is intentionally long enough to pass response size guards in the enrichment service.</p>
              </body>
            </html>
            ''',
            200,
          );
        },
      );

      final result = await noSynopsisService.bootstrapFromUrl(
        'https://nosynopsis.example/item',
        context: EnrichmentContext.test,
      );
      expect(result.title, 'Title');
      expect(result.synopsis, isNull);
    });

    test('returns deferred on deadline timeout when deferral is allowed',
        () async {
      final slowService = EnrichmentService(
        ruleProvider: const _FakeRuleProvider(),
        httpGet: (uri, {headers}) async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return http.Response(
            '''
            <html>
              <head><title>Slow Title</title></head>
              <body><p>This fixture is intentionally long enough to pass response size guards in the enrichment service.</p></body>
            </html>
            ''',
            200,
          );
        },
      );

      final result = await slowService.enrich(
        const EnrichmentRequest(
          url: 'https://example.com/slow',
          context: EnrichmentContext.test,
          deadlineMs: 5,
          allowDeferred: true,
        ),
      );

      expect(result.status, EnrichmentStatus.deferred);
      expect(result.title, isNull);
      expect(result.errors.first.code, EnrichmentErrorCode.timeout);
    });

    test('returns failed on deadline timeout when deferral is disabled',
        () async {
      final slowService = EnrichmentService(
        ruleProvider: const _FakeRuleProvider(),
        httpGet: (uri, {headers}) async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return http.Response(
            '''
            <html>
              <head><title>Slow Title</title></head>
              <body><p>This fixture is intentionally long enough to pass response size guards in the enrichment service.</p></body>
            </html>
            ''',
            200,
          );
        },
      );

      final result = await slowService.enrich(
        const EnrichmentRequest(
          url: 'https://example.com/slow',
          context: EnrichmentContext.test,
          deadlineMs: 5,
          allowDeferred: false,
        ),
      );

      expect(result.status, EnrichmentStatus.failed);
      expect(result.errors.first.code, EnrichmentErrorCode.timeout);
    });
  });
}
