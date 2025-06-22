# CacheManager Module

The `CacheManager` module provides centralized cache management for Categories and Tasks in the Meaning To app. It can handle both saved Categories from the database and new unsaved Categories with their Tasks.

## Features

- **Dual Mode Support**: Works with both saved and unsaved Categories
- **Automatic Database Sync**: Handles database operations automatically for saved Categories
- **Local Cache Management**: Manages unsaved Categories and Tasks in memory
- **Task Operations**: Add, update, remove, finish, and reject tasks
- **Smart Sorting**: Automatically sorts tasks (unfinished first, then by suggestibleAt)
- **Random Task Selection**: Get random unfinished tasks for suggestion
- **Import/Export**: Export cache to JSON files and import from JSON files
- **Cache Validation**: Validate cache consistency and get statistics

## Usage

### Initializing with a Saved Category

```dart
final cacheManager = CacheManager();

// Initialize with a category from the database
await cacheManager.initializeWithSavedCategory(savedCategory, userId);

// Access cached data
print('Category: ${cacheManager.currentCategory?.headline}');
print('Task count: ${cacheManager.taskCount}');
print('Unfinished tasks: ${cacheManager.unfinishedTaskCount}');
```

### Initializing with an Unsaved Category

```dart
final cacheManager = CacheManager();

// Create a new unsaved category and tasks
final unsavedCategory = Category(
  id: -1, // Temporary ID
  headline: 'New Movie List',
  ownerId: userId,
  createdAt: DateTime.now(),
);

final unsavedTasks = [
  Task(
    id: -1,
    categoryId: -1,
    headline: 'The Matrix',
    notes: 'Classic sci-fi movie',
    ownerId: userId,
    createdAt: DateTime.now(),
    finished: false,
  ),
  // ... more tasks
];

// Initialize cache with unsaved data
cacheManager.initializeWithUnsavedCategory(unsavedCategory, unsavedTasks, userId);

// Save to database when ready
final savedCategory = await cacheManager.saveUnsavedCategory();
```

### Task Operations

```dart
// Add a new task
final newTask = Task(/* ... */);
await cacheManager.addTask(newTask);

// Update an existing task
final updatedTask = Task(/* ... */);
await cacheManager.updateTask(updatedTask);

// Remove a task
await cacheManager.removeTask(taskId);

// Mark task as finished
await cacheManager.finishTask(taskId);

// Reject/defer a task
await cacheManager.rejectTask(taskId);

// Get a random unfinished task
final randomTask = cacheManager.getRandomUnfinishedTask();
```

### Export and Import

```dart
// Export cache to default location (with timestamp)
final exportPath = await cacheManager.exportToDefaultLocation();
print('Exported to: $exportPath');

// Export to custom location
final customPath = '/path/to/custom/export.json';
await cacheManager.exportToJson(customPath);

// Import from JSON file
final importSuccess = await cacheManager.importFromJson('/path/to/export.json');
if (importSuccess) {
  print('Import successful');
  print('Imported category: ${cacheManager.currentCategory?.headline}');
  print('Imported tasks: ${cacheManager.taskCount}');
}

// Import from JSON text block
const jsonText = '''
{
  "exportedAt": "2024-01-15T10:30:00.000Z",
  "category": {
    "id": 1,
    "headline": "My Category",
    "owner_id": "user123",
    "created_at": "2024-01-15T10:00:00.000Z"
  },
  "tasks": [
    {
      "id": 1,
      "category_id": 1,
      "headline": "My Task",
      "owner_id": "user123",
      "created_at": "2024-01-15T10:00:00.000Z",
      "finished": false
    }
  ],
  "userId": "user123",
  "isUnsavedCategory": false
}
''';

final importSuccess = await cacheManager.importFromJson(jsonText);
if (importSuccess) {
  print('Text import successful');
}

// Get available export files
final availableExports = await cacheManager.getAvailableExports();
print('Available exports: ${availableExports.length}');

// Delete an export file
await cacheManager.deleteExport(exportPath);
```

### Cache Management

```dart
// Check if cache is initialized
if (cacheManager.isInitialized) {
  // Cache is ready to use
}

// Get cache statistics
final stats = cacheManager.getCacheStats();
print('Cache stats: $stats');

// Validate cache consistency
final isValid = cacheManager.validateCache();
if (!isValid) {
  print('Cache validation failed');
}

// Clear the cache
cacheManager.clearCache();

// Check if current category is unsaved
if (cacheManager.isUnsavedCategory) {
  // Handle unsaved state
}
```

