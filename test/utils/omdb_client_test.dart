import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/omdb_client.dart';

void main() {
  group('OmdbFilmInfo.fromJson', () {
    test('parses a full successful response', () {
      final info = OmdbFilmInfo.fromJson({
        'Title': 'The Shawshank Redemption',
        'Year': '1994',
        'Plot': 'Two imprisoned men bond over a number of years.',
        'Poster': 'https://example.com/poster.jpg',
        'imdbID': 'tt0111161',
        'imdbRating': '9.3',
        'Type': 'movie',
        'Response': 'True',
      });

      expect(info.title, 'The Shawshank Redemption');
      expect(info.year, '1994');
      expect(info.plot, 'Two imprisoned men bond over a number of years.');
      expect(info.posterUrl, 'https://example.com/poster.jpg');
      expect(info.imdbId, 'tt0111161');
      expect(info.imdbRating, '9.3');
      expect(info.type, 'movie');
    });

    test('treats OMDb "N/A" values as null', () {
      final info = OmdbFilmInfo.fromJson({
        'Title': 'Some Obscure Film',
        'Year': '2001',
        'Plot': 'N/A',
        'Poster': 'N/A',
        'imdbID': 'tt1234567',
        'imdbRating': 'N/A',
        'Type': 'movie',
      });

      expect(info.title, 'Some Obscure Film');
      expect(info.plot, isNull);
      expect(info.posterUrl, isNull);
      expect(info.imdbRating, isNull);
    });

    test('treats empty strings as null and defaults a missing title', () {
      final info = OmdbFilmInfo.fromJson({
        'Plot': '   ',
      });

      expect(info.title, 'Unknown Title');
      expect(info.plot, isNull);
      expect(info.year, isNull);
      expect(info.imdbId, isNull);
    });
  });
}
