import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

void main() {
  group('Test Multiple Proxy Services', () {
    test('Test all proxy services for YouTube', () async {
      const url = 'https://www.youtube.com/watch?v=qd1RXxf2LsQ';

      final proxyUrls = [
        'https://api.allorigins.win/raw?url=${Uri.encodeComponent(url)}',
        'https://corsproxy.io/?${Uri.encodeComponent(url)}',
        'https://cors-anywhere.herokuapp.com/$url',
      ];

      for (int i = 0; i < proxyUrls.length; i++) {
        final proxyUrl = proxyUrls[i];
        final proxyName = [
          'allorigins.win',
          'corsproxy.io',
          'cors-anywhere.herokuapp.com'
        ][i];

        print('\n=== Testing $proxyName ===');
        print('Proxy URL: $proxyUrl');

        try {
          final response = await http.get(
            Uri.parse(proxyUrl),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
            },
          ).timeout(const Duration(seconds: 10));

          print('Status: ${response.statusCode}');
          print('Content length: ${response.body.length}');

          if (response.statusCode == 200 && response.body.length > 1000) {
            // Parse and check for content
            final document = html_parser.parse(response.body);

            final titleElement = document.querySelector('title');
            final metaTitle = document.querySelector('meta[name="title"]');
            final ogTitle = document.querySelector('meta[property="og:title"]');

            print('Title tag: ${titleElement?.text ?? "NOT FOUND"}');
            print(
                'Meta title: ${metaTitle?.attributes["content"] ?? "NOT FOUND"}');
            print('OG title: ${ogTitle?.attributes["content"] ?? "NOT FOUND"}');

            // Check for expected content
            final hasFleetwood = response.body.contains('Fleetwood Mac');
            final hasRumours = response.body.contains('Rumours');
            print('Contains "Fleetwood Mac": $hasFleetwood');
            print('Contains "Rumours": $hasRumours');

            if (hasFleetwood || hasRumours) {
              print('✅ This proxy returned YouTube content!');
            }
          } else {
            print('❌ Bad response or too small content');
            if (response.body.length < 100) {
              print('Response body: "${response.body}"');
            }
          }
        } catch (e) {
          print('❌ Error: $e');
        }
      }
    });
  });
}
