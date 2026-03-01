import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/category_suggestion_registry.dart';
import 'package:meaning_to/utils/intent_handler.dart';

void main() {
  group('IntentHandler category suggestions', () {
    final handler = IntentHandler();

    test('matches registry output for representative URLs', () {
      const urls = [
        'https://www.justwatch.com/us/movie/the-shawshank-redemption',
        'https://www.justwatch.com/us/tv-show/breaking-bad',
        'https://www.imdb.com/title/tt0111161/',
        'https://letterboxd.com/film/the-shawshank-redemption/',
        'https://open.spotify.com/playlist/60iEsOOYsvriP3l7gBdyzW',
        'https://example.com/no-match',
      ];

      for (final url in urls) {
        final expected = CategorySuggestionRegistry.getSuggestionsForUrl(url)
            .map((id) => id.toString())
            .toList();
        final actual = handler.analyzeLinkForCategorySuggestionsForTest(url);
        expect(actual, expected, reason: 'Mismatch for URL: $url');
      }
    });

    test('returns empty list for invalid URL', () {
      final actual =
          handler.analyzeLinkForCategorySuggestionsForTest('not-a-url');
      expect(actual, isEmpty);
    });
  });
}
