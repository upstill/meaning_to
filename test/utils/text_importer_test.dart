import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/link.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/text_importer.dart';

// Test data
const String plainTextData = '''
Task 1
Task 2 with description
Task 3 with link https://example.com
''';

const String jsonData = '''
{"title": "JSON Task 1", "description": "Description 1"}
{"title": "JSON Task 2", "link": "https://example.com/2"}
''';

const String jsonArrayData = '''
[
  {"title": "Array Task 1", "description": "Description 1"},
  {"title": "Array Task 2", "link": "https://example.com/2"}
]
''';

const String markdownData = '''
[Markdown Task 1](https://example.com/1)
[Markdown Task 2](https://example.com/2) with description
''';

const String mixedData = '''
Plain Task 1
{"title": "JSON Task", "description": "Description"}
[Markdown Task](https://example.com)
Task with URL https://example.com/plain
''';

void main() {
  group('ImportItem', () {
    test('creates a valid ImportItem', () {
      final item = ImportItem(
        title: 'Test Task',
        description: 'Test Description',
        link: 'https://example.com',
        domain: 'example.com',
      );

      expect(item.title, equals('Test Task'));
      expect(item.description, equals('Test Description'));
      expect(item.link, equals('https://example.com'));
      expect(item.domain, equals('example.com'));
      expect(item.metadata, isEmpty);
    });

    test('extracts domain from link when domain not provided', () {
      final item = ImportItem(
        title: 'Test Task',
        link: 'https://example.com/path',
      );

      expect(item.extractedDomain, equals('example.com'));
      expect(item.domain, isNull);
    });

    test('uses provided domain over extracted domain', () {
      final item = ImportItem(
        title: 'Test Task',
        link: 'https://example.com/path',
        domain: 'custom-domain.com',
      );

      expect(item.extractedDomain, equals('custom-domain.com'));
      expect(item.domain, equals('custom-domain.com'));
    });

    test('handles invalid URLs gracefully', () {
      final item = ImportItem(
        title: 'Test Task',
        link: 'not-a-valid-url',
      );

      expect(item.extractedDomain, isNull);
    });

    test('converts to Task', () {
      final item = ImportItem(
        title: 'Test Task',
        description: 'Test Description',
        link: 'https://example.com',
        domain: 'example.com',
      );

      final task = item.toTask(1, ownerId: 'test_user');
      expect(task.headline, equals('Test Task'));
      expect(task.notes, equals('Test Description'));
      expect(task.links, equals(['https://example.com']));
      expect(task.categoryId, equals(1));
      expect(task.ownerId, equals('test_user'));
      expect(task.finished, isFalse);
    });

    test('converts to Link', () {
      final item = ImportItem(
        title: 'Test Link',
        description: 'Test Description',
        link: 'https://example.com',
        domain: 'example.com',
      );

      final link = item.toLink();
      expect(link.title, equals('Test Link'));
      expect(link.description, equals('Test Description'));
      expect(link.url, equals('https://example.com'));
    });
  });

  group('TextImporter', () {
    const testData = '''
Test Task 1
Test Task 2 with https://example.com
{"title": "JSON Task", "description": "JSON Description", "link": "https://json.com"}
[{"title": "Array Task 1"}, {"title": "Array Task 2"}]
# Markdown Task
- List Task 1
- List Task 2 with https://list.com
''';

    test('parsePlainTextItem handles plain text', () {
      final item = TextImporter.parsePlainTextItem('Test Task');
      expect(item?.title, equals('Test Task'));
      expect(item?.description, isNull);
      expect(item?.link, isNull);
    });

    test('parsePlainTextItem handles text with URL', () {
      final item =
          TextImporter.parsePlainTextItem('Test Task with https://example.com');
      expect(item?.title, equals('Test Task with'));
      expect(item?.link, equals('https://example.com'));
      expect(item?.extractedDomain, equals('example.com'));
    });

    test('parsePlainTextItem handles Letterboxd share', () {
      final item = TextImporter.parsePlainTextItem(
          'The Phoenician Scheme on Letterboxd https://boxd.it/H0Ca');
      expect(item?.title, equals('The Phoenician Scheme on Letterboxd'));
      expect(item?.link, equals('https://boxd.it/H0Ca'));
      expect(item?.extractedDomain, equals('boxd.it'));
    });

    test('parsePlainTextItem handles HTML link', () {
      final item = TextImporter.parsePlainTextItem(
          '<a href="https://example.com">Test Link</a>');
      expect(item?.title, equals('Test Link'));
      expect(item?.link, equals('https://example.com'));
      expect(item?.extractedDomain, equals('example.com'));
      expect(item?.metadata['source'], equals('html_link'));
    });

    test('parseJsonItem handles JSON object', () {
      final item = TextImporter.parseJsonItem(
          '{"title": "Test Task", "description": "Test Description", "link": "https://example.com"}');
      expect(item?.title, equals('Test Task'));
      expect(item?.description, equals('Test Description'));
      expect(item?.link, equals('https://example.com'));
      expect(item?.extractedDomain, equals('example.com'));
    });

    test('parseJsonItem uses provided domain over extracted domain', () {
      final item = TextImporter.parseJsonItem(
          '{"title": "Test Task", "link": "https://example.com", "domain": "custom-domain.com"}');
      expect(item?.title, equals('Test Task'));
      expect(item?.link, equals('https://example.com'));
      expect(item?.domain, equals('custom-domain.com'));
      expect(item?.extractedDomain, equals('custom-domain.com'));
    });

    test('processTextData handles mixed content', () async {
      final items = await TextImporter.processTextData(
          testData, ImportContext.newCategory, 1);
      expect(items.length, equals(7));
      expect(items[0]?.title, equals('Test Task 1'));
      expect(items[1]?.title, equals('Test Task 2 with'));
      expect(items[1]?.link, equals('https://example.com'));
      expect(items[2]?.title, equals('JSON Task'));
      expect(items[2]?.description, equals('JSON Description'));
      expect(items[2]?.link, equals('https://json.com'));
    });

    test('processForNewCategory creates tasks', () async {
      final tasks = await TextImporter.processForNewCategory(
        testData,
        categoryId: 1,
        ownerId: 'test_user',
      ).toList();

      expect(tasks.length, equals(7));
      expect(tasks[0].headline, equals('Test Task 1'));
      expect(tasks[1].headline, equals('Test Task 2 with'));
      expect(tasks[1].links, equals(['https://example.com']));
      expect(tasks[2].headline, equals('JSON Task'));
      expect(tasks[2].notes, equals('JSON Description'));
      expect(tasks[2].links, equals(['https://json.com']));
    });

    test('processForAddToCategory creates tasks', () async {
      final tasks = await TextImporter.processForAddToCategory(
        testData,
        categoryId: 1,
        ownerId: 'test_user',
      ).toList();

      expect(tasks.length, equals(7));
      expect(tasks[0].headline, equals('Test Task 1'));
      expect(tasks[1].headline, equals('Test Task 2 with'));
      expect(tasks[1].links, equals(['https://example.com']));
      expect(tasks[2].headline, equals('JSON Task'));
      expect(tasks[2].notes, equals('JSON Description'));
      expect(tasks[2].links, equals(['https://json.com']));
    });

    test('processForAddToTask creates links', () async {
      final links = await TextImporter.processForAddToTask(testData).toList();

      expect(links.length, equals(3));
      expect(links[0].title, equals('Test Task 2 with'));
      expect(links[0].url, equals('https://example.com'));
      expect(links[1].title, equals('JSON Task'));
      expect(links[1].url, equals('https://json.com'));
      expect(links[2].title, equals('List Task 2 with'));
      expect(links[2].url, equals('https://list.com'));
    });
  });
}
