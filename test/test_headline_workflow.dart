import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() {
  group('Headline Auto-Population Workflow', () {
    setUpAll(() async {
      // Load environment variables for testing
      await dotenv.load(fileName: '.env');
    });

    test('YouTube link with generic "Watch" title should fetch from webpage', () async {
      // This simulates what happens when LinkEditScreen returns a YouTube link with generic title
      final htmlLink = '<a href="https://www.youtube.com/watch?v=qd1RXxf2LsQ">Watch</a>';

      print('=== Testing Headline Population Workflow ===');
      print('Input HTML link: $htmlLink');

      // Step 1: Extract title from HTML link
      final (url, linkTitle) = LinkProcessor.parseHtmlLink(htmlLink);
      print('Extracted URL: $url');
      print('Extracted link title: "$linkTitle"');

      // Step 2: Check if title is useful (this is our new logic)
      bool isUsefulTitle(String title) {
        final genericTitles = {'Watch', 'Click here', 'Link', 'More', 'Read more', 'Continue', 'View', 'See more', 'Details'};
        if (genericTitles.contains(title)) return false;
        if (title.startsWith('http')) return false;
        if (title.length < 3) return false;
        return true;
      }

      final titleIsUseful = linkTitle != null && isUsefulTitle(linkTitle);
      print('Title is useful: $titleIsUseful');

      if (!titleIsUseful) {
        print('Generic title rejected, fetching from webpage...');

        // Step 3: Fetch actual title from YouTube webpage
        final content = await LinkProcessor.fetchWebpageContent(url);

        if (content != null && content.title.isNotEmpty) {
          print('✅ Successfully fetched title from webpage: "${content.title}"');

          // This should be the YouTube video title
          expect(content.title, equals('Fleetwood Mac - Rumours, if it was recorded in the 50s'));
          expect(content.description, isNotNull);
          expect(content.description!, startsWith('⚠️ IMPORTANT DISCLAIMER ⚠️'));
        } else {
          fail('Failed to fetch content from YouTube webpage');
        }
      } else {
        fail('Generic "Watch" title should not be considered useful');
      }
    });

    test('Meaningful title should be used directly without webpage fetch', () {
      final htmlLink = '<a href="https://www.youtube.com/watch?v=abc">Fleetwood Mac - Rumours</a>';

      print('\n=== Testing Meaningful Title Workflow ===');
      print('Input HTML link: $htmlLink');

      final (url, linkTitle) = LinkProcessor.parseHtmlLink(htmlLink);
      print('Extracted URL: $url');
      print('Extracted link title: "$linkTitle"');

      // Check if title is useful
      bool isUsefulTitle(String title) {
        final genericTitles = {'Watch', 'Click here', 'Link', 'More', 'Read more', 'Continue', 'View', 'See more', 'Details'};
        if (genericTitles.contains(title)) return false;
        if (title.startsWith('http')) return false;
        if (title.length < 3) return false;
        return true;
      }

      final titleIsUseful = linkTitle != null && isUsefulTitle(linkTitle);
      print('Title is useful: $titleIsUseful');

      if (titleIsUseful) {
        print('✅ Using meaningful title directly: "$linkTitle"');
        expect(linkTitle, equals('Fleetwood Mac - Rumours'));
      } else {
        fail('Meaningful title should be considered useful');
      }
    });
  });
}