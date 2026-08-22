import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/utils/input_line_parser.dart';

void main() {
  group('InputLineParser.parse', () {
    test('text followed by a bare URL: text is the headline, URL is held', () {
      final p = InputLineParser.parse('Great essay https://x.com/y');
      expect(p.headline, 'Great essay');
      expect(p.url, 'https://x.com/y');
      expect(p.linkTitle, isNull);
      expect(p.finished, isFalse);
    });

    test('bare URL only: headline empty (filled at enrich), URL held', () {
      final p = InputLineParser.parse('https://x.com/y');
      expect(p.headline, '');
      expect(p.url, 'https://x.com/y');
    });

    test('HTML link only: headline falls back to the link label', () {
      final p =
          InputLineParser.parse('<a href="https://x.com/y">Cool Movie</a>');
      expect(p.url, 'https://x.com/y');
      expect(p.linkTitle, 'Cool Movie');
      expect(p.headline, 'Cool Movie');
    });

    test('text around an HTML link: surrounding text is the headline', () {
      final p = InputLineParser.parse(
          'Watch this <a href="https://x.com/y">Label</a> soon');
      expect(p.url, 'https://x.com/y');
      expect(p.linkTitle, 'Label');
      expect(p.headline, 'Watch this soon');
    });

    test('markdown link with trailing note', () {
      final p = InputLineParser.parse('[Title](https://x.com/y) a note');
      expect(p.url, 'https://x.com/y');
      expect(p.linkTitle, 'Title');
      expect(p.headline, 'a note');
    });

    test('checked checklist item marks finished', () {
      final p = InputLineParser.parse('[x] Do the thing');
      expect(p.finished, isTrue);
      expect(p.headline, 'Do the thing');
      expect(p.url, isNull);
    });

    test('Title: notes split', () {
      final p = InputLineParser.parse('Buy milk: from the good store');
      expect(p.headline, 'Buy milk');
      expect(p.notes, 'from the good store');
    });

    test('trailing parenthetical becomes notes', () {
      final p = InputLineParser.parse('Call Sam (about the roof)');
      expect(p.headline, 'Call Sam');
      expect(p.notes, '(about the roof)');
    });

    test('colon inside a plain title is not split without a space', () {
      final p = InputLineParser.parse('Mission:Impossible');
      expect(p.headline, 'Mission:Impossible');
      expect(p.notes, isNull);
    });

    test('trailing punctuation is trimmed off a bare URL', () {
      final p = InputLineParser.parse('See https://x.com/y.');
      expect(p.url, 'https://x.com/y');
      expect(p.headline, 'See');
    });
  });
}
