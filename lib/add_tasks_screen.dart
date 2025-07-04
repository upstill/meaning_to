import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/text_importer.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/widgets/add_task_manually_button.dart';

class AddTasksScreen extends StatefulWidget {
  final Category category;

  const AddTasksScreen({super.key, required this.category});

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

      // Check if the input is a single URL
      final trimmedText = _textInputController.text.trim();
      if (LinkProcessor.isValidUrl(trimmedText)) {
        // Single URL detected - process it through LinkProcessor
        print('Single URL detected: $trimmedText');

        try {
          final processedLink = await LinkProcessor.validateAndProcessLink(
            trimmedText,
            linkText: '', // Let LinkProcessor fetch the title
          );

          // Create a task with the link's title and the URL
          final taskData = {
            'headline': processedLink.title ?? 'Link Task',
            'notes': null,
            'category_id': widget.category.id,
            'owner_id': userId,
            'links': [trimmedText], // Store the original URL
            'suggestible_at': null, // Set to null to appear at the beginning
          };

          await supabase.from('Tasks').insert(taskData);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Created task: "${processedLink.title ?? 'Link Task'}"'),
              backgroundColor: Colors.green,
            ),
          );

          // Clear the text input
          _textInputController.clear();

          // Return success to trigger refresh
          if (mounted) {
            Navigator.pop(context, true);
          }
          return;
        } catch (e) {
          print('Error processing single URL: $e');

          // If URL processing fails, create a task with the URL as the title
          // This is better than falling back to text processing which can create malformed tasks
          final taskData = {
            'headline': trimmedText, // Use the URL as the title
            'notes': 'Failed to fetch webpage title',
            'category_id': widget.category.id,
            'owner_id': userId,
            'links': [trimmedText], // Store the original URL
            'suggestible_at': null, // Set to null to appear at the beginning
          };

          await supabase.from('Tasks').insert(taskData);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Created task with URL: "$trimmedText"'),
              backgroundColor: Colors.orange,
            ),
          );

          // Clear the text input
          _textInputController.clear();

          // Return success to trigger refresh
          if (mounted) {
            Navigator.pop(context, true);
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
                      'List one or more tasks, one per line:',
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
            const Text(
              'Tips:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '• Enter one task per line\n'
              '• Use "Task: Note" format to include a note\n'
              '• Pasting a Share from elsewhere will do the right thing\n'
              '• Ditto a URL (address-bar gobbledygook from a web page)\n'
              '• New Tasks will appear at the beginning of your list',
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
                    const Text(
                      'For adding a single task:',
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
