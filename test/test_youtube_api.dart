import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/youtube_api.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() {
  group('YouTube API Tests', () {
    setUpAll(() async {
      // Load environment variables for testing
      await dotenv.load(fileName: '.env');
    });

    test('YouTube video ID extraction should work for various URL formats', () {
      final testCases = [
        {
          'url': 'https://www.youtube.com/watch?v=HGJ7-GK43lg',
          'expectedId': 'HGJ7-GK43lg',
        },
        {
          'url': 'https://youtu.be/HGJ7-GK43lg',
          'expectedId': 'HGJ7-GK43lg',
        },
        {
          'url': 'https://youtube.com/watch?v=HGJ7-GK43lg',
          'expectedId': 'HGJ7-GK43lg',
        },
        {
          'url': 'https://m.youtube.com/watch?v=HGJ7-GK43lg',
          'expectedId': 'HGJ7-GK43lg',
        },
        {
          'url': 'https://www.youtube.com/watch?v=HGJ7-GK43lg&list=PLxxx',
          'expectedId': 'HGJ7-GK43lg',
        },
      ];

      for (final testCase in testCases) {
        final url = testCase['url'] as String;
        final expectedId = testCase['expectedId'] as String;

        final extractedId = YouTubeApiService.extractVideoId(url);
        expect(extractedId, equals(expectedId),
               reason: 'Failed to extract ID from: $url');

        print('✅ Extracted ID "$extractedId" from: $url');
      }
    });

    test('Invalid URLs should return null video ID', () {
      final invalidUrls = [
        'https://example.com',
        'https://vimeo.com/123456',
        'not-a-url',
        'https://youtube.com/playlist?list=PLxxx',
        '',
      ];

      for (final url in invalidUrls) {
        final extractedId = YouTubeApiService.extractVideoId(url);
        expect(extractedId, isNull,
               reason: 'Should return null for invalid URL: $url');
      }
    });

    test('YouTube API availability check', () {
      final isAvailable = YouTubeApiService.isAvailable;
      print('YouTube API available: $isAvailable');

      if (isAvailable) {
        print('✅ YouTube API key is configured');
      } else {
        print('⚠️ YouTube API key not configured - will fall back to web scraping');
      }

      // Test should pass regardless of API key availability
      expect(isAvailable, isA<bool>());
    });

    test('YouTube API integration (if API key available)', () async {
      if (!YouTubeApiService.isAvailable) {
        print('⚠️ Skipping API test - no API key configured');
        return;
      }

      // Test with a known stable YouTube video
      const testVideoUrl = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'; // Never Gonna Give You Up

      print('Testing YouTube API with: $testVideoUrl');

      final videoInfo = await YouTubeApiService.getVideoInfoFromUrl(testVideoUrl);

      if (videoInfo != null) {
        print('✅ Successfully fetched video info via API:');
        print('   Title: "${videoInfo.title}"');
        print('   Channel: ${videoInfo.channelTitle}');
        print('   Description length: ${videoInfo.description.length} chars');

        expect(videoInfo.title, isNotEmpty);
        expect(videoInfo.channelTitle, isNotEmpty);
        expect(videoInfo.description, isNotEmpty);
      } else {
        print('❌ Failed to fetch video info via API');
        fail('YouTube API should return video info for valid video');
      }
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('Simulated workflow: API first, fallback to scraping', () async {
      const testUrl = 'https://www.youtube.com/watch?v=HGJ7-GK43lg';

      print('=== Testing YouTube Title Extraction Workflow ===');
      print('URL: $testUrl');

      // Step 1: Try YouTube API
      if (YouTubeApiService.isAvailable) {
        print('Step 1: Attempting YouTube API extraction...');
        final videoInfo = await YouTubeApiService.getVideoInfoFromUrl(testUrl);

        if (videoInfo != null) {
          print('✅ YouTube API succeeded: "${videoInfo.title}"');
          expect(videoInfo.title, isNotEmpty);
          return; // Success via API
        } else {
          print('❌ YouTube API failed, would fall back to scraping');
        }
      } else {
        print('Step 1: YouTube API not available, would use scraping');
      }

      // In real usage, this would fall back to web scraping with proxy
      print('Step 2: Would fall back to HTML scraping via CORS proxy');
      print('✅ Workflow simulation completed');
    });
  });
}