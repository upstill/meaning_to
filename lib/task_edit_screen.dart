import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:flutter/services.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/link_edit_screen.dart';
import 'dart:convert';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/link_extractor.dart';
import 'package:meaning_to/widgets/link_display.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/add_tasks_screen.dart';
import 'package:meaning_to/shop_endeavors_screen.dart';
import 'package:meaning_to/import_justwatch_screen.dart';

class TaskEditScreen extends StatefulWidget {
  static VoidCallback? onEditComplete; // Static callback for edit completion

  final Category category;
  final Task? task; // null for new task, existing task for edit

  const TaskEditScreen({super.key, required this.category, this.task});

  @override
  State<TaskEditScreen> createState() => _TaskEditScreenState();
}

class _TaskEditScreenState extends State<TaskEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _headlineController;
  late TextEditingController _notesController;
  bool _isLoading = false;
  String? _error;
  List<String> _links = [];

  // Local copy of the task for editing
  Task? _localTask;

  @override
  void initState() {
    super.initState();

    // Create a local copy of the task for editing
    if (widget.task != null) {
      _localTask = Task(
        id: widget.task!.id,
        categoryId: widget.task!.categoryId,
        ownerId: widget.task!.ownerId,
        headline: widget.task!.headline,
        notes: widget.task!.notes,
        links: widget.task!.links != null
            ? List<String>.from(widget.task!.links!)
            : null,
        processedLinks: widget.task!.processedLinks,
        createdAt: widget.task!.createdAt,
        suggestibleAt: widget.task!.suggestibleAt,
        finished: widget.task!.finished,
      );
    }

    _headlineController =
        TextEditingController(text: _localTask?.headline ?? '');
    _notesController = TextEditingController(text: _localTask?.notes ?? '');
    _links =
        _localTask?.links != null ? List<String>.from(_localTask!.links!) : [];

    // Add listener to track headline changes for button state
    _headlineController.addListener(() {
      setState(() {
        // Trigger rebuild when headline changes to update button state
      });
    });
  }

  @override
  void dispose() {
    _headlineController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _addLink() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => LinkEditScreen(
          currentTask: _currentTaskState,
          currentCategory: widget.category,
        ),
      ),
    );

    if (result != null) {
      final errorMessage = await _addLinkToTask(result);
      if (errorMessage != null) {
        setState(() {
          _error = errorMessage;
        });
      }
    }
  }

  Future<void> _editLink(int index) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => LinkEditScreen(
          initialLink: _links[index],
          currentTask: _currentTaskState,
          currentCategory: widget.category,
        ),
      ),
    );

    if (result != null) {
      final errorMessage = await _updateLinkInTask(result, index);
      if (errorMessage != null) {
        setState(() {
          _error = errorMessage;
        });
      }
    }
  }

  void _removeLink(int index) {
    setState(() {
      _links.removeAt(index);
    });
  }

  /// Get the current task state with all unsaved changes
  Task? get _currentTaskState {
    if (_localTask == null) return null;

    return Task(
      id: _localTask!.id,
      categoryId: _localTask!.categoryId,
      ownerId: _localTask!.ownerId,
      headline: _headlineController.text,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
      links: _links, // Always store as array, even if empty
      processedLinks: _localTask!.processedLinks,
      createdAt: _localTask!.createdAt,
      suggestibleAt: _localTask!.suggestibleAt,
      finished: _localTask!.finished,
    );
  }

  /// Adds a link to the current task (duplicate checking handled by LinkEditScreen).
  /// Returns an error message if the link cannot be added, null if successful.
  Future<String?> _addLinkToTask(String htmlLink) async {
    print('TaskEditScreen: _addLinkToTask called with: $htmlLink');

    // Add the link to the current task's links list
    // Note: Duplicate checking is now handled by LinkEditScreen
    setState(() {
      _links.add(htmlLink);
      _error = null;
    });

    print('TaskEditScreen: Link added successfully: $htmlLink');
    return null; // No error
  }

  /// Helper method to extract URL from HTML link string
  String? _extractUrlFromHtmlLink(String htmlLink) {
    if (htmlLink.startsWith('<a href="') && htmlLink.contains('">')) {
      final startIndex = htmlLink.indexOf('href="') + 6;
      final endIndex = htmlLink.indexOf('">', startIndex);
      if (endIndex > startIndex) {
        return htmlLink.substring(startIndex, endIndex);
      }
    }
    // If it's not an HTML link, return as is (might be a plain URL)
    if (htmlLink.startsWith('http')) {
      return htmlLink;
    }
    return null;
  }

  /// Updates a link in the current task (duplicate checking handled by LinkEditScreen).
  /// Returns an error message if the link cannot be updated, null if successful.
  Future<String?> _updateLinkInTask(String htmlLink, int index) async {
    print(
        'TaskEditScreen: _updateLinkInTask called with: $htmlLink at index $index');

    // Update the link in the current task's links list
    // Note: Duplicate checking is now handled by LinkEditScreen
    setState(() {
      _links[index] = htmlLink;
      _error = null;
    });

    print('TaskEditScreen: Link updated successfully: $htmlLink');
    return null; // No error
  }

  Future<void> _pasteLinkFromClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData?.text == null) {
        setState(() {
          _error = 'No text found in clipboard';
        });
        return;
      }

      final text = clipboardData!.text!.trim();
      setState(() {
        _isLoading = true;
        _error = null;
      });

      try {
        // Parse the text as HTML link
        final (url, linkText) = LinkProcessor.parseHtmlLink(text);

        String htmlLink;
        // If it's not an HTML link, treat it as a plain URL
        if (url == text) {
          if (LinkProcessor.isValidUrl(text)) {
            // Validate the URL
            final processedLink = await LinkProcessor.validateAndProcessLink(
              text,
            );

            // Create an HTML link with the fetched title
            htmlLink = '<a href="$text">${processedLink.title ?? text}</a>';
          } else {
            // Open link edit screen with the text pre-filled
            final result = await Navigator.push<String>(
              context,
              MaterialPageRoute(
                builder: (context) => LinkEditScreen(
                  initialLink: text,
                  errorMessage:
                      'Clipboard text is not a valid URL or HTML link',
                  currentTask: _currentTaskState,
                  currentCategory: widget.category,
                ),
              ),
            );
            if (result != null) {
              htmlLink = result;
            } else {
              setState(() {
                _isLoading = false;
              });
              return;
            }
          }
        } else {
          // It was an HTML link, validate the extracted URL
          final processedLink = await LinkProcessor.validateAndProcessLink(
            url,
            linkText: linkText,
          );

          // Create a new HTML link with the validated data
          htmlLink =
              '<a href="$url">${linkText ?? processedLink.title ?? url}</a>';
        }

        // Add the link (duplicate checking handled by LinkEditScreen)
        await _addLinkToTask(htmlLink);
      } catch (e) {
        print('Error processing pasted link: $e');
        // Open link edit screen with error message
        final result = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (context) => LinkEditScreen(
              initialLink: text,
              errorMessage: e.toString(),
              currentTask: _currentTaskState,
              currentCategory: widget.category,
            ),
          ),
        );
        if (result != null) {
          // Add the link (duplicate checking handled by LinkEditScreen)
          await _addLinkToTask(result);
        }
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error pasting link: $e');
      setState(() {
        _error = 'Failed to paste link: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  /// Check if a task with the same headline or same link already exists and merge information if needed
  Future<Task?> _checkForDuplicateAndMerge(
      Map<String, dynamic> newTaskData, String userId) async {
    print('TaskEditScreen: === DUPLICATE DETECTION START ===');
    print(
        'TaskEditScreen: Checking for duplicates of: "${newTaskData['headline']}"');
    print('TaskEditScreen: New task links: ${newTaskData['links']}');

    // First, check if the current task (if editing) already has the same link
    if (_localTask != null &&
        newTaskData['links'] != null &&
        (newTaskData['links'] as List).isNotEmpty) {
      print('TaskEditScreen: Checking current task for duplicate links...');
      print('TaskEditScreen: Current task links: ${_localTask!.links}');

      if (_localTask!.links != null && _localTask!.links!.isNotEmpty) {
        for (final newLink in newTaskData['links'] as List) {
          print('TaskEditScreen: Checking new link: $newLink');
          for (final existingLink in _localTask!.links!) {
            print('TaskEditScreen: Against current task link: $existingLink');
            // Extract URLs from HTML links for comparison
            final newUrl = _extractUrlFromHtmlLink(newLink);
            final existingUrl = _extractUrlFromHtmlLink(existingLink);
            print('TaskEditScreen: Extracted new URL: $newUrl');
            print('TaskEditScreen: Extracted existing URL: $existingUrl');

            if (newUrl != null &&
                existingUrl != null &&
                newUrl == existingUrl) {
              print('TaskEditScreen: Found duplicate link in current task!');
              print('TaskEditScreen: New link: $newUrl');
              print('TaskEditScreen: Existing link: $existingUrl');
              print(
                  'TaskEditScreen: === DUPLICATE DETECTION END - DUPLICATE IN CURRENT TASK ===');
              return _localTask; // Return current task since it already has this link
            }
          }
        }
      }
      print('TaskEditScreen: No duplicate links found in current task');
    }

    // Get existing tasks for the current category
    final response = await supabase
        .from('Tasks')
        .select()
        .eq('category_id', widget.category.id)
        .eq('owner_id', userId)
        .order('created_at', ascending: false);

    final existingTasks = (response as List)
        .map((json) => Task.fromJson(json as Map<String, dynamic>))
        .toList();
    print('TaskEditScreen: Existing tasks count: ${existingTasks.length}');

    // First, check for tasks with the same headline
    Task existingTask = existingTasks.firstWhere(
      (task) =>
          task.headline.toLowerCase().trim() ==
          (newTaskData['headline'] as String).toLowerCase().trim(),
      orElse: () => Task(
        id: -1,
        categoryId: widget.category.id,
        headline: newTaskData['headline'] as String,
        notes: newTaskData['notes'] as String?,
        ownerId: userId,
        createdAt: DateTime.now(),
        suggestibleAt: null,
        links: newTaskData['links'] as List<String>?,
        processedLinks: null,
        finished: false,
      ), // Return a dummy task if no duplicate found
    );

    // If no headline match found, check for tasks with the same link
    if (existingTask.id == -1 &&
        newTaskData['links'] != null &&
        (newTaskData['links'] as List).isNotEmpty) {
      print(
          'TaskEditScreen: No headline match found, checking for link matches...');

      for (final task in existingTasks) {
        print(
            'TaskEditScreen:   Checking task: "${task.headline}" (ID: ${task.id})');
        if (task.links != null && task.links!.isNotEmpty) {
          print(
              'TaskEditScreen:     Task has ${task.links!.length} links: ${task.links}');
          // Check if any of the new task's links match any of the existing task's links
          for (final newLink in newTaskData['links'] as List) {
            print('TaskEditScreen:     Checking new link: $newLink');
            for (final existingLink in task.links!) {
              print('TaskEditScreen:     Against existing link: $existingLink');
              // Extract URLs from HTML links for comparison
              final newUrl = _extractUrlFromHtmlLink(newLink);
              final existingUrl = _extractUrlFromHtmlLink(existingLink);
              print('TaskEditScreen:     Extracted new URL: $newUrl');
              print('TaskEditScreen:     Extracted existing URL: $existingUrl');

              if (newUrl != null &&
                  existingUrl != null &&
                  newUrl == existingUrl) {
                print(
                    'TaskEditScreen: Found existing task with matching link: "${task.headline}" (ID: ${task.id})');
                print('TaskEditScreen:   New link: $newUrl');
                print('TaskEditScreen:   Existing link: $existingUrl');
                existingTask = task;
                break;
              }
            }
            if (existingTask.id != -1) break;
          }
          if (existingTask.id != -1) break;
        } else {
          print('TaskEditScreen:     Task has no links');
        }
      }
    }

    print(
        'TaskEditScreen: Found existing task: "${existingTask.headline}" (ID: ${existingTask.id})');

    if (existingTask.id != -1) {
      // Found a duplicate - merge information and update
      print('TaskEditScreen: Found duplicate task: "${existingTask.headline}"');
      print(
          'TaskEditScreen: === DUPLICATE DETECTION END - DUPLICATE FOUND ===');

      // Check if we need to update the existing task with new information
      bool needsUpdate = false;
      Map<String, dynamic> updateData = {};

      // Add links if the new task has them and the existing task doesn't
      if (newTaskData['links'] != null &&
          (newTaskData['links'] as List).isNotEmpty &&
          (existingTask.links == null || existingTask.links!.isEmpty)) {
        updateData['links'] = newTaskData['links'];
        needsUpdate = true;
        print('TaskEditScreen:   -> Adding links to existing task');
      }

      // Add notes if the new task has them and the existing task doesn't
      if (newTaskData['notes'] != null &&
          (newTaskData['notes'] as String).isNotEmpty &&
          (existingTask.notes == null || existingTask.notes!.isEmpty)) {
        updateData['notes'] = newTaskData['notes'];
        needsUpdate = true;
        print('TaskEditScreen:   -> Adding notes to existing task');
      }

      // Always update the existing task to move it to the top of the list
      // Set suggestibleAt to null to make it appear first
      try {
        // Add suggestibleAt: null to the update data to move task to top
        updateData['suggestible_at'] = null;

        await supabase
            .from('Tasks')
            .update(updateData)
            .eq('id', existingTask.id)
            .eq('owner_id', userId);

        print(
            'TaskEditScreen:   -> Updated existing task and moved to top of list');

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
        print('TaskEditScreen: Error updating existing task: $e');
        return existingTask; // Return existing task without changes on error
      }
    } else {
      print(
          'TaskEditScreen: === DUPLICATE DETECTION END - NO DUPLICATE FOUND ===');
    }

    return null; // No duplicate found
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = AuthUtils.getCurrentUserId();

      final data = {
        'headline': _headlineController.text,
        'notes': _notesController.text.isEmpty ? null : _notesController.text,
        'category_id': widget.category.id,
        'owner_id': userId,
        'finished': _localTask?.finished ?? false,
        'links':
            _links, // PostgreSQL array - always store as array, even if empty
      };

      // For new tasks, set suggestible_at to null to appear at the top
      if (_localTask == null) {
        data['suggestible_at'] = null;
        print('TaskEditScreen: Setting suggestible_at to null for new task');
      }

      Task? updatedTask;
      if (_localTask == null) {
        // Check for duplicates before creating new task
        print(
            'TaskEditScreen: Checking for duplicates before creating new task...');
        final existingTask = await _checkForDuplicateAndMerge(data, userId);

        if (existingTask != null) {
          // Found a duplicate - use the existing task
          print(
              'TaskEditScreen: Found duplicate task, using existing: ${existingTask.headline}');
          updatedTask = existingTask;
        } else {
          // No duplicate found - create new task
          print('TaskEditScreen: No duplicate found, creating new task...');
          final response =
              await supabase.from('Tasks').insert(data).select().single();

          updatedTask = Task.fromJson(response);
          print('TaskEditScreen: Created new task: ${updatedTask.headline}');
        }
      } else {
        // Update existing task
        print('TaskEditScreen: Updating existing task...');
        final response = await supabase
            .from('Tasks')
            .update(data)
            .eq('id', _localTask!.id)
            .eq('owner_id', userId)
            .select()
            .single();

        updatedTask = Task.fromJson(response);
        print('TaskEditScreen: Updated task: ${updatedTask.headline}');
      }

      // Update the task cache using CacheManager only when saving
      print('TaskEditScreen: Updating task cache...');
      final cacheManager = CacheManager();
      if (cacheManager.currentCategory?.id == widget.category.id) {
        print('TaskEditScreen: Updating task in cache...');
        await cacheManager.updateTask(updatedTask);
      }

      print(
        'TaskEditScreen: Task saved successfully, calling edit complete callback...',
      );
      // Call the edit complete callback before popping
      if (TaskEditScreen.onEditComplete != null) {
        print('TaskEditScreen: Static callback available, calling it...');
        try {
          TaskEditScreen.onEditComplete!();
          print('TaskEditScreen: Static callback executed successfully');
        } catch (e) {
          print('TaskEditScreen: Error executing static callback: $e');
        }
      } else {
        print('TaskEditScreen: No static callback available');
      }

      if (mounted) {
        print('TaskEditScreen: Popping screen with true result...');
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      print('TaskEditScreen: Error saving task: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteTask() async {
    if (_localTask == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = AuthUtils.getCurrentUserId();

      await supabase
          .from('Tasks')
          .delete()
          .eq('id', _localTask!.id)
          .eq('owner_id', userId);

      print('Deleted task: ${_localTask!.headline}');

      // Update the task cache
      if (Task.currentCategory?.id == widget.category.id) {
        await Task.loadTaskSet(widget.category, userId);
      }

      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      print('Error deleting task: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _handleBack() {
    print('TaskEditScreen: Back button pressed');
    print('TaskEditScreen: Current task: ${_localTask?.headline}');
    print(
      'TaskEditScreen: Static callback available: ${TaskEditScreen.onEditComplete != null}',
    );

    // Don't call the callback when going back without saving
    print('TaskEditScreen: Going back without saving, not calling callback');

    // Pop without calling the callback since changes weren't saved
    if (mounted) {
      Navigator.of(
        context,
      ).pop(false); // Return false to indicate no changes were saved
      print('TaskEditScreen: Popped screen with false result');
    } else {
      print('TaskEditScreen: Widget not mounted, cannot pop');
    }
  }

  Widget _buildLinksList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Links:', style: TextStyle(fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add link',
              onPressed: _isLoading ? null : _addLink,
            ),
          ],
        ),
        if (_links.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...List.generate(_links.length, (index) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: LinkDisplayWidget(
                        linkText: _links[index],
                        showIcon: true,
                        showTitle: true,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit link',
                      onPressed: _isLoading ? null : () => _editLink(index),
                    ),
                    // Only show delete button for authenticated users
                    if (!AuthUtils.isGuestUser())
                      IconButton(
                        icon: const Icon(Icons.delete),
                        tooltip: 'Delete link',
                        onPressed: _isLoading ? null : () => _removeLink(index),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        print('TaskEditScreen: WillPopScope triggered');
        _handleBack();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              print('TaskEditScreen: Back button pressed in app bar');
              _handleBack();
            },
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.category.headline,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_localTask != null)
                Text(
                  'Edit Task for ${widget.category.headline}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                  ),
                ),
            ],
          ),
          actions: [
            // Only show delete button for authenticated users
            if (_localTask != null && !AuthUtils.isGuestUser())
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: _isLoading ? null : _deleteTask,
                tooltip: 'Delete task',
              ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              TextFormField(
                controller: _headlineController,
                decoration: const InputDecoration(
                  labelText: 'Task (required)',
                  hintText: 'What have you been meaning to do?',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a task';
                  }
                  return null;
                },
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'Add any additional details...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                enabled: !_isLoading,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Error: $_error',
                  style: const TextStyle(color: Colors.red),
                ),
              ],
              _buildLinksList(),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed:
                    (_isLoading || _headlineController.text.trim().isEmpty)
                        ? null
                        : _saveTask,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _localTask == null ? 'Create Task' : 'Save Changes',
                      ),
              ),
              const SizedBox(height: 24),
              // Separator with helpful text
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      '** If you like, you can add a whole list of tasks at once **',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),
              // Add a List of Tasks button
              ElevatedButton.icon(
                onPressed: _isLoading
                    ? null
                    : () async {
                        // Use pushReplacement so that when AddTasksScreen completes,
                        // it navigates directly to EditCategoryScreen without TaskEditScreen in the stack
                        final result = await Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AddTasksScreen(
                              category: widget.category,
                              currentTask: _currentTaskState,
                            ),
                          ),
                        );
                        // Note: We don't need to handle the result here because AddTasksScreen
                        // will navigate to EditCategoryScreen on completion
                      },
                icon: const Icon(Icons.add_task),
                label: const Text('Add a List of Tasks'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Colors.white,
                ),
              ),

              const SizedBox(height: 24),
              // Separator with helpful text for shop suggestions
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      '** You can also get ideas from other people! **',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),
              // Shop for Suggestions button
              ElevatedButton.icon(
                onPressed: _isLoading
                    ? null
                    : () async {
                        // Use pushReplacement so that when ShopEndeavorsScreen completes,
                        // it navigates directly to EditCategoryScreen without TaskEditScreen in the stack
                        final result = await Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ShopEndeavorsScreen(
                              existingCategory: widget.category,
                            ),
                          ),
                        );

                        // If tasks were added, the result will be true
                        // Edit Category Screen will refresh via lifecycle callback
                        // No need to pop since pushReplacement already handles navigation
                        print(
                            'TaskEditScreen: ShopEndeavorsScreen returned: $result');
                      },
                icon: const Icon(Icons.shopping_cart),
                label: const Text('Shop for Suggestions'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
              // JustWatch import section (only for specific categories)
              if (widget.category.originalId != null &&
                  (widget.category.originalId == 1 ||
                      widget.category.originalId == 2)) ...[
                const SizedBox(height: 24),
                // Separator with helpful text for JustWatch import
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        '** OR...You can import your list from JustWatch. **',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _isLoading
                      ? null
                      : () {
                          print('Import JustWatch button pressed');
                          print('Category: ${widget.category.headline}');

                          // Navigate to Import JustWatch screen, replacing the current screen
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ImportJustWatchScreen(
                                category: widget.category,
                              ),
                            ),
                          ).then((result) {
                            if (result is Category) {
                              // Handle any updates if needed
                              print('JustWatch import completed');
                            }
                          });
                        },
                  icon: const Icon(Icons.movie),
                  label: const Text('Import JustWatch list'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
