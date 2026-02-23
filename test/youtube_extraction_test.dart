import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/link_processor.dart';

void main() {
  group('YouTube Content Extraction Tests', () {
    test('Extract title and description from YouTube URL', () async {
      final url = 'https://www.youtube.com/watch?v=qd1RXxf2LsQ';

      print('Testing YouTube URL: $url');

      final content = await LinkProcessor.fetchWebpageContent(url);

      expect(content, isNotNull, reason: 'Should fetch content from YouTube URL');

      if (content != null) {
        print('Extracted title: "${content.title}"');
        print('Extracted description: "${content.description?.substring(0, content.description!.length > 100 ? 100 : content.description!.length)}..."');

        // Test the expected title
        expect(
          content.title,
          equals('Fleetwood Mac - Rumours, if it was recorded in the 50s'),
          reason: 'Should extract the correct YouTube video title'
        );

        // Test the description starts with the expected disclaimer
        expect(
          content.description,
          isNotNull,
          reason: 'Should extract description from YouTube video'
        );

        expect(
          content.description!.startsWith('⚠️ IMPORTANT DISCLAIMER ⚠️'),
          isTrue,
          reason: 'Description should start with the expected disclaimer text'
        );
      }
    });
  });
}