import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:meaning_to/link_enrichment_core/models/enrichment_context.dart';
import 'package:meaning_to/link_enrichment_core/models/enrichment_status.dart';
import 'package:meaning_to/link_enrichment_core/service/enrichment_service.dart';

void main() {
  group('Site behavior regression coverage', () {
    final service = EnrichmentService(
      httpGet: (uri, {headers}) async {
        if (uri.host.contains('justwatch.com') &&
            uri.path.contains('article')) {
          return http.Response(
            '''
            <html>
              <head>
                <title>Ignored</title>
              </head>
              <body>
                <h1 class="title-detail-hero__details__title">Article Match</h1>
                <div id="synopsis">
                  <article class="article-block">Synopsis from legacy article selector.</article>
                </div>
                <p>This filler text keeps the fixture above minimum body size for enrichment parsing guards.</p>
              </body>
            </html>
            ''',
            200,
          );
        }

        if (uri.host.contains('justwatch.com') && uri.path.contains('jsonld')) {
          return http.Response(
            '''
            <html>
              <head>
                <script type="application/ld+json">
                  {"@context":"https://schema.org","@type":"Movie","description":"Synopsis from JSON-LD fallback."}
                </script>
              </head>
              <body>
                <h1>JSON LD Match</h1>
                <p>This filler text keeps the fixture above minimum body size for enrichment parsing guards.</p>
              </body>
            </html>
            ''',
            200,
          );
        }

        if (uri.host.contains('letterboxd.com')) {
          return http.Response(
            '''
            <html>
              <head>
                <title>Letterboxd Page</title>
                <meta name="description" content="Letterboxd synopsis from meta fallback.">
              </head>
              <body>
                <h1 class="headline-1">Letterboxd Film</h1>
                <p>This fixture omits review body text to force description fallback to meta tags.</p>
              </body>
            </html>
            ''',
            200,
          );
        }

        if (uri.host.contains('imdb.com')) {
          return http.Response(
            '''
            <html>
              <head>
                <title>Example Movie (1994) - IMDb</title>
                <script type="application/ld+json">
                  {"@context":"https://schema.org","@type":"Movie","description":"IMDb synopsis from JSON-LD fallback."}
                </script>
              </head>
              <body>
                <p>This fixture intentionally excludes meta description to verify JSON-LD extraction.</p>
              </body>
            </html>
            ''',
            200,
          );
        }

        return http.Response(
            '<html><body>unexpected fixture</body></html>', 404);
      },
    );

    test('extracts JustWatch synopsis from legacy article selector', () async {
      final result = await service.bootstrapFromUrl(
        'https://www.justwatch.com/us/movie/article',
        context: EnrichmentContext.test,
      );

      expect(result.status, EnrichmentStatus.success);
      expect(result.title, 'Article Match');
      expect(result.synopsis, 'Synopsis from legacy article selector.');
    });

    test('extracts JustWatch synopsis from JSON-LD fallback', () async {
      final result = await service.bootstrapFromUrl(
        'https://www.justwatch.com/us/movie/jsonld',
        context: EnrichmentContext.test,
      );

      expect(result.status, EnrichmentStatus.success);
      expect(result.title, 'JSON LD Match');
      expect(result.synopsis, 'Synopsis from JSON-LD fallback.');
    });

    test('extracts Letterboxd synopsis from meta fallback', () async {
      final result = await service.bootstrapFromUrl(
        'https://letterboxd.com/film/example-film/',
        context: EnrichmentContext.test,
      );

      expect(result.status, EnrichmentStatus.success);
      expect(result.title, 'Letterboxd Film');
      expect(result.synopsis, 'Letterboxd synopsis from meta fallback.');
    });

    test('extracts IMDb synopsis from JSON-LD fallback', () async {
      final result = await service.bootstrapFromUrl(
        'https://www.imdb.com/title/tt0111161/',
        context: EnrichmentContext.test,
      );

      expect(result.status, EnrichmentStatus.success);
      expect(result.title, 'Example Movie');
      expect(result.synopsis, 'IMDb synopsis from JSON-LD fallback.');
    });
  });
}
