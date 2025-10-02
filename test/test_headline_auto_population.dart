import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/link_processor.dart';

void main() {
  group('Headline Auto-Population Tests', () {
    test('parseHtmlLink should extract title from HTML link', () {
      // Test with various HTML link formats
      final testCases = [
        {
          'input': '<a href="https://www.youtube.com/watch?v=qd1RXxf2LsQ">Fleetwood Mac - Rumours, if it was recorded in the 50s</a>',
          'expectedUrl': 'https://www.youtube.com/watch?v=qd1RXxf2LsQ',
          'expectedTitle': 'Fleetwood Mac - Rumours, if it was recorded in the 50s',
        },
        {
          'input': '<a href="https://www.justwatch.com/us/movie/nine-queens">Nine Queens</a>',
          'expectedUrl': 'https://www.justwatch.com/us/movie/nine-queens',
          'expectedTitle': 'Nine Queens',
        },
        {
          'input': '<a href="https://example.com/test"></a>',
          'expectedUrl': 'https://example.com/test',
          'expectedTitle': null,
        },
        {
          'input': 'https://plain-url.com',
          'expectedUrl': 'https://plain-url.com',
          'expectedTitle': null,
        },
      ];

      for (final testCase in testCases) {
        print('\n--- Testing: ${testCase['input']} ---');

        final (url, title) = LinkProcessor.parseHtmlLink(testCase['input'] as String);

        print('Extracted URL: "$url"');
        print('Extracted title: "$title"');

        expect(url, equals(testCase['expectedUrl']),
               reason: 'URL should match for input: ${testCase['input']}');
        expect(title, equals(testCase['expectedTitle']),
               reason: 'Title should match for input: ${testCase['input']}');
      }
    });

    test('isValidUrl should validate URLs correctly', () {
      final validUrls = [
        'https://www.youtube.com/watch?v=qd1RXxf2LsQ',
        'https://www.justwatch.com/us/movie/nine-queens',
        'http://example.com',
        'https://letterboxd.com/film/phantom-thread/',
      ];

      final invalidUrls = [
        'not-a-url',
        'just text',
        '',
        'no-scheme.com',
      ];

      for (final url in validUrls) {
        expect(LinkProcessor.isValidUrl(url), isTrue,
               reason: 'Should be valid: $url');
      }

      for (final url in invalidUrls) {
        expect(LinkProcessor.isValidUrl(url), isFalse,
               reason: 'Should be invalid: $url');
      }
    });

    test('Simulated headline population workflow', () async {
      // Simulate the workflow that would happen in TaskEditScreen

      // Case 1: HTML link with title should use that title
      final htmlLinkWithTitle = '<a href="https://www.youtube.com/watch?v=qd1RXxf2LsQ">Fleetwood Mac - Rumours, if it was recorded in the 50s</a>';
      final (url1, title1) = LinkProcessor.parseHtmlLink(htmlLinkWithTitle);

      print('Case 1 - HTML link with title:');
      print('  URL: $url1');
      print('  Title: $title1');

      expect(title1, isNotNull, reason: 'Should extract title from HTML link');
      expect(title1, equals('Fleetwood Mac - Rumours, if it was recorded in the 50s'));

      // Case 2: HTML link without title should fetch from webpage
      final htmlLinkWithoutTitle = '<a href="https://www.youtube.com/watch?v=qd1RXxf2LsQ"></a>';
      final (url2, title2) = LinkProcessor.parseHtmlLink(htmlLinkWithoutTitle);

      print('\nCase 2 - HTML link without title:');
      print('  URL: $url2');
      print('  Title: $title2');

      expect(title2, isNull, reason: 'Should not extract title from empty HTML link');
      expect(LinkProcessor.isValidUrl(url2), isTrue, reason: 'Should extract valid URL');

      // In this case, TaskEditScreen would call fetchWebpageContent(url2)
      print('  Would fetch title from webpage for: $url2');
    });
  });
}