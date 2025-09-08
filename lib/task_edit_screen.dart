import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:flutter/services.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/link_edit_screen.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/add_tasks_screen.dart';
import 'package:meaning_to/shop_endeavors_screen.dart';
import 'package:meaning_to/utils/app_buttons.dart';
import 'package:meaning_to/justwatch_import_screen.dart';

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
  bool _isShared = false;

  // Local copy of the task for editing
  Task? _localTask;

  @override
  void initState() {
    super.initState();

    // Get the current task state from cache if available, otherwise use the passed task
    if (widget.task != null) {
      final cacheManager = CacheManager();
      final currentTasks = cacheManager.currentTasks;

      if (currentTasks != null) {
        // Try to find the task in the cache
        final cachedTask = currentTasks.firstWhere(
          (task) => task.id == widget.task!.id,
          orElse: () => widget.task!,
        );

        // Use the cached task if found, otherwise use the passed task
        _localTask = cachedTask;
      } else {
        // No cache available, use the passed task
        _localTask = widget.task!;
      }
    }

    _headlineController =
        TextEditingController(text: _localTask?.headline ?? '');
    _notesController = TextEditingController(text: _localTask?.notes ?? '');
    _links =
        _localTask?.links != null ? List<String>.from(_localTask!.links!) : [];

    // For existing tasks, use their current shared state
    // For new tasks, use the category's tasksArePrivate setting
    if (_localTask != null) {
      _isShared = _localTask!.shared;
    } else {
      // New task: use category's tasksArePrivate setting
      // If tasksArePrivate is true, tasks start private (shared = false)
      // If tasksArePrivate is false, tasks start shared (shared = true)
      _isShared = !widget.category.tasksArePrivate;
    }

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
      shared: _isShared,
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

    // Get existing tasks for the current category (excluding the current task being edited)
    final response = await supabase
        .from('Tasks')
        .select()
        .eq('category_id', widget.category.id)
        .eq('owner_id', userId)
        .order('created_at', ascending: false);

    final existingTasks = (response as List)
        .map((json) => Task.fromJson(json as Map<String, dynamic>))
        .where((task) =>
            _localTask == null ||
            task.id != _localTask!.id) // Exclude current task if editing
        .toList();
    print(
        'TaskEditScreen: Existing tasks count: ${existingTasks.length} (excluding current task)');

    // First, check for tasks with the same headline
    Task? existingTask;
    for (final task in existingTasks) {
      if (task.headline.toLowerCase().trim() ==
          (newTaskData['headline'] as String).toLowerCase().trim()) {
        existingTask = task;
        print(
            'TaskEditScreen: Found existing task with matching headline: "${task.headline}" (ID: ${task.id})');
        break;
      }
    }

    // If no headline match found, check for tasks with the same link
    if (existingTask == null &&
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
            if (existingTask != null) break;
          }
          if (existingTask != null) break;
        } else {
          print('TaskEditScreen:     Task has no links');
        }
      }
    }

    if (existingTask != null) {
      print(
          'TaskEditScreen: Found existing task: "${existingTask.headline}" (ID: ${existingTask.id})');
      // Found a duplicate - merge information and update
      print('TaskEditScreen: Found duplicate task: "${existingTask.headline}"');
      print(
          'TaskEditScreen: === DUPLICATE DETECTION END - DUPLICATE FOUND ===');
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

        // Create the updated task object
        final updatedTask = Task(
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

        // Update the cache to reflect the changes
        final cacheManager = CacheManager();
        await cacheManager.updateTask(updatedTask);
        print('TaskEditScreen:   -> Updated cache with moved task');

        return updatedTask;
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

  /// Process headline text to extract links and set appropriate headline
  Future<Map<String, dynamic>> _processHeadlineText(String headlineText) async {
    print('TaskEditScreen: Processing headline text: "$headlineText"');

    if (headlineText.trim().isEmpty) {
      return {
        'headline': '',
        'notes': null,
        'links': <String>[],
      };
    }

    // Check if text contains a URL
    final urlMatch = RegExp(r'https?://[^\s:]+').firstMatch(headlineText);
    if (urlMatch != null) {
      final extractedURL = urlMatch.group(0)!;
      print('TaskEditScreen: Found URL in headline: $extractedURL');

      // Remove trailing colon if present
      String cleanURL = extractedURL;
      if (cleanURL.endsWith(':')) {
        cleanURL = cleanURL.substring(0, cleanURL.length - 1);
      }

      // Extract text before and after the URL
      final urlStart = urlMatch.start;
      final urlEnd = urlMatch.end;
      final beforeURL = headlineText.substring(0, urlStart);
      final afterURL = headlineText.substring(urlEnd);

      // Combine text before and after URL, removing any trailing colons
      String cleanHeadline = (beforeURL + afterURL).trim();
      if (cleanHeadline.endsWith(':')) {
        cleanHeadline =
            cleanHeadline.substring(0, cleanHeadline.length - 1).trim();
      }

      // Remove @ prefix if it's the only text before the URL
      if (cleanHeadline == '@') {
        cleanHeadline = '';
      }

      // If no headline text remains, fetch the webpage title
      if (cleanHeadline.isEmpty) {
        try {
          print('TaskEditScreen: No headline text, fetching webpage title...');
          final processedLink =
              await LinkProcessor.validateAndProcessLink(cleanURL);
          cleanHeadline = processedLink.title ?? 'Link';
          print('TaskEditScreen: Fetched webpage title: "$cleanHeadline"');
        } catch (e) {
          print('TaskEditScreen: Failed to fetch webpage title: $e');
          cleanHeadline = 'Link';
        }
      }

      print('TaskEditScreen: Processed headline: "$cleanHeadline"');
      print('TaskEditScreen: Extracted link: "$cleanURL"');

      return {
        'headline': cleanHeadline,
        'notes': null,
        'links': [cleanURL],
      };
    }

    // Check if text contains a colon separator (title: description)
    final colonIndex = headlineText.indexOf(':');
    if (colonIndex > 0) {
      final title = headlineText.substring(0, colonIndex).trim();
      final description = headlineText.substring(colonIndex + 1).trim();

      if (title.isNotEmpty) {
        print(
            'TaskEditScreen: Found colon separator - title: "$title", description: "$description"');
        return {
          'headline': title,
          'notes': description.isNotEmpty ? description : null,
          'links': <String>[],
        };
      }
    }

    // Check if text is a markdown link [title](url)
    final markdownMatch =
        RegExp(r'\[([^\]]+)\]\(([^)]+)\)').firstMatch(headlineText);
    if (markdownMatch != null) {
      final title = markdownMatch.group(1) ?? 'Link';
      final url = markdownMatch.group(2) ?? '';

      if (url.isNotEmpty) {
        print(
            'TaskEditScreen: Found markdown link - title: "$title", url: "$url"');
        return {
          'headline': title,
          'notes': null,
          'links': [url],
        };
      }
    }

    // Check if text is an HTML link
    if (headlineText.trim().startsWith('<a') &&
        headlineText.trim().endsWith('</a>')) {
      print('TaskEditScreen: Attempting HTML link parsing');
      final (url, title) = LinkProcessor.parseHtmlLink(headlineText);
      if (url != headlineText) {
        print(
            'TaskEditScreen: Parsed HTML link - title: "$title", url: "$url"');
        return {
          'headline': title ?? 'Link',
          'notes': null,
          'links': [url],
        };
      }
    }

    // Treat as plain text
    print('TaskEditScreen: Treating as plain text: "$headlineText"');
    return {
      'headline': headlineText.trim(),
      'notes': null,
      'links': <String>[],
    };
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = AuthUtils.getCurrentUserId();

      // Process the headline text to extract links and set appropriate headline
      final processedData =
          await _processHeadlineText(_headlineController.text);
      final processedHeadline = processedData['headline'] as String;
      final processedNotes = processedData['notes'] as String?;
      final newLinks = processedData['links'] as List<String>;

      // Combine existing links with newly processed links
      final allLinks = [..._links, ...newLinks];

      // Use processed notes if available, otherwise fall back to notes controller
      final finalNotes = processedNotes ??
          (_notesController.text.isEmpty ? null : _notesController.text);

      final data = {
        'headline': processedHeadline,
        'notes': finalNotes,
        'category_id': widget.category.id,
        'owner_id': userId,
        'finished': _localTask?.finished ?? false,
        'shared': _isShared,
        'links':
            allLinks, // PostgreSQL array - always store as array, even if empty
      };

      // For new tasks, explicitly exclude suggestible_at to ensure it remains null
      if (_localTask == null) {
        // Don't include suggestible_at in the data to let database use its default (null)
        print(
            'TaskEditScreen: Excluding suggestible_at from new task data to ensure null value');
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

      // Wait longer for database transaction to commit
      await Future.delayed(const Duration(milliseconds: 500));

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
        title: Text('Delete ${NamingUtils.tasksName(plural: false)}?'),
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

      // Update the task cache using CacheManager
      print('TaskEditScreen: Updating task cache after deletion...');
      final cacheManager = CacheManager();
      if (cacheManager.currentCategory?.id == widget.category.id) {
        print('TaskEditScreen: Removing task from cache...');
        await cacheManager.removeTask(_localTask!.id);
        print('TaskEditScreen: Task removed from cache successfully');
      }

      // Call the edit complete callback to notify the parent screen
      if (TaskEditScreen.onEditComplete != null) {
        print(
            'TaskEditScreen: Calling edit complete callback after deletion...');
        try {
          TaskEditScreen.onEditComplete!();
          print('TaskEditScreen: Edit complete callback executed successfully');
        } catch (e) {
          print('TaskEditScreen: Error executing edit complete callback: $e');
        }
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
              style: AppButtons.iconGoForth(),
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
          title: Text(
            _localTask == null
                ? 'New ${NamingUtils.tasksName(capitalize: true, plural: false)} to ${widget.category.headline}'
                : 'Edit ${NamingUtils.tasksName(capitalize: true, plural: false)} to ${widget.category.headline}',
          ),
          actions: [
            // Only show delete button for authenticated users
            if (_localTask != null && !AuthUtils.isGuestUser())
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: _isLoading ? null : _deleteTask,
                tooltip:
                    'Delete ${NamingUtils.tasksName(capitalize: false, plural: false)}',
              ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _headlineController,
                        decoration: InputDecoration(
                          labelText:
                              '${NamingUtils.tasksName(plural: false)} (required)',
                          hintText:
                              'What have you been meaning to do?\n\nYou can use Enter to add line breaks for multi-line headlines.\n\nTip: Paste a link to automatically extract it and set the link title as the headline.',
                          border: const OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 3,
                        minLines: 1,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a ${NamingUtils.tasksName(capitalize: false, plural: false)}';
                          }
                          return null;
                        },
                        enabled: !_isLoading,
                      ),
                      // Show preview of links that will be extracted from headline
                      if (_headlineController.text.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        FutureBuilder<Map<String, dynamic>>(
                          future:
                              _processHeadlineText(_headlineController.text),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              final processedData = snapshot.data!;
                              final newLinks =
                                  processedData['links'] as List<String>;

                              if (newLinks.isNotEmpty) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Links that will be extracted from headline:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    ...newLinks
                                        .map((link) => Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              margin: const EdgeInsets.only(
                                                  bottom: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                    color:
                                                        Colors.blue.shade200),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(Icons.link,
                                                      size: 16,
                                                      color:
                                                          Colors.blue.shade600),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      link,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors
                                                            .blue.shade700,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ))
                                        .toList(),
                                  ],
                                );
                              }
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          hintText: 'Add any additional details...',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                        enabled: !_isLoading,
                      ),
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        title: const Text(
                            'Share this ${NamingUtils.tasksNameSingular}'),
                        subtitle: const Text('Make it available to others'),
                        value: _isShared,
                        onChanged: _isLoading
                            ? null
                            : (value) {
                                setState(() {
                                  _isShared = value ?? false;
                                });
                              },
                        controlAffinity: ListTileControlAffinity.leading,
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
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton(
                          onPressed: (_isLoading ||
                                  _headlineController.text.trim().isEmpty)
                              ? null
                              : _saveTask,
                          style: AppButtons.finalize(),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(
                                  _localTask == null
                                      ? 'Register ${NamingUtils.tasksName(plural: false)}'
                                      : 'Save Changes',
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_localTask == null) ...[
                const SizedBox(height: 16),
                Center(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Labeled divider to set off alternatives (now inside container)
                      const Row(
                        children: [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 2.0),
                            child: Text(
                              'Alternative options',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Add a List of Tasks button
                      FractionallySizedBox(
                        widthFactor: 0.7,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading
                              ? null
                              : () async {
                                  final result =
                                      await Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => AddTasksScreen(
                                        category: widget.category,
                                        currentTask: _currentTaskState,
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.add_task),
                          label: Text(
                              'Add a List of ${NamingUtils.tasksName(plural: true)}'),
                          style: AppButtons.goForth(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Separator with helpful text for shop suggestions
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Text(
                              '** You can also get ${NamingUtils.tasksNamePlural} from other people! **',
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
                      // Shop for Suggestions button with pre-check
                      FutureBuilder<bool>(
                        future: ShopEndeavorsScreen
                            .hasAnyPublicSuggestionsForCategory(
                                widget.category),
                        builder: (context, snapshot) {
                          final hasSuggestions = snapshot.data == true;
                          return FractionallySizedBox(
                            widthFactor: 0.7,
                            child: ElevatedButton.icon(
                              onPressed: (_isLoading || !hasSuggestions)
                                  ? null
                                  : () async {
                                      final result =
                                          await Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              ShopEndeavorsScreen(
                                            existingCategory: widget.category,
                                          ),
                                        ),
                                      );
                                      print(
                                          'TaskEditScreen: ShopEndeavorsScreen returned: $result');
                                    },
                              icon: const Icon(Icons.shopping_cart),
                              label: Text(hasSuggestions
                                  ? 'Shop for Suggestions'
                                  : 'No Suggestions Out There'),
                              style: hasSuggestions
                                  ? AppButtons.goForth()
                                  : ElevatedButton.styleFrom(
                                      backgroundColor: Colors.grey[300],
                                      foregroundColor: Colors.grey[600],
                                    ),
                            ),
                          );
                        },
                      ),
                      if (widget.category.originalId != null &&
                          (widget.category.originalId == 1 ||
                              widget.category.originalId == 2)) ...[
                        const SizedBox(height: 24),
                        // Separator with helpful text for JustWatch import
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16.0),
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
                        // Single JustWatch Import button
                        FractionallySizedBox(
                          widthFactor: 0.7,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    print(
                                        'Import from JustWatch button pressed');
                                    print(
                                        'Category: ${widget.category.headline}');

                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            JustWatchImportScreen(
                                          category: widget.category,
                                        ),
                                      ),
                                    ).then((result) {
                                      if (result is Category && mounted) {
                                        print('JustWatch import completed');
                                        Navigator.pop(context, result);
                                      }
                                    });
                                  },
                            icon: const Icon(Icons.movie),
                            label: const Text('Import from JustWatch'),
                            style: AppButtons.goForth(),
                          ),
                        ),
                      ],
                    ],
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
