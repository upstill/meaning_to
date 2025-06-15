import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:meaning_to/models/category.dart' as models;
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/widgets/link_display.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' hide Category;

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
  final models.Category category;
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
        category: args?['category'] as models.Category,
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
    } else {
      // If no jsonData provided, we'll wait for user to pick a file
      _loadExistingTasks();
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
        print(
            'Skipping $title because it already exists in task #${task.id}: ${task.headline}');
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
          processedLinks: null, // Will be processed when needed
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
                final fullPath = 'https://www.justwatch.com' +
                    (content['fullPath']?.toString() ?? '');
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
        print(
            'First task: ${tasks.isNotEmpty ? tasks.first.headline : "none"}');
        print(
            'First task links: ${tasks.isNotEmpty ? tasks.first.links : "none"}');

        setState(() {
          _matchingItems = items;
          _tasks = tasks;
          _isLoading = false;
        });
      } else {
        print(
            'Invalid JSON format: expected a list, got ${jsonData.runtimeType}');
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

  Future<void> _pickAndParseFile() async {
    try {
      print('Starting file pick in ImportJustWatchScreen...');
      setState(() {
        _isLoading = true;
        _error = null;
        _selectedFileName = null;
        _matchingItems = [];
        _tasks = [];
      });

      // Request permissions first (only on Android)
      if (Platform.isAndroid) {
        try {
          await _requestAndroidPermissions();
        } catch (e) {
          print('Permission error: $e');
          setState(() {
            _error = e.toString();
            _isLoading = false;
          });
          return;
        }
      }

      try {
        // Use file_selector to pick a file
        print('Opening file picker...');
        final typeGroup = XTypeGroup(
          label: 'JSON',
          extensions: ['json'],
          mimeTypes: ['application/json'],
        );

        final file = await openFile(
          acceptedTypeGroups: [typeGroup],
        ).catchError((error) {
          print('Error opening file picker: $error');
          throw Exception('Failed to open file picker: $error');
        });

        if (file == null) {
          print('No file selected');
          setState(() {
            _isLoading = false;
          });
          return;
        }

        print('File selected: ${file.name}');

        // Read and parse the file content
        final contents = await file.readAsString();
        print('File contents length: ${contents.length}');

        dynamic jsonData;
        try {
          jsonData = json.decode(contents);
          print('JSON decoded successfully');
          print('JSON type: ${jsonData.runtimeType}');
          if (jsonData is List) {
            print('JSON is a list with ${jsonData.length} items');
          }
        } catch (e) {
          print('Error decoding JSON: $e');
          setState(() {
            _error = 'Invalid JSON file: $e';
            _isLoading = false;
          });
          return;
        }

        setState(() {
          _selectedFileName = file.name;
        });

        await _parseJsonData(jsonData);
      } catch (e) {
        print('Error in file processing: $e');
        setState(() {
          _error = 'Error processing file: $e';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error in _pickAndParseFile: $e');
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _requestAndroidPermissions() async {
    if (!Platform.isAndroid) return;

    print('Checking Android permissions...');

    // For Android 13+ (API 33+)
    if (await Permission.photos.status.isGranted &&
        await Permission.videos.status.isGranted &&
        await Permission.audio.status.isGranted) {
      print('Media permissions already granted');
      return;
    }

    // Request media permissions for Android 13+
    if (await Permission.photos.request().isGranted &&
        await Permission.videos.request().isGranted &&
        await Permission.audio.request().isGranted) {
      print('Media permissions granted');
      return;
    }

    // For Android 12 and below
    if (await Permission.storage.status.isGranted) {
      print('Storage permission already granted');
      return;
    }

    // Request storage permission for Android 12 and below
    final storageStatus = await Permission.storage.request();
    if (storageStatus.isGranted) {
      print('Storage permission granted');
      return;
    }

    // If we get here, permissions were denied
    print('All permissions denied');
    throw Exception('Storage permission is required to browse files');
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
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open, size: 28),
            onPressed: _isLoading ? null : _pickAndParseFile,
            tooltip: 'Browse JSON Files',
            color: Colors.blue.shade700,
          ),
        ],
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
              'Import your ${widget.category.originalId == 1 ? 'movies' : 'TV shows'} from JustWatch for "${widget.category.headline}".',
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
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.folder_open, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Browse JSON File',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _pickAndParseFile,
                      icon: const Icon(Icons.folder_open, size: 24),
                      label: const Text('Select JSON File',
                          style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 24),
                        backgroundColor: Colors.blue.shade100,
                        foregroundColor: Colors.blue.shade900,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ] else ...[
              if (_matchingItems.isNotEmpty) ...[
                Text('Got ${_matchingItems.length} items to import:'),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: _matchingItems.length,
                    itemBuilder: (context, index) {
                      if (index >= _matchingItems.length ||
                          index >= _tasks.length) {
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
                              if (task.links != null &&
                                  task.links!.isNotEmpty) ...[
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: task.links!
                                      .map((link) => Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 4.0),
                                            child: LinkDisplayWidget(
                                              key: ValueKey(
                                                  'link_${task.id}_$link'),
                                              linkText: link,
                                              showIcon: true,
                                              showTitle: true,
                                            ),
                                          ))
                                      .toList(),
                                ),
                              ] else ...[
                                const Text('No links available',
                                    style: TextStyle(color: Colors.grey)),
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
                  child: Text("No matching items found in the file",
                      style: TextStyle(fontSize: 16)),
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

        print('Inserting task into database: ${task.headline}');
        print('Task data: $taskData');

        try {
          final response =
              await supabase.from('Tasks').insert(taskData).select().single();

          print(
              'Successfully inserted task: ${response['headline']} (ID: ${response['id']})');
        } catch (e) {
          print('Error inserting task ${task.headline}: $e');
          if (e is PostgrestException) {
            print('Postgrest error details: ${e.details}');
            print('Postgrest hint: ${e.hint}');
            print('Postgrest code: ${e.code}');
          }
          rethrow; // Re-throw to be caught by the outer try-catch
        }
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
