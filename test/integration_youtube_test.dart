import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:http/http.dart' as http;

void main() {
  group('YouTube Integration Tests', () {
    test('Test direct vs proxy URL access', () async {
      final url = 'https://www.youtube.com/watch?v=qd1RXxf2LsQ';
      final proxyUrl = 'https://api.allorigins.win/raw?url=${Uri.encodeComponent(url)}';

      print('Testing YouTube URL extraction approaches...');
      print('Original URL: $url');
      print('Proxy URL: $proxyUrl');

      // Test direct access (this might fail in web environments)
      try {
        print('\n--- Testing Direct Access ---');
        final directResponse = await http.get(Uri.parse(url)).timeout(Duration(seconds: 5));
        print('Direct access status: ${directResponse.statusCode}');
        print('Direct access response length: ${directResponse.body.length}');
      } catch (e) {
        print('Direct access failed (expected in web): $e');
      }

      // Test proxy access (this should work)
      try {
        print('\n--- Testing Proxy Access ---');
        final proxyResponse = await http.get(Uri.parse(proxyUrl)).timeout(Duration(seconds: 10));
        print('Proxy access status: ${proxyResponse.statusCode}');
        print('Proxy access response length: ${proxyResponse.body.length}');

        if (proxyResponse.statusCode == 200) {
          // Quick check for YouTube content
          final hasTitle = proxyResponse.body.contains('<title>');
          final hasYouTube = proxyResponse.body.contains('YouTube');
          print('Response contains <title>: $hasTitle');
          print('Response contains "YouTube": $hasYouTube');
        }
      } catch (e) {
        print('Proxy access failed: $e');
      }

      print('\n--- Testing LinkProcessor Integration ---');
      try {
        final content = await LinkProcessor.fetchWebpageContent(url);
        if (content != null) {
          print('LinkProcessor extracted title: "${content.title}"');
          print('LinkProcessor extracted description: "${content.description?.substring(0, content.description!.length > 100 ? 100 : content.description!.length)}..."');
        } else {
          print('LinkProcessor failed to extract content');
        }
      } catch (e) {
        print('LinkProcessor error: $e');
      }
    });
  });
}