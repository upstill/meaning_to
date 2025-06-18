# TextImporter Module

The `TextImporter` module provides functionality for importing items from text data sources (clipboard and files) into the meaning_to app. It supports different import contexts and returns generators for sequential item processing.

## Features

- **Multiple Data Sources**: Import from clipboard or text files
- **Flexible Contexts**: Support for different import scenarios
- **Multiple Formats**: Handle plain text, JSON, markdown links, and URLs
- **Streaming**: Process items sequentially using Dart streams
- **Error Handling**: Robust error handling with meaningful error messages

## Import Contexts

The module supports three different import contexts:

### 1. `ImportContext.newCategory`
For creating a new category with imported items as tasks.

### 2. `ImportContext.addToCategory` 
For adding items to the tasks of an existing category.

### 3. `ImportContext.addToTask`
For adding links to an existing task.

## Supported Data Formats

### Plain Text
```
Movie Title 1
Movie Title 2
https://example.com/movie3 Movie Title 3
```

### JSON Objects (one per line)
```json
{"title": "Movie 1", "description": "A great movie", "link": "https://example.com/movie1"}
{"title": "Movie 2", "notes": "Another great movie", "url": "https://example.com/movie2"}
```

### JSON Arrays
```json
[{"title": "Movie 1"}, {"title": "Movie 2", "link": "https://example.com/movie2"}]
```

### Markdown Links
```
[Inception](https://example.com/inception)
[The Matrix](https://example.com/matrix)
```

### URLs with Titles
```
https://example.com/movie1 Movie Title 1
https://example.com/movie2 Movie Title 2
```

### Mixed Formats
The importer can handle mixed formats in the same input:
```
Movie Title 1
{"title": "Movie 2", "link": "https://example.com/movie2"}
[Inception](https://example.com/inception)
https://example.com/movie4 Movie Title 4
```

## Usage Examples

### Basic Import from Clipboard

```dart
import 'package:meaning_to/utils/text_importer.dart';

// Import for new category
final controller = TextImporter.importFromClipboard(ImportContext.newCategory);

controller.stream.listen(
  (item) {
    print('Received item: $item');
    // Process the item (e.g., create a Task)
  },
  onError: (error) {
    print('Error: $error');
  },
  onDone: () {
    print('Import completed');
  },
);
```

### Import from File

```dart
// Import from file
final controller = await TextImporter.importFromFile(ImportContext.addToCategory);

if (controller != null) {
  controller.stream.listen(
    (item) {
      print('Received item: $item');
      // Process the item
    },
    onError: (error) {
      print('Error: $error');
    },
    onDone: () {
      print('Import completed');
    },
  );
}
```

### Convert ImportItem to Task

```dart
// For new category context
final task = TextImporter.importItemToTask(item, categoryId, ownerId);
if (task != null) {
  // Save task to database
}
```

### Convert ImportItem to Link

```dart
// For add to task context
final link = TextImporter.importItemToLink(item);
if (link != null) {
  // Add link to existing task
}
```

### Process All Items at Once

```dart
final items = <ImportItem>[];
final controller = TextImporter.importFromClipboard(ImportContext.newCategory);

await for (final item in controller.stream) {
  items.add(item);
}

// Now process all items
for (final item in items) {
  // Process item
}
```

### Custom Filtering

```dart
final controller = TextImporter.importFromClipboard(ImportContext.newCategory);

controller.stream
    .where((item) => item.title.length > 3) // Filter out short titles
    .listen(
  (item) {
    print('Filtered item: $item');
  },
  onError: (error) {
    print('Error: $error');
  },
  onDone: () {
    print('Import completed');
  },
);
```

## ImportItem Class

The `ImportItem` class represents a single item that can be imported:

```dart
class ImportItem {
  final String title;           // Required: The title/name of the item
  final String? description;    // Optional: Description or notes
  final String? link;           // Optional: URL or link
  final String? domain;         // Optional: Domain name (can be set explicitly or extracted from link)
  final Map<String, dynamic>? metadata; // Optional: Additional metadata
}
```

### Domain Handling

The `ImportItem` class provides flexible domain handling:

- **Explicit Domain**: You can set the domain explicitly during creation
- **Automatic Extraction**: If no domain is provided but a link is available, the domain is automatically extracted from the URL
- **Domain Getter**: Use `item.extractedDomain` to get the domain (either the explicitly set one or the extracted one)

#### Examples:

```dart
// Domain explicitly set
final item1 = ImportItem(
  title: 'Movie Title',
  link: 'https://example.com/movie',
  domain: 'custom-domain.com', // This domain will be used
);

// Domain automatically extracted from link
final item2 = ImportItem(
  title: 'Movie Title',
  link: 'https://example.com/movie', // Domain will be extracted as 'example.com'
);

// Get the domain (either explicit or extracted)
print(item1.extractedDomain); // 'custom-domain.com'
print(item2.extractedDomain); // 'example.com'
```

#### JSON Import with Domain:

```json
{
  "title": "Movie Title",
  "link": "https://example.com/movie",
  "domain": "custom-domain.com"
}
```

If the `domain` field is provided in JSON, it will be used. Otherwise, the domain will be extracted from the `link` field.

## Error Handling

The module provides comprehensive error handling:

- **Empty Data**: Handles empty clipboard or file content
- **Invalid JSON**: Gracefully falls back to plain text parsing
- **File Access**: Handles file permission and access errors
- **Stream Errors**: Propagates errors through the stream for proper handling

## File Types Supported

When importing from files, the module accepts:
- `.txt` - Plain text files
- `.json` - JSON files
- `.csv` - CSV files (treated as plain text)

## Integration with Existing Code

The module is designed to integrate seamlessly with the existing meaning_to codebase:

- Uses existing `Task` and `Category` models
- Follows the same patterns as the JustWatch importer
- Compatible with the existing link processing system
- Uses the same file selection approach as other importers

## Future Enhancements

Potential future improvements:
- CSV parsing with column mapping
- Batch processing for large files
- Progress reporting for long imports
- Custom format plugins
- Import validation and preview 