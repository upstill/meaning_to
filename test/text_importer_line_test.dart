import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/text_importer.dart';

/// Phase 2: TextImporter.importFromText now maps InputLineParser output to an
/// ImportItem. These lock the mapping for representative list-import lines.
void main() {
  group('TextImporter.importFromText', () {
    test('plain text → title only', () {
      final item = TextImporter.importFromText('Buy milk');
      expect(item, isNotNull);
      expect(item!.title, 'Buy milk');
      expect(item.link, isNull);
      expect(item.finished, isFalse);
    });

    test('Title: notes → title + description', () {
      final item = TextImporter.importFromText('Call Sam: about the roof');
      expect(item!.title, 'Call Sam');
      expect(item.description, 'about the roof');
    });

    test('checked checklist item → finished', () {
      final item = TextImporter.importFromText('[x] Walk the dog');
      expect(item!.title, 'Walk the dog');
      expect(item.finished, isTrue);
    });

    test('HTML link → title from label, link from href', () {
      final item = TextImporter.importFromText(
          '<a href="https://x.com/y">Cool Movie</a>');
      expect(item!.title, 'Cool Movie');
      expect(item.link, 'https://x.com/y');
    });

    test('markdown link → title from label, link held', () {
      final item = TextImporter.importFromText('[The Bear](https://x.com/bear)');
      expect(item!.title, 'The Bear');
      expect(item.link, 'https://x.com/bear');
    });

    test('text followed by a URL → text is title, URL held', () {
      final item = TextImporter.importFromText('Great essay https://x.com/y');
      expect(item!.title, 'Great essay');
      expect(item.link, 'https://x.com/y');
    });

    test('empty line → null', () {
      expect(TextImporter.importFromText('   '), isNull);
    });

    test('JSON array line → null (expanded upstream)', () {
      expect(TextImporter.importFromText('[1, 2, 3]'), isNull);
    });
  });
}
