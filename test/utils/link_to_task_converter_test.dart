import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:meaning_to/utils/link_to_task_converter.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/utils/streaming_media_constants.dart';
import 'package:meaning_to/models/category.dart';

void main() {
  // Load .env file before all tests
  setUpAll(() async {
    try {
      await dotenv.load(fileName: '.env');
      print('✅ Test setup: .env file loaded successfully');
      if (dotenv.env['OMDB_API_KEY'] != null) {
        print('✅ Test setup: OMDb API key found in .env');
      } else {
        print('⚠️  Test setup: OMDb API key not found in .env');
      }
    } catch (e) {
      print('⚠️  Test setup: Could not load .env file: $e');
    }
  });

  group('LinkToTaskConverter Tests', () {
    // Note: These tests require network access and will hit actual URLs
    // In a production environment, you might want to mock the HTTP requests

    const testUserId = 'test-user-123';

    test('should process Tidal link and extract artist/work', () async {
      const tidalUrl = 'https://tidal.com/browse/album/251380836';

      final proposedTask = await LinkToTaskConverter.createProposedTaskFromLink(
        tidalUrl,
        testUserId,
      );

      print('✅ ProposedTask from Tidal link:');
      print('   Headline: "${proposedTask.headline}"');
      print('   Notes: "${proposedTask.notes}"');
      print('   Links: ${proposedTask.links}');
      print('   Synopsis: ${proposedTask.synopsis != null ? "present" : "null"}');
      print('   Suggested categories: ${proposedTask.suggestedCategoryOriginalIds}');

      // Should extract artist as headline
      expect(proposedTask.headline, isNotEmpty);
      expect(proposedTask.headline, isNot(contains('on TIDAL')));

      // Should extract work as notes
      expect(proposedTask.notes, isNotNull);
      expect(proposedTask.notes, isNotEmpty);

      // Should have exactly one link
      expect(proposedTask.links.length, 1);
      expect(proposedTask.links[0], contains(tidalUrl));
      expect(proposedTask.links[0], startsWith('<a href='));

      // Should suggest streaming media categories
      expect(proposedTask.suggestedCategoryOriginalIds, isNotEmpty);
      expect(
        proposedTask.suggestedCategoryOriginalIds,
        containsAll(STREAMING_MEDIA_CATEGORY_IDS),
      );
    });

    test('should process Tidal link with streaming category context', () async {
      const tidalUrl = 'https://tidal.com/browse/album/251380836';

      // Create a mock streaming category
      final streamingCategory = Category(
        id: 999,
        headline: 'Test Streaming Category',
        invitation: 'Test',
        ownerId: testUserId,
        createdAt: DateTime.now(),
        originalId: 54, // "Play a Favorite Record"
        isPrivate: false,
        tasksArePrivate: false,
      );

      final proposedTask = await LinkToTaskConverter.createProposedTaskFromLink(
        tidalUrl,
        testUserId,
        currentCategory: streamingCategory,
      );

      print('✅ ProposedTask from Tidal link with category context:');
      print('   Headline: "${proposedTask.headline}"');
      print('   Notes: "${proposedTask.notes}"');

      // Should extract artist and work
      expect(proposedTask.headline, isNotEmpty);
      expect(proposedTask.notes, isNotNull);
      expect(proposedTask.notes, isNotEmpty);
    });

    test('should process IMDb link and suggest movie/TV categories', () async {
      const imdbUrl = 'https://www.imdb.com/title/tt0111161/'; // The Shawshank Redemption

      final proposedTask = await LinkToTaskConverter.createProposedTaskFromLink(
        imdbUrl,
        testUserId,
      );

      print('✅ ProposedTask from IMDb link:');
      print('   Headline: "${proposedTask.headline}"');
      print('   Suggested categories: ${proposedTask.suggestedCategoryOriginalIds}');

      // Should have a headline
      expect(proposedTask.headline, isNotEmpty);

      // Should have exactly one link
      expect(proposedTask.links.length, 1);

      // Should suggest movie categories (1=movie, 2=TV)
      expect(proposedTask.suggestedCategoryOriginalIds, isNotEmpty);
      expect(proposedTask.suggestedCategoryOriginalIds, contains(1)); // Movie category
    });

    test('should extract exact details from Shawshank Redemption IMDb link', () async {
      const imdbUrl = 'https://www.imdb.com/title/tt0111161/';

      final proposedTask = await LinkToTaskConverter.createProposedTaskFromLink(
        imdbUrl,
        testUserId,
      );

      print('✅ ProposedTask from Shawshank Redemption IMDb link:');
      print('   Headline: "${proposedTask.headline}"');
      print('   Synopsis: "${proposedTask.synopsis?.substring(0, proposedTask.synopsis!.length > 50 ? 50 : proposedTask.synopsis!.length)}..."');
      print('   Suggested categories: ${proposedTask.suggestedCategoryOriginalIds}');

      // Should extract exactly "The Shawshank Redemption" as headline (without year or "- IMDb")
      expect(proposedTask.headline, equals('The Shawshank Redemption'));

      // Should have synopsis beginning with "A banker convicted" or "Chronicles"
      expect(proposedTask.synopsis, isNotNull);
      expect(proposedTask.synopsis, isNotEmpty);
      // OMDb API provides different plot than HTML scraping
      expect(proposedTask.synopsis!.startsWith('A banker convicted') ||
             proposedTask.synopsis!.startsWith('Chronicles'), isTrue);

      // Should suggest Movie category only [1] when OMDb API detects it as a movie
      // Falls back to [1, 2] if OMDb API is not configured
      expect(proposedTask.suggestedCategoryOriginalIds, anyOf(equals([1]), equals([1, 2])));

      // Should have exactly one link
      expect(proposedTask.links.length, 1);
      expect(proposedTask.links[0], contains(imdbUrl));
    });

    test('should detect TV series type from OMDb and suggest TV category only', () async {
      const imdbUrl = 'https://www.imdb.com/title/tt0903747/'; // Breaking Bad

      final proposedTask = await LinkToTaskConverter.createProposedTaskFromLink(
        imdbUrl,
        testUserId,
      );

      print('✅ ProposedTask from Breaking Bad IMDb link:');
      print('   Headline: "${proposedTask.headline}"');
      print('   Suggested categories: ${proposedTask.suggestedCategoryOriginalIds}');

      // Should extract clean headline
      expect(proposedTask.headline, equals('Breaking Bad'));

      // Should suggest TV category only [2] when OMDb API detects it as a series
      // Falls back to [1, 2] if OMDb API is not configured
      expect(proposedTask.suggestedCategoryOriginalIds, anyOf(equals([2]), equals([1, 2])));
    });

    test('should process JustWatch movie link', () async {
      const justwatchUrl = 'https://www.justwatch.com/us/movie/the-shawshank-redemption';

      final proposedTask = await LinkToTaskConverter.createProposedTaskFromLink(
        justwatchUrl,
        testUserId,
      );

      print('✅ ProposedTask from JustWatch movie link:');
      print('   Headline: "${proposedTask.headline}"');
      print('   Suggested categories: ${proposedTask.suggestedCategoryOriginalIds}');

      // Should have a headline
      expect(proposedTask.headline, isNotEmpty);

      // Should suggest only movie category
      expect(proposedTask.suggestedCategoryOriginalIds, contains(1)); // Movie
      expect(proposedTask.suggestedCategoryOriginalIds.length, 1); // Only movie
    });

    test('should process JustWatch TV show link', () async {
      const justwatchUrl = 'https://www.justwatch.com/us/tv-show/breaking-bad';

      final proposedTask = await LinkToTaskConverter.createProposedTaskFromLink(
        justwatchUrl,
        testUserId,
      );

      print('✅ ProposedTask from JustWatch TV link:');
      print('   Headline: "${proposedTask.headline}"');
      print('   Suggested categories: ${proposedTask.suggestedCategoryOriginalIds}');

      // Should have a headline
      expect(proposedTask.headline, isNotEmpty);

      // Should suggest only TV category
      expect(proposedTask.suggestedCategoryOriginalIds, contains(2)); // TV
      expect(proposedTask.suggestedCategoryOriginalIds.length, 1); // Only TV
    });

    test('should process Letterboxd link', () async {
      const letterboxdUrl = 'https://letterboxd.com/film/the-shawshank-redemption/';

      final proposedTask = await LinkToTaskConverter.createProposedTaskFromLink(
        letterboxdUrl,
        testUserId,
      );

      print('✅ ProposedTask from Letterboxd link:');
      print('   Headline: "${proposedTask.headline}"');
      print('   Synopsis: ${proposedTask.synopsis != null ? proposedTask.synopsis!.substring(0, proposedTask.synopsis!.length > 100 ? 100 : proposedTask.synopsis!.length) : "null"}');
      print('   Suggested categories: ${proposedTask.suggestedCategoryOriginalIds}');

      // Should have a headline
      expect(proposedTask.headline, isNotEmpty);

      // Should suggest movie categories
      expect(proposedTask.suggestedCategoryOriginalIds, contains(1)); // Movie

      // May have synopsis from Letterboxd
      // (This depends on successful fetching, so we just check it's not throwing errors)
    });

    test('should normalize URLs by removing tracking parameters', () async {
      const urlWithTracking = 'https://www.imdb.com/title/tt0111161/?utm_source=test&fbclid=abc123&ref=share';

      final proposedTask = await LinkToTaskConverter.createProposedTaskFromLink(
        urlWithTracking,
        testUserId,
      );

      print('✅ ProposedTask from URL with tracking params:');
      print('   Original URL: $urlWithTracking');
      print('   Link in task: ${proposedTask.links[0]}');

      // Should have removed tracking parameters
      expect(proposedTask.links[0], isNot(contains('utm_source=')),
        reason: 'Link should not contain utm_source parameter');
      expect(proposedTask.links[0], isNot(contains('fbclid=')),
        reason: 'Link should not contain fbclid parameter');
      expect(proposedTask.links[0], isNot(contains('?ref=')),
        reason: 'Link should not contain ?ref= parameter');
      expect(proposedTask.links[0], isNot(contains('&ref=')),
        reason: 'Link should not contain &ref= parameter');

      // The normalized URL should be clean
      expect(proposedTask.links[0], contains('href="https://www.imdb.com/title/tt0111161/"'),
        reason: 'Link should contain clean URL without parameters');
    });

    test('should process general URL with title extraction', () async {
      const generalUrl = 'https://www.example.com/article/test';

      final proposedTask = await LinkToTaskConverter.createProposedTaskFromLink(
        generalUrl,
        testUserId,
      );

      print('✅ ProposedTask from general URL:');
      print('   Headline: "${proposedTask.headline}"');
      print('   Suggested categories: ${proposedTask.suggestedCategoryOriginalIds}');

      // Should have a headline (even if it's just a fallback)
      expect(proposedTask.headline, isNotEmpty);

      // Should have exactly one link
      expect(proposedTask.links.length, 1);

      // May not suggest any specific categories
      // (This is fine for general links)
    });

    test('should handle URL normalization in HTML link format', () async {
      const htmlLink = '<a href="https://www.imdb.com/title/tt0111161/">The Shawshank Redemption</a>';

      final proposedTask = await LinkToTaskConverter.createProposedTaskFromLink(
        htmlLink,
        testUserId,
      );

      print('✅ ProposedTask from HTML link format:');
      print('   Headline: "${proposedTask.headline}"');

      // Should extract and process the URL from the HTML link
      expect(proposedTask.headline, isNotEmpty);
      expect(proposedTask.links[0], contains('imdb.com'));
    });
  });

  group('LinkProcessor UI Display Tests', () {
    test('should clean IMDb movie title for UI display', () async {
      const imdbUrl = 'https://www.imdb.com/title/tt0111161/';

      final processed = await LinkProcessor.processLinkForDisplay(imdbUrl);

      print('✅ Processed IMDb movie for UI:');
      print('   Title: "${processed.title}"');

      // Should have clean title without year or "- IMDb"
      expect(processed.title, equals('The Shawshank Redemption'));
      expect(processed.title, isNot(contains('1994')));
      expect(processed.title, isNot(contains('IMDb')));
    });

    test('should clean IMDb TV series title for UI display', () async {
      const imdbUrl = 'https://www.imdb.com/title/tt0903747/';

      final processed = await LinkProcessor.processLinkForDisplay(imdbUrl);

      print('✅ Processed IMDb TV series for UI:');
      print('   Title: "${processed.title}"');

      // Should have clean title without year range, "TV Series", or "- IMDb"
      expect(processed.title, equals('Breaking Bad'));
      expect(processed.title, isNot(contains('2008')));
      expect(processed.title, isNot(contains('2013')));
      expect(processed.title, isNot(contains('TV Series')));
      expect(processed.title, isNot(contains('IMDb')));
    });

    test('should clean IMDb title variations including "Reference view"', () {
      // Test direct method call with various IMDb title formats

      // Test "- Reference view" suffix
      expect(
        LinkProcessor.cleanImdbTitle('The Shawshank Redemption (1994) - Reference view'),
        equals('The Shawshank Redemption'),
      );

      // Test "- IMDb" suffix
      expect(
        LinkProcessor.cleanImdbTitle('The Shawshank Redemption (1994) - IMDb'),
        equals('The Shawshank Redemption'),
      );

      // Test TV Series with Reference view
      expect(
        LinkProcessor.cleanImdbTitle('Breaking Bad (TV Series 2008–2013) - Reference view'),
        equals('Breaking Bad'),
      );

      // Test just year removal
      expect(
        LinkProcessor.cleanImdbTitle('Inception (2010)'),
        equals('Inception'),
      );

      print('✅ All IMDb title variations cleaned correctly');
    });
  });

  group('LinkToTaskConverter Category Suggestion Tests', () {
    test('should suggest correct categories for different link types', () {
      final testCases = [
        {
          'url': 'https://www.imdb.com/title/tt0111161/',
          'expected': [1, 2], // Movie, TV
          'description': 'IMDb title'
        },
        {
          'url': 'https://www.imdb.com/title/tt0903747/', // Breaking Bad
          'expected': [1, 2], // Movie first, TV second (general title)
          'description': 'IMDb title (general)'
        },
        {
          'url': 'https://letterboxd.com/film/the-shawshank-redemption/',
          'expected': [1, 2], // Movie, TV
          'description': 'Letterboxd film'
        },
        {
          'url': 'https://www.justwatch.com/us/movie/inception',
          'expected': [1], // Movie only
          'description': 'JustWatch movie'
        },
        {
          'url': 'https://www.justwatch.com/us/tv-show/the-office',
          'expected': [2], // TV only
          'description': 'JustWatch TV show'
        },
        {
          'url': 'https://tidal.com/browse/album/123',
          'expected': STREAMING_MEDIA_CATEGORY_IDS.toList(), // Streaming categories
          'description': 'Tidal album'
        },
      ];

      for (final testCase in testCases) {
        final suggestions = LinkToTaskConverter.analyzeLinkForCategorySuggestions(
          testCase['url'] as String
        );

        print('Testing ${testCase['description']}: ${testCase['url']}');
        print('  Expected: ${testCase['expected']}');
        print('  Got: $suggestions');

        expect(
          suggestions,
          equals(testCase['expected']),
          reason: 'Failed for ${testCase['description']}',
        );
      }

      print('✅ All category suggestion tests passed!');
    });
  });
}