## Key Methods

### Initialization
- `initializeWithSavedCategory(Category, String)`: Load saved category and tasks from database
- `initializeWithUnsavedCategory(Category, List<Task>, String)`: Initialize with unsaved data
- `saveUnsavedCategory()`: Save unsaved category and tasks to database

### Task Management
- `addTask(Task)`: Add a new task
- `updateTask(Task)`: Update an existing task
- `removeTask(int)`: Remove a task by ID
- `finishTask(int)`: Mark a task as finished
- `rejectTask(int)`: Reject/defer a task

### Data Access
- `getRandomUnfinishedTask()`: Get a random unfinished task
- `currentCategory`: Get the current category
- `currentTasks`: Get the list of current tasks
- `taskCount`: Get the total number of tasks
- `unfinishedTaskCount`: Get the number of unfinished tasks

### Export/Import
- `exportToJson(String)`: Export cache to specified JSON file
- `exportToDefaultLocation()`: Export to default location with timestamp
- `importFromJson(String)`: Import cache from JSON file or JSON text block
- `getAvailableExports()`: Get list of available export files
- `deleteExport(String)`: Delete an export file

### Cache Control
- `clearCache()`: Clear all cached data
- `isInitialized`: Check if cache is initialized
- `isUnsavedCategory`: Check if current category is unsaved
- `getCacheStats()`: Get cache statistics
- `validateCache()`: Validate cache consistency

## Export File Format

The export JSON file contains the following structure:

```json
{
  "exportedAt": "2024-01-15T10:30:00.000Z",
  "category": {
    "id": 1,
    "headline": "My Category",
    "invitation": "Optional invitation text",
    "owner_id": "user123",
    "created_at": "2024-01-15T10:00:00.000Z",
    "updated_at": null,
    "original_id": 1,
    "triggers_at": null,
    "template": null
  },
  "tasks": [
    {
      "id": 1,
      "category_id": 1,
      "headline": "Task Title",
      "notes": "Task description",
      "owner_id": "user123",
      "created_at": "2024-01-15T10:00:00.000Z",
      "suggestible_at": "2024-01-15T10:00:00.000Z",
      "triggers_at": null,
      "deferral": null,
      "links": null,
      "finished": false
    }
  ],
  "userId": "user123",
  "isUnsavedCategory": false,
  "metadata": {
    "taskCount": 1,
    "unfinishedTaskCount": 1,
    "version": "1.0"
  }
}
```

## Benefits

1. **Unified Interface**: Single interface for both saved and unsaved data
2. **Automatic Persistence**: Handles database operations transparently
3. **Memory Efficiency**: Manages data in memory for better performance
4. **Data Consistency**: Ensures cache and database stay in sync
5. **Error Handling**: Comprehensive error handling and logging
6. **Flexible Usage**: Supports various use cases from simple caching to complex workflows
7. **Data Portability**: Export/import functionality for backup and sharing
8. **Cache Validation**: Built-in validation to ensure data integrity

## Integration

The CacheManager can be integrated into existing screens and workflows:

- **EditCategoryScreen**: Use for managing both saved and new categories
- **HomeScreen**: Use for loading and managing category data
- **TaskEditScreen**: Use for task operations
- **Import flows**: Use for managing imported data before saving
- **Backup/Restore**: Use export/import for data backup and restoration
- **Data Migration**: Use for moving data between different instances

## Example Integration

```dart
class MyScreen extends StatefulWidget {
  @override
  _MyScreenState createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  final CacheManager _cacheManager = CacheManager();
  
  @override
  void initState() {
    super.initState();
    _initializeCache();
  }
  
  Future<void> _initializeCache() async {
    if (widget.category != null) {
      // Load saved category
      await _cacheManager.initializeWithSavedCategory(
        widget.category!, 
        userId
      );
    } else {
      // Initialize with new unsaved category
      final newCategory = Category(/* ... */);
      _cacheManager.initializeWithUnsavedCategory(
        newCategory, 
        [], 
        userId
      );
    }
    setState(() {});
  }
  
  Future<void> _exportCache() async {
    try {
      final exportPath = await _cacheManager.exportToDefaultLocation();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cache exported to: $exportPath')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }
  
  Future<void> _importCache() async {
    // Show file picker and import selected file
    // Implementation depends on your file picker library
  }
  
  // Use cacheManager throughout the widget...
}
``` 