import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/utils/category_suggestion_registry.dart';

void main() {
  setUpAll(() async {
    try {
      await dotenv.load(fileName: '.env');
      print('✅ Test setup: .env file loaded successfully');
    } catch (e) {
      print('⚠️  Test setup: Could not load .env file: $e');
    }
  });

  group('Title Extraction + Category Suggestion Tests', () {
    test('should match title and category suggestions from TSV data', () async {
      final tsvFile = File('test/utils/title_extraction_test_data.tsv');

      if (!await tsvFile.exists()) {
        print('⚠️  TSV test data file not found at: ${tsvFile.path}');
        print('   Skipping tests');
        return;
      }

      final lines = await tsvFile.readAsLines();

      if (lines.isEmpty) {
        print('⚠️  TSV file is empty');
        return;
      }

      // First line is the header; skip it and any lines that don't start with
      // "http" (the legend rows embedded below the header are ignored).
      final dataLines = <String>[];
      for (int i = 1; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed.startsWith('http')) {
          dataLines.add(trimmed);
        }
      }

      print('✅ Found TSV with ${dataLines.length} test case(s)');

      // Support --dart-define=TEST_LINE=N (1-based index into data rows)
      const testLineParam = String.fromEnvironment('TEST_LINE');
      final specificLine =
          testLineParam.isEmpty ? null : int.tryParse(testLineParam);

      if (specificLine != null) {
        if (specificLine < 1 || specificLine > dataLines.length) {
          print(
              '❌ TEST_LINE=$specificLine is out of range (1-${dataLines.length})');
          fail('TEST_LINE out of range');
        }
        print('   Testing only row $specificLine...\n');
      } else {
        print('   Processing ${dataLines.length} test case(s)...\n');
      }

      for (int i = 0; i < dataLines.length; i++) {
        final rowNumber = i + 1; // 1-based for user-facing messages
        if (specificLine != null && rowNumber != specificLine) continue;

        final fields = dataLines[i].split('\t');
        while (fields.length < 3) fields.add('');

        final url = fields[0].trim();
        final expectedTitleSubstring = fields[1].trim();
        final rawCategoryIds = fields[2].trim();

        final expectedCategoryIds = rawCategoryIds.isEmpty
            ? <int>[]
            : rawCategoryIds
                .split(',')
                .map((s) => int.parse(s.trim()))
                .toList();

        print('Row $rowNumber: $url');

        try {
          // ── 1. Title extraction ──────────────────────────────────────────
          final content = await LinkProcessor.fetchWebpageContent(url);
          final title = content?.title ?? '';

          if (expectedTitleSubstring.isNotEmpty) {
            expect(
              title,
              contains(expectedTitleSubstring),
              reason:
                  'Title for $url should contain "$expectedTitleSubstring" but got "$title"',
            );
            print('  ✅ Title contains "$expectedTitleSubstring": "$title"');
          } else {
            print('  ℹ️  No title assertion (expected substring empty)');
          }

          // ── 2. Category suggestions ──────────────────────────────────────
          final actualCategoryIds =
              CategorySuggestionRegistry.getSuggestionsForUrl(url);

          expect(
            actualCategoryIds,
            equals(expectedCategoryIds),
            reason:
                'Category IDs for $url: expected $expectedCategoryIds, got $actualCategoryIds',
          );
          print('  ✅ Category IDs: $actualCategoryIds');

          print('  ✅ Row $rowNumber passed\n');
        } catch (e) {
          print('  ❌ Row $rowNumber failed: $e\n');
          rethrow;
        }
      }

      print('✅ All title extraction tests passed!');
    });
  });
}
