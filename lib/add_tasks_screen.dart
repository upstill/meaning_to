import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/text_importer.dart';
import 'package:meaning_to/utils/cache_manager.dart';

class AddTasksScreen extends StatefulWidget {
  final Category category;

  const AddTasksScreen({super.key, required this.category});

  @override
  AddTasksScreenState createState() => AddTasksScreenState();
}

class AddTasksScreenState extends State<AddTasksScreen> {
  final _textInputController = TextEditingController();
  final _linkInputController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _textInputController.addListener(() {
      setState(() {
        // Trigger rebuild when text changes to update button state
      });
    });
    _linkInputController.addListener(() {
      setState(() {
        // Trigger rebuild when text changes to update button state
      });
    });
  }

  @override
  void dispose() {
    _textInputController.dispose();
    _linkInputController.dispose();
    super.dispose();
  }

  /// Check if a task with the same headline already exists and merge information if needed
  Future<Task?> _checkForDuplicateAndMerge(
      Task newTask, List<Task> existingTasks) async {
    print('Checking for duplicates of: "${newTask.headline}"');
    print('Existing tasks:');
    for (final task in existingTasks) {
      print('  - "${task.headline}" (ID: ${task.id})');
    }

    final existingTask = existingTasks.firstWhere(
      (task) =>
          task.headline.toLowerCase().trim() ==
          newTask.headline.toLowerCase().trim(),
      orElse: () => newTask, // Return the new task if no duplicate found
    );

    print(
        'Found existing task: "${existingTask.headline}" (ID: ${existingTask.id})');
    print('New task: "${newTask.headline}" (ID: ${newTask.id})');
    print('Are they the same? ${existingTask.id == newTask.id}');

    if (existingTask.id != newTask.id) {
      // Found a duplicate - merge information
      print('Found duplicate task: "${newTask.headline}"');

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
        if (userId == null) throw Exception('No user logged in');

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
    }

    return null; // No duplicate found
  }

  Future<void> _processLinks() async {
    if (_linkInputController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter some text to process for links'),
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
      if (userId == null) {
        throw Exception('No user logged in');
      }

      // Get existing tasks for this category
      final existingTasks = CacheManager().currentTasks ?? [];
      final categoryTasks = existingTasks
          .where((task) => task.categoryId == widget.category.id)
          .toList();

      if (categoryTasks.isEmpty) {
        throw Exception('No tasks found in this category to add links to');
      }

      // Use TextImporter to process the text for links
      final tasksToProcess = <Task>[];

      await for (final task in TextImporter.processForNewCategory(
        _linkInputController.text,
        category: widget.category,
        ownerId: userId,
      )) {
        tasksToProcess.add(task);
      }

      if (tasksToProcess.isEmpty) {
        throw Exception('No valid links found in text input');
      }

      // For each processed task, find matching existing tasks and add links
      int linksAdded = 0;

      for (final newTask in tasksToProcess) {
        // Find existing tasks with matching headlines
        for (final existingTask in categoryTasks) {
          if (existingTask.headline.toLowerCase().trim() ==
              newTask.headline.toLowerCase().trim()) {
            // Check if the existing task needs links added
            if (newTask.links != null && newTask.links!.isNotEmpty) {
              List<String> updatedLinks =
                  List<String>.from(existingTask.links ?? []);

              // Add new links that aren't already present
              for (final newLink in newTask.links!) {
                if (!updatedLinks.contains(newLink)) {
                  updatedLinks.add(newLink);
                }
              }

              if (updatedLinks.length > (existingTask.links?.length ?? 0)) {
                // Update the task with new links
                await supabase
                    .from('Tasks')
                    .update({'links': updatedLinks})
                    .eq('id', existingTask.id)
                    .eq('owner_id', userId);

                linksAdded++;
                print('Added links to task: "${existingTask.headline}"');
              }
            }
          }
        }
      }

      // Show success message
      String message;
      if (linksAdded > 0) {
        message = 'Added links to $linksAdded tasks';
      } else {
        message = 'No new links were added (they may already exist)';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
        ),
      );

      // Clear the link input
      _linkInputController.clear();

      // Return success to trigger refresh
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('=== Link Processing Error ===');
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

  Future<void> _processTextInput() async {
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
      if (userId == null) {
        throw Exception('No user logged in');
      }

      // Get existing tasks for duplicate checking
      final existingTasks = CacheManager().currentTasks ?? [];

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
            await _checkForDuplicateAndMerge(task, existingTasks);

        print('Duplicate check result for "${task.headline}":');
        print(
            '  existingOrUpdatedTask: ${existingOrUpdatedTask?.headline} (ID: ${existingOrUpdatedTask?.id})');
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

      // Return success to trigger refresh
      if (mounted) {
        Navigator.pop(context, true);
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
        title: Text('Add Tasks to ${widget.category.headline}'),
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
                    const Text(
                      'Add Tasks:',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'List multiple tasks below (one per line) or add them individually:',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _textInputController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText:
                            'Task 1\nTask 2: A great task\nTask 3: https://example.com/task3',
                        border: OutlineInputBorder(),
                        labelText: 'Paste tasks here',
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
                        label: Text(_isLoading ? 'Adding...' : 'Make Tasks'),
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
            // Link addition section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Add Links to Existing Tasks:',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Paste text with task names and URLs to add links to existing tasks:',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _linkInputController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText:
                            'Task Name: https://example.com/link1\nAnother Task: https://example.com/link2',
                        border: OutlineInputBorder(),
                        labelText: 'Paste links here',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ||
                                _linkInputController.text.trim().isEmpty
                            ? null
                            : _processLinks,
                        icon: _isLoading
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.link),
                        label: Text(_isLoading ? 'Adding...' : 'Add Link(s)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.secondary,
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
            const Text(
              'Adding Tasks:\n'
              '• Enter one task per line\n'
              '• Use "Task: Notes" format to add notes\n'
              '• Include URLs to automatically create links\n'
              '• Tasks will be added to the beginning of your list\n'
              '• For single tasks, use "Add Task Manually" on the previous screen\n\n'
              'Adding Links:\n'
              '• Use "Task Name: URL" format to add links to existing tasks\n'
              '• Links will be matched by task headline (case-insensitive)\n'
              '• Duplicate links will be ignored\n'
              '• Only tasks in this category will be updated',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
