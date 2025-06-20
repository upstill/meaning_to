import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/link.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/text_importer.dart';

void main() {
  group('ImportItem', () {
    test('interprets strings correctly', () {
      final item = ImportItem(title: 'Task 1');
      expect(item.title, equals('Task 1'));
      expect(item.description, isNull);
      expect(item.link, isNull);
      expect(item.domain, isNull);
    });
    test('creates a valid ImportItem', () {
      final item = ImportItem(
        title: 'Test Task',
        description: 'Test Description',
        link: 'https://www.example.com',
        domain: 'example.com',
      );

      expect(item.title, equals('Test Task'));
      expect(item.description, equals('Test Description'));
      expect(item.link, equals('https://www.example.com'));
      expect(item.domain, equals('example.com'));
      expect(item.metadata, isEmpty);
    });

    test('extracts domain from link', () {
      final item = ImportItem(
        title: 'Test Task',
        link: 'https://www.example.com/path',
      );
      expect(item.domain, equals('example.com'));
    });

    test('uses explicit domain over extracted domain', () {
      final item = ImportItem(
        title: 'Test Task',
        link: 'https://www.example.com/path',
        domain: 'custom-domain.com',
      );
      expect(item.domain, equals('custom-domain.com'));
    });

    test('returns null for domain when no link or explicit domain', () {
      final item = ImportItem(
        title: 'Test Task',
        link: 'not-a-valid-url',
      );
      expect(item.domain, isNull);
      expect(item.link, isNull);
    });

    test('converts to Task', () {
      final item = ImportItem(
        title: 'Test Task',
        description: 'Test Description',
        link: 'https://www.example.com',
        domain: 'example.com',
      );

      final testCategory = Category(
          id: 1,
          ownerId: 'test_user',
          headline: 'Test Category',
          createdAt: DateTime.now());
      final task = item.toTask(testCategory, ownerId: 'test_user');
      expect(task.headline, equals('Test Task'));
      expect(task.notes, equals('Test Description'));
      expect(task.links, equals(['https://www.example.com']));
      expect(task.categoryId, equals(testCategory.id));
      expect(task.ownerId, equals('test_user'));
      expect(task.finished, isFalse);
    });

    test('converts to Link', () {
      final item = ImportItem(
        title: 'Test Link',
        description: 'Test Description',
        link: 'https://www.example.com',
        domain: 'example.com',
      );

      final link = item.toLink();
      expect(link.title, equals('Test Link'));
      expect(link.description, equals('Test Description'));
      expect(link.url, equals('https://www.example.com'));
    });
  });

  // Test data that puts the same data in different formats
  const String plainTextData = '''
  Task 1
  Task 2 with description
  Task 3 with link https://example.com with description description"
  ''';

  const String jsonData = '''
  {"title": "Task 1"}
  {"title": "Task 2", "description": "description"}
  {"title": "Task 3", "link": "https://example.com", "description": "Description"}
  ''';

  const String jsonArrayData = '''
  [
    {"title": "Task 1"},
    {"title": "Task 2", "description": "description"},
    {"title": "Task 3", "link": "https://example.com", "description": "Description"}
  ]
  ''';

  const String markdownData = '''
  [Task 1]()
  [Task 2]() with description Description
  [Task 3](https://example.com) with description Description
  ''';

  const String mixedData = '''
  Task 1
  {"title": "Task 2", "description": "Description"}
  [Task 3](https://example.com) with description Description
  ''';

  // All the above should result in the following ImportItems
  final dataResult1 = ImportItem(title: 'Task 1');
  final dataResult2 = ImportItem(title: 'Task 2', description: 'Description');
  final dataResult3 = ImportItem(
      title: 'Task 3', link: 'https://example.com', description: 'Description');
  group('TextImporter', () {
    final testCategory = Category(
        id: 1,
        ownerId: 'test_user',
        headline: 'Test Category',
        createdAt: DateTime.now());
    const testData = '''
Test Task 1
Test Task 2 with https://www.example.com
{"title": "JSON Task", "description": "JSON Description", "link": "https://json.com"}
[{"title": "Array Task 1"}, {"title": "Array Task 2"}]
# Markdown Task
- List Task 1
- List Task 2 with https://www.list.com
''';

    test('parsePlainTextItem handles plain text', () {
      final item = TextImporter.parsePlainTextItem('Test Task');
      expect(item?.title, equals('Test Task'));
      expect(item?.description, isNull);
      expect(item?.link, isNull);
    });

    test('parsePlainTextItem handles text with URL', () {
      final item = TextImporter.parsePlainTextItem(
          'Test Task with https://www.example.com');
      expect(item?.title, equals('Test Task with'));
      expect(item?.link, equals('https://www.example.com'));
      expect(item?.domain, equals('example.com'));
    });

    test('parsePlainTextItem handles Letterboxd share', () {
      final item = TextImporter.parsePlainTextItem(
          'The Phoenician Scheme on Letterboxd https://boxd.it/H0Ca');
      expect(item?.title, equals('The Phoenician Scheme on Letterboxd'));
      expect(item?.link, equals('https://boxd.it/H0Ca'));
      expect(item?.domain, equals('boxd.it'));
    });

    test('parsePlainTextItem handles Justwatch share', () {
      final item = TextImporter.parsePlainTextItem(
          'The Phoenician Scheme on JustWatch https://www.justwatch.com/us/tv-show/severance');
      expect(item?.title, equals('The Phoenician Scheme on JustWatch'));
      expect(
          item?.link, equals('https://www.justwatch.com/us/tv-show/severance'));
      expect(item?.domain, equals('justwatch.com'));
    });

    test('parsePlainTextItem handles HTML link', () {
      final item = TextImporter.parsePlainTextItem(
          '<a href="https://www.example.com">Test Link</a>');
      expect(item?.title, equals('Test Link'));
      expect(item?.link, equals('https://www.example.com'));
      expect(item?.domain, equals('example.com'));
      expect(item?.metadata['source'], equals('html_link'));
    });

    test('parseJsonItem handles JSON object', () {
      final item = TextImporter.parseJsonItem(
          '{"title": "Test Task", "description": "Test Description", "link": "https://www.example.com"}');
      expect(item?.title, equals('Test Task'));
      expect(item?.description, equals('Test Description'));
      expect(item?.link, equals('https://www.example.com'));
      expect(item?.domain, equals('example.com'));
    });

    test('parseTextItem handles embedded JSON array', () {
      final item = TextImporter.parsePlainTextItem(
          r'["<a href=\"https://www.justwatch.com/us/tv-show/interior-chinatown\">Interior Chinatown</a>"]');
      expect(item?.title, equals('Interior Chinatown'));
      expect(item?.description, null);
      expect(item?.link,
          equals('https://www.justwatch.com/us/tv-show/interior-chinatown'));
      expect(item?.domain, equals('justwatch.com'));
    });

    test('parseJsonItem uses provided domain over extracted domain', () {
      final item = TextImporter.parseJsonItem(
          '{"title": "Test Task", "link": "https://www.example.com", "domain": "custom-domain.com"}');
      expect(item?.title, equals('Test Task'));
      expect(item?.link, equals('https://www.example.com'));
      expect(item?.domain, equals('custom-domain.com'));
      expect(item?.domain, equals('custom-domain.com'));
    });

    test('parseJsonItem handles JustWatch share with host, scheme, and path',
        () {
      final item = TextImporter.parseJsonItem(
          '{"title": "Severance", "host": "www.justwatch.com", "scheme": "https", "path": "/us/tv-show/severance"}');
      expect(item?.title, equals('Severance'));
      expect(
          item?.link, equals('https://www.justwatch.com/us/tv-show/severance'));
      expect(item?.domain, equals('justwatch.com'));
    });

    test('parseJsonItem handles JustWatch share with default scheme', () {
      final item = TextImporter.parseJsonItem(
          '{"title": "The Matrix", "host": "www.justwatch.com", "path": "/us/movie/the-matrix"}');
      expect(item?.title, equals('The Matrix'));
      expect(
          item?.link, equals('https://www.justwatch.com/us/movie/the-matrix'));
      expect(item?.domain, equals('justwatch.com'));
    });

    test('parseJsonItem does not assemble link for non-JustWatch domains', () {
      final item = TextImporter.parseJsonItem(
          '{"title": "Example", "host": "www.example.com", "scheme": "https", "path": "/test"}');
      expect(item?.title, equals('Example'));
      expect(item?.link, equals('https://www.example.com/test'));
      expect(item?.domain, equals('example.com'));
    });

    test('importFromText handles mixed content', () async {
      final items =
          await TextImporter.importFromText(testData, category: testCategory)
              .toList();
      expect(items.length, equals(7));
      expect(items[0].title, equals('Test Task 1'));
      expect(items[1].title, equals('Test Task 2 with'));
      expect(items[1].link, equals('https://www.example.com'));
      expect(items[2].title, equals('JSON Task'));
      expect(items[2].description, equals('JSON Description'));
      expect(items[2].link, equals('https://json.com'));
    });

    test('processForNewCategory creates tasks', () async {
      final tasks = await TextImporter.processForNewCategory(
        testData,
        category: testCategory,
        ownerId: 'test_user',
      ).toList();

      expect(tasks.length, equals(7));
      expect(tasks[0].headline, equals('Test Task 1'));
      expect(tasks[1].headline, equals('Test Task 2 with'));
      expect(tasks[1].links, equals(['https://www.example.com']));
      expect(tasks[2].headline, equals('JSON Task'));
      expect(tasks[2].notes, equals('JSON Description'));
      expect(tasks[2].links, equals(['https://json.com']));
    });

    test('processForAddToCategory creates tasks', () async {
      final tasks = await TextImporter.processForAddToCategory(
        testData,
        category: testCategory,
        ownerId: 'test_user',
      ).toList();

      expect(tasks.length, equals(7));
      expect(tasks[0].headline, equals('Test Task 1'));
      expect(tasks[1].headline, equals('Test Task 2 with'));
      expect(tasks[1].links, equals(['https://www.example.com']));
      expect(tasks[2].headline, equals('JSON Task'));
      expect(tasks[2].notes, equals('JSON Description'));
      expect(tasks[2].links, equals(['https://json.com']));
    });

    test('processForAddToTask creates links', () async {
      final links = await TextImporter.processForAddToTask(testData).toList();

      expect(links.length, equals(3));
      expect(links[0].title, equals('Test Task 2 with'));
      expect(links[0].url, equals('https://www.example.com'));
      expect(links[1].title, equals('JSON Task'));
      expect(links[1].url, equals('https://json.com'));
      expect(links[2].title, equals('List Task 2 with'));
      expect(links[2].url, equals('https://www.list.com'));
    });

    test('debug JustWatch JSON parsing', () {
      final json =
          '{"title": "Severance", "host": "www.justwatch.com", "scheme": "https", "path": "/us/tv-show/severance"}';
      final jsonData = jsonDecode(json);
      print('JSON data: $jsonData');
      print('Host: ${jsonData['host']}');
      print('Scheme: ${jsonData['scheme']}');
      print('Path: ${jsonData['path']}');

      final item = TextImporter.parseJsonItem(json);
      print('Parsed item: $item');
      print('Parsed title: ${item?.title}');
      print('Item link: ${item?.link}');
      print('Item domain: ${item?.domain}');

      expect(item?.title, equals('Severance'));
      expect(
          item?.link, equals('https://www.justwatch.com/us/tv-show/severance'));
      expect(item?.domain, equals('justwatch.com'));
    });

    test('converts to Task', () {
      final item = ImportItem(
        title: 'Test Task',
        description: 'Test Description',
        link: 'https://example.com',
        domain: 'example.com',
      );
      final testCategory = Category(
          id: 1,
          ownerId: 'test_user',
          headline: 'Test Category',
          createdAt: DateTime.now());
      final task = item.toTask(testCategory, ownerId: 'test_user');
      expect(task.headline, equals('Test Task'));
      expect(task.notes, equals('Test Description'));
      expect(task.links, equals(['https://example.com']));
      expect(task.categoryId, equals(testCategory.id));
      expect(task.ownerId, equals('test_user'));
      expect(task.finished, isFalse);
    });
  });
}
