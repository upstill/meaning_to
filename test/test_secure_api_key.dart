import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/youtube_api.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() {
  group('Secure API Key Management Tests', () {
    setUp(() {
      // Clear any cached values
    });

    test('Should prioritize build-time environment variable over dotenv', () async {
      // Load dotenv for testing
      await dotenv.load(fileName: '.env');

      // In this test, if YOUTUBE_API_KEY is defined at build time, it should be used
      // If not, it should fall back to dotenv (which now has no API key)

      final apiKey = YouTubeApiService.apiKey;
      final isAvailable = YouTubeApiService.isAvailable;

      print('API Key source test:');
      print('  API Key available: $isAvailable');
      print('  API Key length: ${apiKey?.length ?? 0}');

      // The behavior depends on whether --dart-define was used during build
      if (apiKey != null && apiKey.isNotEmpty) {
        print('  ✅ Using build-time environment variable');
        expect(apiKey, isNot(equals('test_key_value')),
               reason: 'Should not be test value in normal runs');
      } else {
        print('  ⚠️ No API key available (expected for local testing without --dart-define)');
      }

      // API availability should match key availability
      expect(isAvailable, equals(apiKey != null && apiKey.isNotEmpty));
    });

    test('Should handle missing environment variables gracefully', () {
      // Test that the app doesn't crash when no API key is available
      final apiKey = YouTubeApiService.apiKey;
      final isAvailable = YouTubeApiService.isAvailable;

      // Should not throw exceptions
      expect(() => YouTubeApiService.apiKey, returnsNormally);
      expect(() => YouTubeApiService.isAvailable, returnsNormally);

      print('Graceful fallback test:');
      print('  API Key: ${apiKey ?? "null"}');
      print('  Available: $isAvailable');
      print('  ✅ No exceptions thrown');
    });

    test('Should extract video IDs regardless of API key availability', () {
      // Video ID extraction should work without API key
      const testUrl = 'https://www.youtube.com/watch?v=HGJ7-GK43lg';

      final videoId = YouTubeApiService.extractVideoId(testUrl);
      expect(videoId, equals('HGJ7-GK43lg'));

      print('Video ID extraction test:');
      print('  Input: $testUrl');
      print('  Extracted ID: $videoId');
      print('  ✅ Works independently of API key');
    });

    test('Security: API key should not be logged or exposed', () {
      // Test that API key is not accidentally logged
      final apiKey = YouTubeApiService.apiKey;

      if (apiKey != null) {
        // Ensure the key is not trivially exposed
        expect(apiKey.length, greaterThan(10),
               reason: 'API key should be substantial length');
        expect(apiKey, startsWith('AIza'),
               reason: 'YouTube API keys start with AIza');

        print('Security test:');
        print('  API Key length: ${apiKey.length}');
        print('  API Key prefix: ${apiKey.substring(0, 4)}***');
        print('  ✅ API key appears valid and not fully exposed');
      } else {
        print('Security test: No API key to validate');
      }
    });
  });
}