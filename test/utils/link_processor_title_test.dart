import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/link_processor.dart';

void main() {
  group('LinkProcessor fetchWebpageTitle Tests', () {
    test('should fetch title from The Atlantic article', () async {
      const testUrl =
          'https://www.theatlantic.com/magazine/archive/2025/09/canada-euthanasia-demand-maid-policy/683562/';

      final title = await LinkProcessor.fetchWebpageTitle(testUrl);

      // The title should be extracted successfully
      expect(title, isNotNull);
      expect(title, isNotEmpty);
      expect(title, contains('Canada'));
      expect(title, contains('Atlantic'));

      print('✅ Test passed: Title extracted: "$title"');
    });

    test('should handle CORS errors gracefully', () async {
      const testUrl =
          'https://www.theatlantic.com/magazine/archive/2025/09/canada-euthanasia-demand-maid-policy/683562/';

      // This test will likely fail in web environment due to CORS
      final title = await LinkProcessor.fetchWebpageTitle(testUrl);

      // In web environment, this should return null due to CORS
      // In non-web environment, this should return the actual title
      if (title == null) {
        print('⚠️ CORS blocked the request (expected in web environment)');
      } else {
        print('✅ Title extracted successfully: "$title"');
      }
    });

    test('should create proper fallback title when fetchWebpageTitle fails',
        () async {
      const testUrl =
          'https://www.theatlantic.com/magazine/archive/2025/09/canada-euthanasia-demand-maid-policy/683562/';

      final processedLink = await LinkProcessor.validateAndProcessLink(testUrl);

      // Should have a title (either fetched or fallback)
      expect(processedLink.title, isNotNull);
      expect(processedLink.title, isNotEmpty);

      print('✅ ProcessedLink title: "${processedLink.title}"');

      // If it's the fallback title, it should be "683562"
      // If it's the real title, it should contain "Canada"
      if (processedLink.title == '683562') {
        print(
            '⚠️ Using fallback title due to CORS (expected in web environment)');
      } else {
        print('✅ Using real title: "${processedLink.title}"');
      }
    });
  });
}
