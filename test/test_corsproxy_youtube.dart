import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:meaning_to/utils/site_configurations.dart';

void main() {
  group('Test corsproxy.io with YouTube', () {
    test('Verify corsproxy.io returns proper YouTube content', () async {
      final url = 'https://www.youtube.com/watch?v=qd1RXxf2LsQ';
      final proxyUrl = 'https://corsproxy.io/?${Uri.encodeComponent(url)}';

      print('=== Testing corsproxy.io for YouTube ===');
      print('Original URL: $url');
      print('Proxy URL: $proxyUrl');

      try {
        final response = await http.get(
          Uri.parse(proxyUrl),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
          },
        ).timeout(Duration(seconds: 15));

        print('Status: ${response.statusCode}');
        print('Content length: ${response.body.length}');

        expect(response.statusCode, equals(200), reason: 'Should get successful response');
        expect(response.body.length, greaterThan(1000), reason: 'Should get substantial content');

        if (response.statusCode == 200) {
          // Parse the HTML
          final document = html_parser.parse(response.body);

          // Test site configuration extraction
          final siteConfig = SiteConfigRegistry.getConfigForUrl(url);
          print('\n=== Using site configuration: ${siteConfig.displayName} ===');

          final extractedTitle = siteConfig.extractTitle(document);
          final extractedDescription = siteConfig.extractDescription(document);

          print('Extracted title: "$extractedTitle"');
          print('Extracted description: "${extractedDescription?.substring(0, extractedDescription.length > 100 ? 100 : extractedDescription.length)}..."');

          // Test expectations
          expect(extractedTitle, isNotNull, reason: 'Should extract a title');
          expect(extractedTitle, contains('Fleetwood Mac'), reason: 'Title should contain "Fleetwood Mac"');
          expect(extractedTitle, contains('Rumours'), reason: 'Title should contain "Rumours"');

          expect(extractedDescription, isNotNull, reason: 'Should extract a description');
          expect(extractedDescription!, startsWith('⚠️ IMPORTANT DISCLAIMER ⚠️'),
                 reason: 'Description should start with disclaimer');

          print('✅ All expectations met!');
        }
      } catch (e) {
        print('❌ Error: $e');
        rethrow;
      }
    });
  });
}