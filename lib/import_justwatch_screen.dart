import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/link_processor.dart';

class JustWatchItem {
  final String title;
  final String fullPath;

  JustWatchItem({
    required this.title,
    required this.fullPath,
  });

  @override
  String toString() => 'JustWatchItem(title: $title, fullPath: $fullPath)';
}

class ImportJustWatchScreen extends StatefulWidget {
  final Category category;
  final dynamic jsonData;

  const ImportJustWatchScreen({
    super.key,
    required this.category,
    this.jsonData,
  });

  static Route routeFromArgs(RouteSettings settings) {
    print('ImportJustWatchScreen: routeFromArgs called');
    final args = settings.arguments as Map<String, dynamic>?;
    print('ImportJustWatchScreen: Arguments: $args');
    return MaterialPageRoute(
      builder: (_) => ImportJustWatchScreen(
        category: args?['category'] as Category,
        jsonData: args?['jsonData'],
      ),
      settings: settings,
    );
  }

  @override
  State<ImportJustWatchScreen> createState() => _ImportJustWatchScreenState();
}

class _ImportJustWatchScreenState extends State<ImportJustWatchScreen> {
  bool _isLoading = false;
  String? _error;
  String? _selectedFileName;
  List<JustWatchItem> _matchingItems = [];
  List<Task> _tasks = [];

  @override
  void initState() {
    super.initState();
    print('ImportJustWatchScreen: initState called');
    print('ImportJustWatchScreen: Category: ${widget.category.headline}');
    if (widget.jsonData != null) {
      _parseJsonData(widget.jsonData);
    }
  }

  /// Returns true if the item should be included, false to filter it out.
  /// Override this method to implement custom filtering logic.
  bool filterJustWatchItem(String title, String fullLink) {
    // Check each existing task
    for (var task in _tasks) {
      // If task already has this link, skip it
      if (task.links?.any((link) => link.contains(fullLink)) ?? false) {
        print('Skipping $title because it already exists in task #${task.id}: ${task.headline}');
        return false;
      }
      
      // If task has matching headline, add this link to its links
      if (task.headline == title) {
        print('Adding $fullLink to task #${task.id}: ${task.headline}');
        task.links?.add(fullLink);
        return false;
      }
    }
    
    // No matches found, include this item
    return true;
  }

  void _parseJsonData(dynamic jsonData) {
    setState(() {
      _isLoading = true;
      _error = null;
      _selectedFileName = "Imported from Edit Screen";
      _matchingItems = [];
      _tasks = [];
    });
    try {
      // Map category's original_id to target_type
      final targetType = widget.category.originalId == 1 ? 'MOVIE' : 'SHOW';
      print('Processing for [38;5;2m${targetType}s[0m');
      if (jsonData is List) {
        int totalNodes = 0;
        int matchingNodes = 0;
        final List<JustWatchItem> items = [];
        final List<Task> tasks = [];
        for (var item in jsonData) {
          if (item is Map && item.containsKey('node')) {
            final node = item['node'];
            if (node is Map) {
              final objectType = node['objectType'];
              totalNodes++;
              if (objectType?.toString().toUpperCase() != targetType) {
                continue;
              }
              matchingNodes++;
              final content = node['content'];
              if (content is Map) {
                final title = content['title'];
                final fullPath = 'https://www.justwatch.com' + content['fullPath'];
                final htmlLink = '<a href="$fullPath">$title</a>';
                if (!filterJustWatchItem(title.toString(), htmlLink)) {
                  continue;
                }
                items.add(JustWatchItem(
                  title: title.toString(),
                  fullPath: fullPath,
                ));
                tasks.add(Task(
                  id: -1,
                  categoryId: widget.category.id,
                  headline: title.toString(),
                  notes: null,
                  ownerId: '',
                  createdAt: DateTime.now(),
                  suggestibleAt: DateTime.now(),
                  triggersAt: null,
                  deferral: null,
                  links: [htmlLink],
                  processedLinks: null,
                  finished: false,
                ));
              }
            }
          }
        }
        items.sort((a, b) => a.title.compareTo(b.title));
        tasks.sort((a, b) => a.headline.compareTo(b.headline));
        setState(() {
          _matchingItems = items;
          _tasks = tasks;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Invalid JSON format: expected a list';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error parsing JSON: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import JustWatch List'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Import ${widget.category.originalId == 1 ? 'Movies' : 'TV Shows'}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Import your ${widget.category.originalId == 1 ? 'movies' : 'TV shows'} from JustWatch to create tasks in "${widget.category.headline}".',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Text(
                'Error: $_error',
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
            ],
            if (_selectedFileName != null) ...[
              Text('Selected file: $_selectedFileName'),
              const SizedBox(height: 16),
              if (_matchingItems.isNotEmpty) ...[
                Text('Found ${_matchingItems.length} items to import'),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: _matchingItems.length,
                    itemBuilder: (context, index) {
                      final item = _matchingItems[index];
                      return ListTile(
                        title: Text(item.title),
                        subtitle: Text(item.fullPath),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isLoading ? null : _importItems,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Import Items'),
                ),
              ],
            ] else ...[
              const Spacer(),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.movie,
                      size: 64,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Select your JustWatch export file to begin',
                      style: TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : () {
                        // No-op since file picking is now handled in edit screen
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please pick a file from the edit screen')),
                        );
                      },
                      icon: const Icon(Icons.file_open),
                      label: const Text('Pick a file (use edit screen)'),
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _importItems() async {
    // TODO: Implement importing items
    Navigator.pop(context, widget.category);
  }
} 