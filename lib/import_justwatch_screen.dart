import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/widgets/link_display.dart';

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
    print('Starting _parseJsonData');
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
      print('Processing for ${targetType}s');
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
                final title = content['title']?.toString() ?? 'Unknown Title';
                final fullPath = 'https://www.justwatch.com' + (content['fullPath']?.toString() ?? '');
                print('Processing item: $title with path: $fullPath');
                
                // Create both JustWatch and IMDB links
                final justWatchLink = '<a href="$fullPath">$title</a>';
                
                if (!filterJustWatchItem(title, justWatchLink)) {
                  print('Skipping $title - already exists');
                  continue;
                }
                
                print('Adding item: $title with link: $justWatchLink');
                items.add(JustWatchItem(
                  title: title,
                  fullPath: fullPath,
                ));
                tasks.add(Task(
                  id: -1,
                  categoryId: widget.category.id,
                  headline: title,
                  notes: null,
                  ownerId: '',
                  createdAt: DateTime.now(),
                  suggestibleAt: DateTime.now(),
                  triggersAt: null,
                  deferral: null,
                  links: [justWatchLink],
                  processedLinks: null,
                  finished: false,
                ));
              }
            }
          }
        }
        items.sort((a, b) => a.title.compareTo(b.title));
        tasks.sort((a, b) => a.headline.compareTo(b.headline));
        print('Found ${items.length} items to import');
        print('First item: ${items.isNotEmpty ? items.first.title : "none"}');
        print('First task: ${tasks.isNotEmpty ? tasks.first.headline : "none"}');
        print('First task links: ${tasks.isNotEmpty ? tasks.first.links : "none"}');
        
        setState(() {
          _matchingItems = items;
          _tasks = tasks;
          _isLoading = false;
        });
      } else {
        print('Invalid JSON format: expected a list, got ${jsonData.runtimeType}');
        setState(() {
          _error = 'Invalid JSON format: expected a list';
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      print('Error parsing JSON: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _error = 'Error parsing JSON: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    print('Building ImportJustWatchScreen');
    print('_matchingItems length: ${_matchingItems.length}');
    print('_tasks length: ${_tasks.length}');
    if (_tasks.isNotEmpty) {
      print('First task links: ${_tasks.first.links}');
    }
    
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
                      final task = _tasks[index];
                      print('Building item $index: ${item.title}');
                      print('Task links: ${task.links}');
                      
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              if (task.links != null && task.links!.isNotEmpty) ...[
                                LinkListDisplay(
                                  key: ValueKey('links_${task.id}_$index'),
                                  links: task.links!.map((link) => link.toString()).toList(),
                                ),
                              ] else ...[
                                const Text('No links available', style: TextStyle(color: Colors.grey)),
                              ],
                            ],
                          ),
                        ),
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
              const Center(
                child: Text("No imported data", style: TextStyle(fontSize: 16)),
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