# TextImporter Module

The `TextImporter` module provides functionality to import items from various text data sources, including clipboard data, files, and text strings. It supports multiple data formats and can process items in different contexts.

## Features

- **Multiple Data Formats**: Supports plain text, JSON objects, JSON arrays, markdown links, and HTML links
- **Context-Aware Processing**: Can process items for new categories, existing categories, or specific tasks
- **Domain Extraction**: Automatically extracts domains from URLs or allows explicit domain specification
- **Stream Processing**: Provides both stream-based and batch processing options
- **Error Handling**: Gracefully handles parsing errors and invalid data

## Core Classes

### ImportItem

Represents an item that can be imported from text data.

```dart
class ImportItem {
  final String title;
  final String? description;
  final String? link;
  final String? domain;
  final Map<String, dynamic> metadata;
}
```

**Properties:**
- `title`: The title/name of the item (required)
- `description`: Optional description or notes
- `link`: Optional URL associated with the item
- `domain`: Optional domain (explicitly set or extracted from link)
- `metadata`: Additional data from the source format

**Methods:**
- `toTask(category, ownerId)`: Converts the item to a Task
- `toLink()`: Converts the item to a Link

## Usage

### Basic Import Operations

#### Import from Text Data

```dart
// Import for new category (no categoryId or task specified)
final stream = TextImporter.processTextData(
  'Movie Title 1\nhttps://example.com/movie2 Movie Title 2',
);

// Import for existing category
final category = Category(id: 1, ownerId: 'user123', headline: 'Test Category', createdAt: DateTime.now());
final stream = TextImporter.processTextData(
  'Movie Title 1\nhttps://example.com/movie2 Movie Title 2',
  category: category,
);

// Import for specific task
final stream = TextImporter.processTextData(
  'https://example.com/link1\n[Markdown Link](https://example.com/link2)',
  task: existingTask,
);
```

### Context-Aware Processing

Use `processWithContext` to automatically determine the processing context based on parameters:

```dart
// New category context (no categoryId or task specified)
final newCategoryStream = TextImporter.processWithContext(
  'Test Task 1\nhttps://example.com/movie2 Movie Task 2',
  ownerId: 'user123',
);

// Add to category context (categoryId specified)
final addToCategoryStream = TextImporter.processWithContext(
  'Test Task 1\nhttps://example.com/movie2 Movie Task 2',
  category: category,
  ownerId: 'user123',
);

// Add to task context (task specified)
final addToTaskStream = TextImporter.processWithContext(
  'https://example.com/link1\n[Markdown Link](https://example.com/link2)',
  task: existingTask,
);
```

### Processing Context Logic

The context is determined by the parameters provided:

- **If `task` is specified**: Process as `addToTask` (converts items to Links)
- **If `category` is specified**: Process as `addToCategory` (converts items to Tasks)
- **If neither is specified**: Process as `newCategory` (converts items to Tasks for new category)

### Converting Imported Items

#### Convert to Tasks

```dart
// Convert a single item to a Task
final task = item.toTask(category, ownerId: 'user123');

// Process items as Tasks (for category context)
final taskStream = TextImporter.processForNewCategory(textData, category: category, ownerId: 'user123');
final taskStream2 = TextImporter.processForAddToCategory(textData, category: category, ownerId: 'user123');
```

#### Convert to Links

```dart
// Convert a single item to a Link
final link = item.toLink();

// Process items as Links (for task context)
final linkStream = TextImporter.processForAddToTask(textData);
```

### Individual Item Parsing

You can also parse individual text items:

```dart
// Parse a single text item
final item = TextImporter.importFromText('Movie Title with https://example.com/movie');

// Parse a JSON item
final jsonItem = TextImporter.parseJsonItem('{"title": "Movie", "link": "https://example.com/movie"}');
```

## Supported Data Formats

### 1. Plain Text (one item per line)
```
Movie Title 1
Movie Title 2
https://example.com/movie3 Movie Title 3
```

### 2. JSON Objects (one per line)
```json
{"title": "Movie 1", "description": "A great movie", "link": "https://example.com/movie1"}
{"title": "Movie 2", "notes": "Another great movie", "url": "https://example.com/movie2"}
{"title": "Movie 3", "link": "https://example.com/movie3", "domain": "custom-domain.com"}
```

### 3. JSON Array
```json
[{"title": "Movie 1"}, {"title": "Movie 2", "link": "https://example.com/movie2"}]
```

### 4. Markdown Links
```markdown
[Inception](https://example.com/inception)
[The Matrix](https://example.com/matrix)
```

### 5. URLs with Titles
```
https://example.com/movie1 Movie Title 1
https://example.com/movie2 Movie Title 2
```

### 6. HTML Links
```html
<a href="https://example.com">Test Link</a>
```

### 7. Mixed Formats
```
Movie Title 1
{"title": "Movie 2", "link": "https://example.com/movie2"}
[Inception](https://example.com/inception)
https://example.com/movie4 Movie Title 4
```

## Domain Handling

The module provides flexible domain handling:

### Explicit Domain
```json
{"title": "Movie with custom domain", "link": "https://example.com/movie", "domain": "custom-domain.com"}
```

### Auto-Extracted Domain
```json
{"title": "Movie with auto-extracted domain", "link": "https://letterboxd.com/movie"}
```

### JustWatch Integration
The module includes special handling for JustWatch shares:

```json
{"title": "Severance", "host": "www.justwatch.com", "scheme": "https", "path": "/us/tv-show/severance"}
```

This automatically assembles the full URL: `https://www.justwatch.com/us/tv-show/severance`

## Error Handling

The module gracefully handles various error conditions:

- **Invalid JSON**: Returns null for malformed JSON objects
- **Empty Lines**: Skips empty or whitespace-only lines
- **Missing Titles**: Returns null for items without titles
- **Invalid URLs**: Handles malformed URLs gracefully
- **Domain Extraction**: Returns null for URLs that can't be parsed

## Testing

The module includes comprehensive tests covering:

- All supported data formats
- Domain extraction and handling
- Error conditions
- JustWatch integration
- Context-aware processing

Run tests with:
```bash
flutter test test/utils/text_importer_test.dart
```

## Examples

See `lib/utils/text_importer_example.dart` for complete usage examples including:

- Import from clipboard for different contexts
- Import from files
- Custom filtering
- Context-aware processing
- Domain handling demonstrations 