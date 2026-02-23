import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

void main() {
  group('Debug corsproxy.io selectors', () {
    test('Find what title/description elements exist', () async {
      final url = 'https://www.youtube.com/watch?v=qd1RXxf2LsQ';
      final proxyUrl = 'https://corsproxy.io/?${Uri.encodeComponent(url)}';

      print('=== Analyzing corsproxy.io content ===');

      try {
        final response = await http.get(
          Uri.parse(proxyUrl),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
          },
        ).timeout(Duration(seconds: 15));

        if (response.statusCode == 200) {
          final document = html_parser.parse(response.body);

          print('\n=== Available title elements ===');

          // Check all possible title elements
          final titleTag = document.querySelector('title');
          print('1. <title>: "${titleTag?.text ?? "NOT FOUND"}"');

          final metaTitle = document.querySelector('meta[name="title"]');
          print('2. meta[name="title"]: "${metaTitle?.attributes["content"] ?? "NOT FOUND"}"');

          final ogTitle = document.querySelector('meta[property="og:title"]');
          print('3. meta[property="og:title"]: "${ogTitle?.attributes["content"] ?? "NOT FOUND"}"');

          final twitterTitle = document.querySelector('meta[name="twitter:title"]');
          print('4. meta[name="twitter:title"]: "${twitterTitle?.attributes["content"] ?? "NOT FOUND"}"');

          final h1Elements = document.querySelectorAll('h1');
          print('5. Found ${h1Elements.length} h1 elements:');
          for (int i = 0; i < h1Elements.length && i < 3; i++) {
            print('   h1[$i]: "${h1Elements[i].text.trim()}"');
          }

          print('\n=== Available description elements ===');

          final metaDesc = document.querySelector('meta[name="description"]');
          print('1. meta[name="description"]: "${metaDesc?.attributes["content"] ?? "NOT FOUND"}"');

          final ogDesc = document.querySelector('meta[property="og:description"]');
          print('2. meta[property="og:description"]: "${ogDesc?.attributes["content"] ?? "NOT FOUND"}"');

          final twitterDesc = document.querySelector('meta[name="twitter:description"]');
          print('3. meta[name="twitter:description"]: "${twitterDesc?.attributes["content"] ?? "NOT FOUND"}"');

          // Look for any elements containing our expected content
          print('\n=== Searching for specific content ===');

          // Search for elements containing "Fleetwood Mac"
          final allElements = document.querySelectorAll('*');
          var fleetwoodElements = 0;
          var rumoursElements = 0;
          var disclaimerElements = 0;

          for (final element in allElements) {
            final text = element.text;
            if (text.contains('Fleetwood Mac')) {
              fleetwoodElements++;
              if (fleetwoodElements <= 3) {
                print('Found "Fleetwood Mac" in <${element.localName}>: "${text.length > 100 ? text.substring(0, 100) + "..." : text}"');
              }
            }
            if (text.contains('Rumours')) {
              rumoursElements++;
              if (rumoursElements <= 3) {
                print('Found "Rumours" in <${element.localName}>: "${text.length > 100 ? text.substring(0, 100) + "..." : text}"');
              }
            }
            if (text.contains('⚠️ IMPORTANT DISCLAIMER')) {
              disclaimerElements++;
              if (disclaimerElements <= 3) {
                print('Found disclaimer in <${element.localName}>: "${text.length > 100 ? text.substring(0, 100) + "..." : text}"');
              }
            }
          }

          print('\nTotal elements containing:');
          print('- "Fleetwood Mac": $fleetwoodElements');
          print('- "Rumours": $rumoursElements');
          print('- "⚠️ IMPORTANT DISCLAIMER": $disclaimerElements');
        }
      } catch (e) {
        print('Error: $e');
      }
    });
  });
}