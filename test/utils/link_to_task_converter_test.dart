import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:meaning_to/utils/link_to_task_converter.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/utils/streaming_media_constants.dart';
import 'package:meaning_to/models/category.dart';

void main() {
  // Test user ID used across all tests
  const testUserId = 'test-user-123';

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

      // Should have a non-empty headline
      expect(proposedTask.headline, isNotEmpty);
      // Note: notes may be null if TIDAL returns HTTP 403 for /browse/album/ URLs
      // (these URLs require authentication; canonical /album/ URLs work reliably)

      // Should have exactly one link
      expect(proposedTask.links.length, 1);
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

      // Should have a non-empty headline
      // Note: notes may be null if TIDAL returns HTTP 403 for /browse/album/ URLs
      expect(proposedTask.headline, isNotEmpty);
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

    test('should process Spotify playlist link with query parameters', () async {
      const spotifyUrl = 'https://open.spotify.com/playlist/60iEsOOYsvriP3l7gBdyzW?si=tk35MI51QKO6Ypk1yjRPxQ';

      final proposedTask = await LinkToTaskConverter.createProposedTaskFromLink(
        spotifyUrl,
        testUserId,
      );

      print('✅ ProposedTask from Spotify playlist link:');
      print('   Headline: "${proposedTask.headline}"');
      print('   Notes: "${proposedTask.notes}"');
      print('   Links: ${proposedTask.links}');
      print('   Suggested categories: ${proposedTask.suggestedCategoryOriginalIds}');

      // Should extract playlist name as headline (Spotify API returns with extra space)
      expect(proposedTask.headline, equals('Anassa  Dinner'));

      // Should have null notes for playlists
      expect(proposedTask.notes, isNull);

      // Should have exactly one link with text containing the playlist name
      expect(proposedTask.links.length, 1);
      expect(proposedTask.links[0], contains('Anassa  Dinner'));

      // Link should not contain query parameters
      expect(proposedTask.links[0], isNot(contains('si=')));
      expect(proposedTask.links[0], contains('href="https://open.spotify.com/playlist/60iEsOOYsvriP3l7gBdyzW"'));

      // Should suggest streaming media categories
      expect(proposedTask.suggestedCategoryOriginalIds, isNotEmpty);
      expect(
        proposedTask.suggestedCategoryOriginalIds,
        containsAll(STREAMING_MEDIA_CATEGORY_IDS),
      );
    });

    test('should process Spotify album link', () async {
      const spotifyUrl = 'https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy';

      final proposedTask = await LinkToTaskConverter.createProposedTaskFromLink(
        spotifyUrl,
        testUserId,
      );

      print('✅ ProposedTask from Spotify album link:');
      print('   Headline: "${proposedTask.headline}"');
      print('   Notes: "${proposedTask.notes}"');
      print('   Links: ${proposedTask.links}');
      print('   Suggested categories: ${proposedTask.suggestedCategoryOriginalIds}');

      // Should extract artist as headline
      expect(proposedTask.headline, equals('Pitbull'));

      // Should extract album title as notes
      expect(proposedTask.notes, equals('Global Warming'));

      // Should have exactly one link with text containing the album name
      // (link text is the raw page title, e.g. "Global Warming - album by Pitbull | Spotify")
      expect(proposedTask.links.length, 1);
      expect(proposedTask.links[0], contains('Global Warming'));
      expect(proposedTask.links[0], contains('href="https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy"'));

      // Should suggest streaming media categories
      expect(proposedTask.suggestedCategoryOriginalIds, isNotEmpty);
      expect(
        proposedTask.suggestedCategoryOriginalIds,
        containsAll(STREAMING_MEDIA_CATEGORY_IDS),
      );
    });

    test('should process Spotify track link with query parameters', () async {
      const spotifyUrl = 'https://open.spotify.com/track/292kifgxa7S78AuzA5NMpL?si=43b468ec44d74587';

      final proposedTask = await LinkToTaskConverter.createProposedTaskFromLink(
        spotifyUrl,
        testUserId,
      );

      print('✅ ProposedTask from Spotify track link:');
      print('   Headline: "${proposedTask.headline}"');
      print('   Notes: "${proposedTask.notes}"');
      print('   Links: ${proposedTask.links}');
      print('   Suggested categories: ${proposedTask.suggestedCategoryOriginalIds}');

      // Spotify track titles may not include "song and lyrics by" artist info,
      // so artist extraction may not succeed — headline is the track name in that case
      expect(proposedTask.headline, equals('Global Warming (feat. Sensato)'));

      // Notes are null when artist extraction is not available for tracks
      expect(proposedTask.notes, isNull);

      // Should have exactly one link with text containing the track name
      expect(proposedTask.links.length, 1);
      expect(proposedTask.links[0], contains('Global Warming (feat. Sensato)'));

      // Link should not contain query parameters
      expect(proposedTask.links[0], isNot(contains('si=')));
      expect(proposedTask.links[0], contains('href="https://open.spotify.com/track/292kifgxa7S78AuzA5NMpL"'));

      // Should suggest streaming media categories
      expect(proposedTask.suggestedCategoryOriginalIds, isNotEmpty);
      expect(
        proposedTask.suggestedCategoryOriginalIds,
        containsAll(STREAMING_MEDIA_CATEGORY_IDS),
      );
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
          'expected': [1], // Movie only (Letterboxd /film/ paths are definitively movies)
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
        {
          'url': 'https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy',
          'expected': [54, 41, 74], // Streaming categories
          'description': 'Spotify album'
        },
        {
          'url': 'https://open.spotify.com/playlist/60iEsOOYsvriP3l7gBdyzW',
          'expected': [54, 41, 74], // Streaming categories
          'description': 'Spotify playlist'
        },
        {
          'url': 'https://open.spotify.com/track/292kifgxa7S78AuzA5NMpL',
          'expected': [54, 41, 74], // Streaming categories
          'description': 'Spotify track'
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

  group('LinkToTaskConverter TSV Data Tests', () {
    test('should process links according to TSV test data', () async {
      // Read the TSV file
      final tsvFile = File('test/utils/link_to_task_test_data.tsv');

      if (!await tsvFile.exists()) {
        print('⚠️  TSV test data file not found at: ${tsvFile.path}');
        print('   Skipping TSV data tests');
        return;
      }

      final lines = await tsvFile.readAsLines();

      // Skip the header line
      if (lines.isEmpty) {
        print('⚠️  TSV file is empty');
        return;
      }

      final header = lines[0].split('\t');
      print('✅ Found TSV with headers: $header');

      // Check if a specific test line was requested via --dart-define=TEST_LINE=N
      const testLineParam = String.fromEnvironment('TEST_LINE');
      final specificLine = testLineParam.isEmpty ? null : int.tryParse(testLineParam);

      if (specificLine != null) {
        if (specificLine < 1 || specificLine >= lines.length) {
          print('❌ TEST_LINE=$specificLine is out of range (1-${lines.length - 1})');
          fail('TEST_LINE out of range');
        }
        print('   Testing only line $specificLine...\n');
      } else {
        print('   Processing ${lines.length - 1} test cases...\n');
      }

      // Unescape a single TSV field that may use CSV-style quoting:
      // surrounding double-quotes are stripped and doubled internal quotes
      // ("") are replaced with a single quote (").
      String unquote(String field) {
        final t = field.trim();
        if (t.startsWith('"') && t.endsWith('"') && t.length >= 2) {
          return t.substring(1, t.length - 1).replaceAll('""', '"');
        }
        return t;
      }

      // Process each test case
      final failures = <String>[];
      for (int i = 1; i < lines.length; i++) {
        // If a specific line was requested, skip all others
        if (specificLine != null && i != specificLine) continue;

        final line = lines[i].trim();
        if (line.isEmpty) continue;

        // Split on tabs then unescape any CSV-quoted fields
        final fields = line.split('\t').map(unquote).toList();

        // Pad fields with empty strings if there are fewer than 7 fields
        while (fields.length < 7) {
          fields.add('');
        }

        final linkIn = fields[0];
        final linkOut = fields[1];
        final expectedHeadline = fields[2];
        final expectedNotes = fields[3];
        final expectedLinkText = fields[4];
        final expectedCategoryIds = fields[5];
        final expectedSynopsisStart = fields[6];

        print('Test case ${i}: $linkIn');

        try {
          final proposedTask = await LinkToTaskConverter.createProposedTaskFromLink(
            linkIn,
            testUserId,
          );

          // Test headline
          expect(
            proposedTask.headline,
            equals(expectedHeadline),
            reason: 'Headline mismatch for $linkIn',
          );
          print('  ✅ Headline: "${proposedTask.headline}"');

          // Test notes (handle null and empty string)
          if (expectedNotes.isEmpty || expectedNotes.toLowerCase() == 'null') {
            expect(
              proposedTask.notes,
              isNull,
              reason: 'Notes should be null for $linkIn',
            );
            print('  ✅ Notes: null');
          } else {
            expect(
              proposedTask.notes,
              equals(expectedNotes),
              reason: 'Notes mismatch for $linkIn',
            );
            print('  ✅ Notes: "${proposedTask.notes}"');
          }

          // Test link text
          expect(
            proposedTask.links.length,
            equals(1),
            reason: 'Should have exactly one link for $linkIn',
          );
          expect(
            proposedTask.links[0],
            contains(expectedLinkText),
            reason: 'Link text mismatch for $linkIn',
          );
          print('  ✅ Link text contains: "$expectedLinkText"');

          // Test normalized link URL
          if (linkOut.isNotEmpty) {
            expect(
              proposedTask.links[0],
              contains('href="$linkOut"'),
              reason: 'Normalized URL mismatch for $linkIn',
            );
            print('  ✅ Normalized URL: $linkOut');
          }

          // Test category IDs
          if (expectedCategoryIds.isNotEmpty && expectedCategoryIds.toLowerCase() != 'null') {
            // Remove surrounding quotes if present
            final cleanedCategoryIds = expectedCategoryIds.replaceAll('"', '').trim();
            final expectedIds = cleanedCategoryIds
                .split(',')
                .map((s) => int.parse(s.trim()))
                .toList();
            expect(
              proposedTask.suggestedCategoryOriginalIds,
              equals(expectedIds),
              reason: 'Category IDs mismatch for $linkIn',
            );
            print('  ✅ Category IDs: ${proposedTask.suggestedCategoryOriginalIds}');
          }

          // Test synopsis (just check it starts with the expected value)
          if (expectedSynopsisStart.isNotEmpty && expectedSynopsisStart.toLowerCase() != 'null') {
            expect(
              proposedTask.synopsis,
              isNotNull,
              reason: 'Synopsis should not be null for $linkIn',
            );
            expect(
              proposedTask.synopsis,
              startsWith(expectedSynopsisStart),
              reason: 'Synopsis should start with "$expectedSynopsisStart" for $linkIn',
            );
            print('  ✅ Synopsis starts with: "${expectedSynopsisStart.substring(0, expectedSynopsisStart.length > 50 ? 50 : expectedSynopsisStart.length)}..."');
          }

          print('  ✅ Test case $i passed\n');
        } catch (e) {
          print('  ❌ Test case $i failed: $e\n');
          failures.add('Line $i ($linkIn): $e');
        }
      }

      if (failures.isNotEmpty) {
        fail('${failures.length} TSV test case(s) failed:\n${failures.join('\n\n')}');
      }
      print('✅ All TSV test cases passed!');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
