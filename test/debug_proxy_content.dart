import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

void main() {
  group('Debug Proxy Content', () {
    test('Check what proxy returns for YouTube', () async {
      const url = 'https://www.youtube.com/watch?v=qd1RXxf2LsQ';
      final proxyUrl =
          'https://api.allorigins.win/raw?url=${Uri.encodeComponent(url)}';

      print('=== Fetching content via proxy ===');
      print('Original URL: $url');
      print('Proxy URL: $proxyUrl');

      try {
        final response = await http.get(Uri.parse(proxyUrl));
        print('Status: ${response.statusCode}');
        print('Content length: ${response.body.length}');

        if (response.statusCode == 200) {
          // Parse the HTML to debug
          final document = html_parser.parse(response.body);

          print('\n=== Content Analysis ===');

          // Check for title tag
          final titleElement = document.querySelector('title');
          if (titleElement != null) {
            print('Found <title>: "${titleElement.text}"');
          } else {
            print('No <title> tag found');
          }

          // Check for YouTube-specific meta tags
          final metaTitle = document.querySelector('meta[name="title"]');
          if (metaTitle != null) {
            print(
                'Found meta[name="title"]: "${metaTitle.attributes["content"]}"');
          } else {
            print('No meta[name="title"] found');
          }

          final metaDescription =
              document.querySelector('meta[name="description"]');
          if (metaDescription != null) {
            print(
                'Found meta[name="description"]: "${metaDescription.attributes["content"]}"');
          } else {
            print('No meta[name="description"] found');
          }

          // Check for og tags
          final ogTitle = document.querySelector('meta[property="og:title"]');
          if (ogTitle != null) {
            print('Found og:title: "${ogTitle.attributes["content"]}"');
          } else {
            print('No og:title found');
          }

          // Check what the page actually looks like
          print('\n=== First 1000 characters of content ===');
          print(response.body.substring(
              0, response.body.length > 1000 ? 1000 : response.body.length));

          // Look for any mention of the video title
          print('\n=== Searching for expected content ===');
          final hasFleetwood = response.body.contains('Fleetwood Mac');
          final hasRumours = response.body.contains('Rumours');
          final hasDisclaimer =
              response.body.contains('⚠️ IMPORTANT DISCLAIMER');

          print('Contains "Fleetwood Mac": $hasFleetwood');
          print('Contains "Rumours": $hasRumours');
          print('Contains "⚠️ IMPORTANT DISCLAIMER": $hasDisclaimer');
        }
      } catch (e) {
        print('Error: $e');
      }
    });
  });
}
