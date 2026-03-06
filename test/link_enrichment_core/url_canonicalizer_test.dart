import 'package:flutter_test/flutter_test.dart';
import 'package:link_enrichment_core/utils/url_canonicalizer.dart';

void main() {
  group('UrlCanonicalizer.extractUrl', () {
    test('extracts href from HTML link', () {
      const html = '<a href="https://example.com/path?q=1">Example</a>';
      expect(UrlCanonicalizer.extractUrl(html), 'https://example.com/path?q=1');
    });

    test('returns plain URL unchanged', () {
      const url = 'https://example.com/path?q=1';
      expect(UrlCanonicalizer.extractUrl(url), url);
    });
  });

  group('UrlCanonicalizer.normalize', () {
    test('removes known tracking params and preserves others', () {
      const input =
          'https://example.com/watch?v=abc&utm_source=test&si=123&keep=yes';
      final result = UrlCanonicalizer.normalize(input);
      expect(result, 'https://example.com/watch?v=abc&keep=yes');
    });

    test('is idempotent', () {
      const input = 'https://example.com/a?utm_source=x&keep=y';
      final once = UrlCanonicalizer.normalize(input);
      final twice = UrlCanonicalizer.normalize(once);
      expect(twice, once);
    });

    test('returns input when URL is invalid', () {
      const input = 'not-a-url';
      expect(UrlCanonicalizer.normalize(input), input);
    });

    test('canonicalizes IMDb URLs to title id path', () {
      const input =
          'https://www.imdb.com/title/tt0111161/?ref_=vp_close&foo=bar';
      expect(
        UrlCanonicalizer.normalize(input),
        'https://www.imdb.com/title/tt0111161/',
      );
    });

    test('canonicalizes JustWatch URLs by removing /u suffix and query', () {
      const input =
          'https://www.justwatch.com/us/movie/the-shawshank-redemption/u?utm_source=x';
      expect(
        UrlCanonicalizer.normalize(input),
        'https://www.justwatch.com/us/movie/the-shawshank-redemption',
      );
    });

    test('canonicalizes TIDAL URLs by removing /u suffix but preserving query',
        () {
      const input = 'https://tidal.com/album/31826314/u?country=US&si=abc';
      expect(
        UrlCanonicalizer.normalize(input),
        'https://tidal.com/album/31826314?country=US&si=abc',
      );
    });
  });
}
