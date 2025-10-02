import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/utils/site_configurations.dart';
import 'package:flutter/foundation.dart';

void main() {
  group('Web Detection Debug', () {
    test('Check kIsWeb flag and proxy logic', () async {
      final url = 'https://www.youtube.com/watch?v=qd1RXxf2LsQ';

      print('=== Environment Detection ===');
      print('kIsWeb: $kIsWeb');
      print('kDebugMode: $kDebugMode');

      print('\n=== Site Configuration ===');
      final config = SiteConfigRegistry.getConfigForUrl(url);
      print('Domain: ${config.domain}');
      print('Display Name: ${config.displayName}');
      print('Requires Proxy: ${config.requiresProxy}');

      print('\n=== Proxy Logic ===');
      final shouldUseProxy = SiteConfigRegistry.shouldUseProxy(url);
      print('shouldUseProxy result: $shouldUseProxy');

      final willUseProxy = kIsWeb && shouldUseProxy;
      print('kIsWeb && shouldUseProxy: $willUseProxy');

      if (willUseProxy) {
        final proxyUrl = 'https://api.allorigins.win/raw?url=${Uri.encodeComponent(url)}';
        print('Would use proxy URL: $proxyUrl');
      } else {
        print('Would use direct URL: $url');
      }

      print('\n=== Testing Actual Content Fetch ===');
      try {
        final content = await LinkProcessor.fetchWebpageContent(url);
        if (content != null) {
          print('Successfully fetched content:');
          print('  Title: "${content.title}"');
          print('  Description length: ${content.description?.length ?? 0}');
        } else {
          print('Failed to fetch content (returned null)');
        }
      } catch (e) {
        print('Error fetching content: $e');
      }
    });
  });
}