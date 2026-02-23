import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/utils/youtube_api.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() {
  group('Async Initialization Tests', () {
    test('YouTube API handles uninitialized environment gracefully', () {
      // Simulate uninitialized environment (don't load dotenv)

      // YouTube API should handle this gracefully
      final isAvailable = YouTubeApiService.isAvailable;
      expect(isAvailable, isFalse, reason: 'Should be false when environment not initialized');

      // API key access should not throw, should return null
      final apiKey = YouTubeApiService.apiKey;
      expect(apiKey, isNull, reason: 'Should return null when environment not accessible');
    });

    test('Link processing workflow with delayed environment initialization', () async {
      // Simulate the scenario where link processing happens before dotenv is ready

      print('=== Testing Async Environment Initialization ===');

      // Start with uninitialized environment
      expect(YouTubeApiService.isAvailable, isFalse);

      // Simulate link processing that would fail initially
      const testUrl = 'https://www.youtube.com/watch?v=HGJ7-GK43lg';

      // This should handle the uninitialized environment gracefully
      var content = await LinkProcessor.fetchWebpageContent(testUrl);
      print('Content fetch without environment: ${content != null ? "succeeded" : "failed"}');

      // Now initialize environment (simulating delayed initialization)
      await dotenv.load(fileName: '.env');
      print('Environment loaded');

      // Now the API should be available
      expect(YouTubeApiService.isAvailable, isTrue);

      // And content fetching should work via API
      content = await LinkProcessor.fetchWebpageContent(testUrl);
      print('Content fetch with environment: ${content != null ? "succeeded" : "failed"}');

      if (content != null) {
        print('Successfully fetched title: "${content.title}"');
        expect(content.title, isNotEmpty);
      }
    });

    test('YouTube video ID extraction works regardless of environment state', () {
      // Video ID extraction should work even without environment initialization
      const testUrl = 'https://www.youtube.com/watch?v=HGJ7-GK43lg';

      final videoId = YouTubeApiService.extractVideoId(testUrl);
      expect(videoId, equals('HGJ7-GK43lg'));

      print('✅ Video ID extraction works independently of environment');
    });

    test('Simulated app startup race condition', () async {
      // Simulate what happens during app startup when multiple operations happen concurrently

      print('=== Simulating App Startup Race Condition ===');

      // Clear any existing environment (simulate fresh start)
      // Note: In real app, this would be the initial state

      const testUrl = 'https://www.youtube.com/watch?v=HGJ7-GK43lg';

      // Simulate concurrent operations during app startup
      final futures = <Future>[];

      // Simulate link processing happening immediately
      futures.add(LinkProcessor.fetchWebpageContent(testUrl).then((content) {
        print('Immediate fetch result: ${content?.title ?? "null"}');
        return content;
      }));

      // Simulate environment loading (delayed)
      futures.add(Future.delayed(const Duration(milliseconds: 200)).then((_) async {
        await dotenv.load(fileName: '.env');
        print('Environment loaded after delay');
      }));

      // Simulate another link processing after a delay
      futures.add(Future.delayed(const Duration(milliseconds: 500)).then((_) async {
        final content = await LinkProcessor.fetchWebpageContent(testUrl);
        print('Delayed fetch result: ${content?.title ?? "null"}');
        return content;
      }));

      await Future.wait(futures);

      print('✅ Race condition simulation completed');
    });
  });
}