import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/widgets/link_display.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  List<Task> _existingTasks = [];

  @override
  void initState() {
    super.initState();
    print('ImportJustWatchScreen: initState called');
    print('ImportJustWatchScreen: Category: ${widget.category.headline}');
    if (widget.jsonData != null) {
      _loadExistingTasks().then((_) {
        _parseJsonData(widget.jsonData);
      });
    }
  }

  Future<void> _loadExistingTasks() async {
    print('Loading existing tasks for category: ${widget.category.headline}');
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('No user logged in');
      }

      final response = await supabase
          .from('Tasks')
          .select()
          .eq('category_id', widget.category.id)
          .eq('owner_id', userId);

      if (response == null) {
        print('No existing tasks found');
        return;
      }

      final tasks = response
          .map((json) => Task.fromJson(json as Map<String, dynamic>))
          .toList();
      
      print('Loaded ${tasks.length} existing tasks');
      setState(() {
        _existingTasks = tasks;
      });
    } catch (e) {
      print('Error loading existing tasks: $e');
      // Don't throw - we can still proceed with import
    }
  }

  /// Returns true if the item should be included, false to filter it out.
  Future<bool> filterJustWatchItem(String title, String fullLink) async {
    // Check each existing task
    for (var task in _existingTasks) {
      // If task already has this link, skip it
      if (task.links?.any((link) => link.contains(fullLink)) ?? false) {
        print('Skipping $title because it already exists in task #${task.id}: ${task.headline}');
        return false;
      }
      
      // If task has matching headline, add this link to its links
      print('Checking task "${task.headline}" against "$title"');
      if (task.headline == title) {
        print('Adding $fullLink to task #${task.id}: ${task.headline}');
        
        // Create new list with existing links plus the new one
        final updatedLinks = [...?task.links, fullLink];
        
        // Create updated task
        final updatedTask = Task(
          id: task.id,
          categoryId: task.categoryId,
          headline: task.headline,
          notes: task.notes,
          ownerId: task.ownerId,
          createdAt: task.createdAt,
          suggestibleAt: task.suggestibleAt,
          triggersAt: task.triggersAt,
          deferral: task.deferral,
          links: updatedLinks,
          processedLinks: null,  // Will be processed when needed
          finished: task.finished,
        );
        
        // Update in database
        try {
          await supabase
              .from('Tasks')
              .update({'links': Task.linksToString(updatedLinks)})
              .eq('id', task.id)
              .eq('owner_id', task.ownerId);
          
          // Update in our local list
          final index = _existingTasks.indexWhere((t) => t.id == task.id);
          if (index != -1) {
            _existingTasks[index] = updatedTask;
          }
          
          print('Successfully updated task #${task.id} with new link');
        } catch (e) {
          print('Error updating task #${task.id}: $e');
          // Continue with import even if update fails
        }
        
        return false;
      }
    }
    
    // No matches found, include this item
    return true;
  }

  Future<void> _parseJsonData(dynamic jsonData) async {
    print('Starting _parseJsonData');
    print('Existing tasks count: ${_existingTasks.length}');
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
                
                if (!await filterJustWatchItem(title, justWatchLink)) {
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
            if (_selectedFileName == null) ...[
              const Spacer(),
              Center(
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : () async {
                    print('Pick a file button pressed in ImportJustWatchScreen');
                    try {
                      final file = await openFile(
                        acceptedTypeGroups: [
                          XTypeGroup(
                            label: 'JSON Files',
                            extensions: ['json'],
                            mimeTypes: ['application/json'],
                          ),
                        ],
                      );
                      
                      if (file == null) {
                        print('No file selected in ImportJustWatchScreen');
                        return;
                      }
                      
                      print('File picked in ImportJustWatchScreen: ${file.name}');
                      final contents = await file.readAsString();
                      print('File contents length: ${contents.length}');
                      
                      dynamic jsonData;
                      try {
                        jsonData = json.decode(contents);
                        print('JSON decoded successfully in ImportJustWatchScreen');
                        print('JSON type: ${jsonData.runtimeType}');
                        if (jsonData is List) {
                          print('JSON is a list with ${jsonData.length} items');
                        }
                      } catch (e) {
                        print('Error decoding JSON in ImportJustWatchScreen: $e');
                        if (mounted) {
                          setState(() {
                            _error = 'Invalid JSON file: $e';
                          });
                        }
                        return;
                      }
                      
                      if (mounted) {
                        setState(() {
                          _selectedFileName = file.name;
                          _isLoading = true;
                          _error = null;
                          _matchingItems = [];
                          _tasks = [];
                        });
                      }
                      
                      await _loadExistingTasks();
                      await _parseJsonData(jsonData);
                      
                      if (mounted) {
                        setState(() {
                          _isLoading = false;
                        });
                      }
                    } catch (e) {
                      print('Error picking file in ImportJustWatchScreen: $e');
                      if (mounted) {
                        setState(() {
                          _error = 'Error picking file: $e';
                          _isLoading = false;
                        });
                      }
                    }
                  },
                  icon: const Icon(Icons.file_upload),
                  label: const Text('Pick a file'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                    minimumSize: const Size(200, 48),
                  ),
                ),
              ),
              const Spacer(),
            ] else ...[
              Text('Selected file: $_selectedFileName'),
              const SizedBox(height: 16),
              if (_matchingItems.isNotEmpty) ...[
                Text('Found ${_matchingItems.length} items to import'),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: _matchingItems.length,
                    itemBuilder: (context, index) {
                      if (index >= _matchingItems.length || index >= _tasks.length) {
                        return const SizedBox.shrink();
                      }
                      
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
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: task.links!.map((link) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4.0),
                                    child: LinkDisplayWidget(
                                      key: ValueKey('link_${task.id}_$link'),
                                      linkText: link,
                                      showIcon: true,
                                      showTitle: true,
                                    ),
                                  )).toList(),
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
              ] else if (_selectedFileName != null) ...[
                const Center(
                  child: Text("No matching items found in the file", style: TextStyle(fontSize: 16)),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _importItems() async {
    if (_tasks.isEmpty) {
      print('No tasks to import');
      Navigator.pop(context, widget.category);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('No user logged in');
      }

      // Take first three tasks
      final tasksToImport = _tasks.take(3).toList();
      print('Importing ${tasksToImport.length} tasks:');
      for (var task in tasksToImport) {
        print('- ${task.headline}');
      }

      // Insert tasks into database
      for (var task in tasksToImport) {
        final taskData = {
          'category_id': task.categoryId,
          'headline': task.headline,
          'notes': task.notes,
          'owner_id': userId,
          'created_at': task.createdAt?.toIso8601String(),
          'suggestible_at': task.suggestibleAt?.toIso8601String(),
          'triggers_at': task.triggersAt?.toIso8601String(),
          'deferral': task.deferral,
          'links': Task.linksToString(task.links ?? []),
          'finished': task.finished,
        };

        final response = await supabase
            .from('Tasks')
            .insert(taskData)
            .select()
            .single();

        print('Added task to database: ${task.headline}');
      }

      print('Successfully imported ${tasksToImport.length} tasks');
      Navigator.pop(context, widget.category);
    } catch (e) {
      print('Error importing tasks: $e');
      setState(() {
        _error = 'Error importing tasks: $e';
        _isLoading = false;
      });
    }
  }
} 