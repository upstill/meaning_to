import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/utils/text_importer.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/widgets/add_task_manually_button.dart';
import 'package:meaning_to/import_justwatch_screen.dart';
import 'package:meaning_to/edit_category_screen.dart';

class AddTasksScreen extends StatefulWidget {
  final Category category;
  final Task? currentTask; // Optional current task being edited

  const AddTasksScreen({
    super.key,
    required this.category,
    this.currentTask,
  });

  @override
  AddTasksScreenState createState() => AddTasksScreenState();
}

class AddTasksScreenState extends State<AddTasksScreen> {
  final _textInputController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _textInputController.addListener(() {
      setState(() {
        // Trigger rebuild when text changes to update button state
      });
    });
  }

  @override
  void dispose() {
    _textInputController.dispose();
    super.dispose();
  }

  /// Navigate to Edit Category screen for the cached category
  void _navigateToEditCategory() async {
    final cachedCategory = CacheManager().currentCategory;
    if (cachedCategory != null) {
      // Refresh the cache to include newly created tasks
      try {
        await CacheManager().refreshFromDatabase();
        print('AddTasksScreen: Cache refreshed before navigation');
      } catch (e) {
        print('AddTasksScreen: Error refreshing cache: $e');
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => EditCategoryScreen(category: cachedCategory),
        ),
      );
    } else {
      // Fallback to just popping if no cached category
      Navigator.pop(context, true);
    }
  }

  /// Check if a task with the same headline or same link already exists and merge information if needed
  Future<Task?> _checkForDuplicateAndMerge(
      Task newTask, List<Task> existingTasks) async {
    print('=== DUPLICATE DETECTION START ===');
    print('Checking for duplicates of: "${newTask.headline}"');
    print('New task links: ${newTask.links}');
    print('Existing tasks count: ${existingTasks.length}');
    print('Existing tasks:');
    for (final task in existingTasks) {
      print('  - "${task.headline}" (ID: ${task.id}, links: ${task.links})');
    }

    // First, check for tasks with the same headline
    Task? existingTask = existingTasks.firstWhere(
      (task) =>
          task.headline.toLowerCase().trim() ==
          newTask.headline.toLowerCase().trim(),
      orElse: () => newTask, // Return the new task if no duplicate found
    );

    // If no headline match found, check for tasks with the same link
    if (existingTask.id == newTask.id &&
        newTask.links != null &&
        newTask.links!.isNotEmpty) {
      print('No headline match found, checking for link matches...');

      for (final task in existingTasks) {
        print('  Checking task: "${task.headline}" (ID: ${task.id})');
        if (task.links != null && task.links!.isNotEmpty) {
          print('    Task has ${task.links!.length} links: ${task.links}');
          // Check if any of the new task's links match any of the existing task's links
          for (final newLink in newTask.links!) {
            print('    Checking new link: $newLink');
            for (final existingLink in task.links!) {
              print('    Against existing link: $existingLink');
              // Extract URLs from HTML links for comparison
              final newUrl = _extractUrlFromHtmlLink(newLink);
              final existingUrl = _extractUrlFromHtmlLink(existingLink);
              print('    Extracted new URL: $newUrl');
              print('    Extracted existing URL: $existingUrl');

              if (newUrl != null &&
                  existingUrl != null &&
                  newUrl == existingUrl) {
                print(
                    'Found existing task with matching link: "${task.headline}" (ID: ${task.id})');
                print('  New link: $newUrl');
                print('  Existing link: $existingUrl');
                existingTask = task;
                break;
              }
            }
            if (existingTask!.id != newTask.id) break;
          }
          if (existingTask!.id != newTask.id) break;
        } else {
          print('    Task has no links');
        }
      }
    }

    print(
        'Found existing task: "${existingTask!.headline}" (ID: ${existingTask.id})');
    print('New task: "${newTask.headline}" (ID: ${newTask.id})');
    print('Are they the same? ${existingTask.id == newTask.id}');

    if (existingTask.id != newTask.id) {
      // Found a duplicate - merge information
      print('Found duplicate task: "${newTask.headline}"');
      print('=== DUPLICATE DETECTION END - DUPLICATE FOUND ===');

      // Check if we need to update the existing task with new information
      bool needsUpdate = false;
      Map<String, dynamic> updateData = {};

      // Add links if the new task has them and the existing task doesn't
      if (newTask.links != null &&
          newTask.links!.isNotEmpty &&
          (existingTask.links == null || existingTask.links!.isEmpty)) {
        updateData['links'] = newTask.links;
        needsUpdate = true;
        print('  -> Adding links to existing task');
      }

      // Add notes if the new task has them and the existing task doesn't
      if (newTask.notes != null &&
          newTask.notes!.isNotEmpty &&
          (existingTask.notes == null || existingTask.notes!.isEmpty)) {
        updateData['notes'] = newTask.notes;
        needsUpdate = true;
        print('  -> Adding notes to existing task');
      }

      // Always update the existing task to move it to the top of the list
      // Set suggestibleAt to null to make it appear first
      try {
        final userId = AuthUtils.getCurrentUserId();

        // Add suggestibleAt: null to the update data to move task to top
        updateData['suggestible_at'] = null;

        await supabase
            .from('Tasks')
            .update(updateData)
            .eq('id', existingTask.id)
            .eq('owner_id', userId);

        print('  -> Updated existing task and moved to top of list');

        // Return the updated existing task
        return Task(
          id: existingTask.id,
          categoryId: existingTask.categoryId,
          ownerId: existingTask.ownerId,
          headline: existingTask.headline,
          notes: updateData['notes'] ?? existingTask.notes,
          links: updateData['links'] ?? existingTask.links,
          processedLinks: existingTask.processedLinks,
          createdAt: existingTask.createdAt,
          suggestibleAt: null, // Set to null to move to top
          finished: existingTask.finished,
        );
      } catch (e) {
        print('Error updating existing task: $e');
        return existingTask; // Return existing task without changes on error
      }
    } else {
      print('=== DUPLICATE DETECTION END - NO DUPLICATE FOUND ===');
    }

    return null; // No duplicate found
  }

  /// Extract URL from HTML link string
  String? _extractUrlFromHtmlLink(String htmlLink) {
    print('    _extractUrlFromHtmlLink called with: "$htmlLink"');
    if (htmlLink.startsWith('<a href="') && htmlLink.contains('">')) {
      final startIndex = htmlLink.indexOf('href="') + 6;
      final endIndex = htmlLink.indexOf('">', startIndex);
      if (endIndex > startIndex) {
        final url = htmlLink.substring(startIndex, endIndex);
        print('    Extracted URL from HTML: "$url"');
        return url;
      }
    }
    // If it's not an HTML link, return as is (might be a plain URL)
    if (htmlLink.startsWith('http')) {
      print('    Using plain URL: "$htmlLink"');
      return htmlLink;
    }
    print('    No valid URL found in: "$htmlLink"');
    return null;
  }

  Future<void> _processTextInput() async {
    print('=== _processTextInput START ===');
    print('Input text: "${_textInputController.text}"');

    if (_textInputController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter some text to create tasks'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      final userId = AuthUtils.getCurrentUserId();

      // Get existing tasks for duplicate checking - refresh cache first
      print('AddTasksScreen: About to refresh cache...');
      print(
          'AddTasksScreen: Category: ${widget.category.headline} (ID: ${widget.category.id})');
      print('AddTasksScreen: User ID: $userId');

      // Initialize cache manager with current category and user
      final cacheManager = CacheManager();
      print('AddTasksScreen: CacheManager created, about to initialize...');
      await cacheManager.initializeWithSavedCategory(widget.category, userId);
      print('AddTasksScreen: Cache initialization completed');

      final existingTasks = cacheManager.currentTasks ?? [];

      // If we have a current task being edited, create a copy with its current state
      // and add it to the list for duplicate checking
      List<Task> tasksForDuplicateChecking = List.from(existingTasks);
      if (widget.currentTask != null) {
        print(
            'AddTasksScreen: Including current task in duplicate checking: "${widget.currentTask!.headline}"');
        print(
            'AddTasksScreen: Current task links: ${widget.currentTask!.links}');
        tasksForDuplicateChecking.add(widget.currentTask!);
      }

      print(
          'AddTasksScreen: Existing tasks for duplicate checking: ${existingTasks.length}');
      print(
          'AddTasksScreen: Including current task: ${widget.currentTask != null}');
      print(
          'AddTasksScreen: Total tasks for duplicate checking: ${tasksForDuplicateChecking.length}');
      print(
          'AddTasksScreen: CacheManager currentCategory: ${cacheManager.currentCategory?.headline}');
      print(
          'AddTasksScreen: CacheManager currentUserId: ${cacheManager.currentUserId}');
      for (final task in tasksForDuplicateChecking) {
        print('  - "${task.headline}" (ID: ${task.id})');
        print('    Links: ${task.links}');
        print('    Links type: ${task.links?.runtimeType}');
        print('    Links length: ${task.links?.length ?? 0}');
        if (task.links != null && task.links!.isNotEmpty) {
          for (int i = 0; i < task.links!.length; i++) {
            print('      Link $i: "${task.links![i]}"');
          }
        }
      }

      // Check if the input is a single URL
      final trimmedText = _textInputController.text.trim();
      print('Checking if "$trimmedText" is a valid URL...');
      print(
          'LinkProcessor.isValidUrl result: ${LinkProcessor.isValidUrl(trimmedText)}');

      if (LinkProcessor.isValidUrl(trimmedText)) {
        // Single URL detected - process it through LinkProcessor
        print('Single URL detected: $trimmedText');
        print('Taking single URL processing path...');

        try {
          print('AddTasksScreen: Processing URL: $trimmedText');
          final processedLink = await LinkProcessor.validateAndProcessLink(
            trimmedText,
            linkText: '', // Let LinkProcessor fetch the title
          );

          // Create a task object for duplicate checking
          final newTask = Task(
            id: DateTime.now().millisecondsSinceEpoch, // Temporary ID
            categoryId: widget.category.id,
            headline: processedLink.title ?? 'Link Task',
            notes: null,
            ownerId: userId,
            createdAt: DateTime.now(),
            suggestibleAt: null, // Set to null to appear at the beginning
            links: [
              processedLink.originalLink
            ], // Store the processed HTML link with title
            processedLinks: null,
            finished: false,
          );

          print(
              'AddTasksScreen: Creating task with headline: "${newTask.headline}"');
          print('AddTasksScreen: Task links: ${newTask.links}');
          print('AddTasksScreen: About to call duplicate detection...');

          // Check for duplicates and merge information if needed
          final existingOrUpdatedTask = await _checkForDuplicateAndMerge(
              newTask, tasksForDuplicateChecking);

          print('Duplicate check result for "${newTask.headline}":');
          print(
              '  existingOrUpdatedTask: ${existingOrUpdatedTask?.headline} (ID: ${existingOrUpdatedTask?.id})');
          print('  newTask.id: ${newTask.id}');
          print('  existingOrUpdatedTask?.id: ${existingOrUpdatedTask?.id}');
          print(
              '  isDuplicate: ${existingOrUpdatedTask != null && existingOrUpdatedTask.id != newTask.id}');

          if (existingOrUpdatedTask != null &&
              existingOrUpdatedTask.id != newTask.id) {
            // This was a duplicate - existing task was updated or found
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Updated existing task: "${existingOrUpdatedTask.headline}"'),
                backgroundColor: Colors.blue,
              ),
            );
          } else {
            // No duplicate found - create new task
            final taskData = {
              'headline': newTask.headline,
              'notes': newTask.notes,
              'category_id': newTask.categoryId,
              'owner_id': newTask.ownerId,
              'links': newTask.links,
              'suggestible_at': newTask.suggestibleAt?.toIso8601String(),
            };
            await supabase.from('Tasks').insert(taskData);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Created task: "${newTask.headline}"'),
                backgroundColor: Colors.green,
              ),
            );
          }

          // Clear the text input
          _textInputController.clear();

          // Navigate to Edit Category screen for cached category
          if (mounted) {
            _navigateToEditCategory();
          }
          return;
        } catch (e) {
          print('Error processing single URL: $e');

          // If URL processing fails, create a task with the URL as the title
          // This is better than falling back to text processing which can create malformed tasks
          final newTask = Task(
            id: DateTime.now().millisecondsSinceEpoch, // Temporary ID
            categoryId: widget.category.id,
            headline: trimmedText, // Use the URL as the title
            notes: 'Failed to fetch webpage title',
            ownerId: userId,
            createdAt: DateTime.now(),
            suggestibleAt: null, // Set to null to appear at the beginning
            links: [trimmedText], // Store the original URL
            processedLinks: null,
            finished: false,
          );

          // Check for duplicates and merge information if needed
          final existingOrUpdatedTask = await _checkForDuplicateAndMerge(
              newTask, tasksForDuplicateChecking);

          if (existingOrUpdatedTask != null &&
              existingOrUpdatedTask.id != newTask.id) {
            // This was a duplicate - existing task was updated or found
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Updated existing task: "${existingOrUpdatedTask.headline}"'),
                backgroundColor: Colors.blue,
              ),
            );
          } else {
            // No duplicate found - create new task
            final taskData = {
              'headline': newTask.headline,
              'notes': newTask.notes,
              'category_id': newTask.categoryId,
              'owner_id': newTask.ownerId,
              'links': newTask.links,
              'suggestible_at': newTask.suggestibleAt?.toIso8601String(),
            };
            await supabase.from('Tasks').insert(taskData);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Created task with URL: "${newTask.headline}"'),
                backgroundColor: Colors.orange,
              ),
            );
          }

          // Clear the text input
          _textInputController.clear();

          // Navigate to Edit Category screen for cached category
          if (mounted) {
            _navigateToEditCategory();
          }
          return;
        }
      }

      // Use TextImporter to process the text input
      final tasksToProcess = <Task>[];
      final now = DateTime.now();
      int taskIndex = 0;

      await for (final task in TextImporter.processForNewCategory(
        _textInputController.text,
        category: widget.category,
        ownerId: userId,
      )) {
        // Set suggestibleAt to null so new tasks appear at the beginning
        // Tasks with null suggestibleAt are sorted first in the list

        final modifiedTask = Task(
          id: task.id,
          categoryId: task.categoryId,
          ownerId: task.ownerId,
          headline: task.headline,
          notes: task.notes,
          links: task.links,
          processedLinks: task.processedLinks,
          createdAt: task.createdAt,
          suggestibleAt: null, // Set to null to appear at the beginning
          finished: task.finished,
        );

        tasksToProcess.add(modifiedTask);
        taskIndex++;
      }

      if (tasksToProcess.isEmpty) {
        throw Exception('No valid tasks found in text input');
      }

      // Process tasks with duplicate checking
      int newTasksCreated = 0;
      int existingTasksUpdated = 0;

      for (final task in tasksToProcess) {
        print('Processing task: "${task.headline}" (ID: ${task.id})');

        // Check for duplicates and merge information if needed
        final existingOrUpdatedTask =
            await _checkForDuplicateAndMerge(task, tasksForDuplicateChecking);

        print('Duplicate check result for "${task.headline}":');
        print(
            '  existingOrUpdatedTask:  [${existingOrUpdatedTask?.headline} (ID: ${existingOrUpdatedTask?.id})');
        print('  task.id: ${task.id}');
        print('  existingOrUpdatedTask?.id: ${existingOrUpdatedTask?.id}');
        print(
            '  isDuplicate: ${existingOrUpdatedTask != null && existingOrUpdatedTask.id != task.id}');

        if (existingOrUpdatedTask != null &&
            existingOrUpdatedTask.id != task.id) {
          // This was a duplicate - existing task was updated or found
          existingTasksUpdated++;
          print('Skipped duplicate task: "${task.headline}"');
        } else {
          // No duplicate found - create new task
          final taskData = {
            'headline': task.headline,
            'notes': task.notes,
            'category_id': widget.category.id,
            'owner_id': userId,
            'links': task.links,
            'suggestible_at': task.suggestibleAt?.toIso8601String(),
          };
          await supabase.from('Tasks').insert(taskData);
          newTasksCreated++;
          print('Created new task: "${task.headline}"');
        }
      }

      // Show appropriate success message
      String message;
      if (newTasksCreated > 0 && existingTasksUpdated > 0) {
        message =
            'Created $newTasksCreated new tasks and updated $existingTasksUpdated existing tasks';
      } else if (newTasksCreated > 0) {
        message = 'Created $newTasksCreated new tasks';
      } else if (existingTasksUpdated > 0) {
        message =
            'Updated $existingTasksUpdated existing tasks (no duplicates created)';
      } else {
        message = 'No new tasks created';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
        ),
      );

      // Clear the text input
      _textInputController.clear();

      // Navigate to Edit Category screen for cached category
      if (mounted) {
        _navigateToEditCategory();
      }
    } catch (e) {
      print('=== Text Input Error ===');
      print('Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            'Add ${NamingUtils.tasksName()} to ${widget.category.headline}'),
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
            // Task creation section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add ${NamingUtils.tasksName(plural: true)}:',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'List one or more tasks, one per line:',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _textInputController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText:
                            '${NamingUtils.tasksName()} 1\n${NamingUtils.tasksName()} 2: A great ${NamingUtils.tasksName(capitalize: false, plural: false)}\n${NamingUtils.tasksName()} 3: https://example.com/${NamingUtils.tasksName(capitalize: false, plural: false)}3',
                        border: const OutlineInputBorder(),
                        labelText:
                            'Paste ${NamingUtils.tasksName(plural: true)} here',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ||
                                _textInputController.text.trim().isEmpty
                            ? null
                            : _processTextInput,
                        icon: _isLoading
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add_task),
                        label: Text(_isLoading
                            ? 'Adding...'
                            : 'Make ${NamingUtils.tasksName(plural: true)}'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Tips:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '• Enter one ${NamingUtils.tasksName(capitalize: false, plural: false)} per line\n'
              '• Use "${NamingUtils.tasksName()}: Note" format to include a note\n'
              '• Pasting a Share from elsewhere will do the right thing\n'
              '• Ditto a URL (address-bar gobbledygook from a web page)\n'
              '• New ${NamingUtils.tasksName(plural: true)} will appear at the beginning of your list',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            // Single task addition section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'For adding a single ${NamingUtils.tasksName(capitalize: false, plural: false)}:',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: AddTaskManuallyButton(
                        category: widget.category,
                        isLoading: _isLoading,
                        onTaskAdded: () {
                          setState(() {
                            // Refresh the UI after task is added
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
