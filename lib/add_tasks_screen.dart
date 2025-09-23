import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/utils/text_importer.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/utils/app_buttons.dart';
import 'package:meaning_to/widgets/add_task_manually_button.dart';
import 'package:meaning_to/edit_category_screen.dart';
import 'package:file_selector/file_selector.dart';

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

  /// Select and load a file into the text input
  Future<void> _selectAndLoadFile() async {
    try {
      const typeGroup = XTypeGroup(
        label: 'text files',
        extensions: ['txt', 'md', 'csv', 'rtf', 'pdf', 'doc', 'docx', 'odt'],
      );

      final XFile? file = await openFile(
        acceptedTypeGroups: [typeGroup],
      );

      if (file != null) {
        final String contents = await file.readAsString();
        String processedContents = contents;

        // Handle different file types
        final fileName = file.name.toLowerCase();
        if (fileName.endsWith('.rtf')) {
          processedContents = _rtfToText(contents);
        } else if (fileName.endsWith('.pdf')) {
          // For PDF files, we'll need to extract text
          // This is a placeholder - you might want to add a PDF parser
          processedContents = 'PDF text extraction not yet implemented';
        } else if (fileName.endsWith('.doc') || fileName.endsWith('.docx')) {
          // For Word documents, we'll need to extract text
          // This is a placeholder - you might want to add a DOC parser
          processedContents =
              'Word document text extraction not yet implemented';
        }
        // For txt, md, csv, odt - use as is

        setState(() {
          _textInputController.text = processedContents;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File loaded: ${file.name}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Convert RTF content to plain text
  String _rtfToText(String rtfContent) {
    // More comprehensive RTF to text conversion
    String text = rtfContent;

    // Remove RTF header
    if (text.startsWith('{\\rtf')) {
      final headerEnd = text.indexOf('\\viewkind');
      if (headerEnd != -1) {
        text = text.substring(headerEnd);
      }
    }

    // Convert RTF line breaks to actual line breaks
    // RTF uses \par for paragraph breaks and \line for line breaks
    text = text.replaceAll(RegExp(r'\\par\s*'), '\n');
    text = text.replaceAll(RegExp(r'\\line\s*'), '\n');

    // Remove RTF control words more comprehensively
    // This catches control words with optional parameters
    text = text.replaceAll(RegExp(r'\\[a-zA-Z]+\d*'), '');
    text = text.replaceAll(RegExp(r'\\[a-zA-Z]+'), '');

    // Remove RTF groups but preserve line breaks
    text = text.replaceAll(RegExp(r'\{[^}]*\}'), '');
    text = text.replaceAll(RegExp(r'\}[^{]*\{'), ' ');
    text = text.replaceAll('{', '');
    text = text.replaceAll('}', '');

    // Remove any remaining RTF artifacts
    text = text.replaceAll(
        RegExp(r'\\[^\\\s]+'), ''); // Any remaining backslash commands
    text = text.replaceAll(RegExp(r'\\'), ''); // Any remaining backslashes

    // Clean up multiple line breaks and spaces
    text = text.replaceAll(RegExp(r'\n\s*\n'),
        '\n\n'); // Multiple line breaks to double line breaks
    text = text.replaceAll(
        RegExp(r'[ \t]+'), ' '); // Multiple spaces/tabs to single space
    text = text.replaceAll(
        RegExp(r'\n[ \t]+'), '\n'); // Remove leading spaces after line breaks
    text = text.replaceAll(
        RegExp(r'[ \t]+\n'), '\n'); // Remove trailing spaces before line breaks

    // Remove any lines that are just whitespace or RTF artifacts
    text =
        text.replaceAll(RegExp(r'^\s*[a-zA-Z]*\d*\s*$', multiLine: true), '');

    // Trim whitespace but preserve line breaks
    text = text.trim();

    return text;
  }

  /// Navigate to Edit Category screen for the cached category
  void _navigateToEditCategory() async {
    final cachedCategory = CacheManager().currentCategory;
    if (cachedCategory != null) {
      // Cache should already be fresh from the task creation process
      // No need to refresh again here to avoid race conditions
      print('AddTasksScreen: Navigating to Edit Category with cached category');

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

    // First, check for tasks with the same headline (case-insensitive, trimmed)
    Task? existingTask;
    for (final task in existingTasks) {
      if (task.headline.toLowerCase().trim() ==
          newTask.headline.toLowerCase().trim()) {
        existingTask = task;
        print(
            'Found existing task with matching headline: "${task.headline}" (ID: ${task.id})');
        break;
      }
    }

    // If no headline match found, check for tasks with the same link
    if (existingTask == null &&
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
            if (existingTask != null) break;
          }
          if (existingTask != null) break;
        } else {
          print('    Task has no links');
        }
      }
    }

    if (existingTask != null) {
      print(
          'Found existing task: "${existingTask.headline}" (ID: ${existingTask.id})');
      print('New task: "${newTask.headline}" (ID: ${newTask.id})');
      print('Are they the same? ${existingTask.id == newTask.id}');

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
        print('  -> Updated cache with moved task');

        return updatedTask;
      } catch (e) {
        print('Error updating existing task: $e');
        return existingTask; // Return existing task without changes on error
      }
    } else {
      print('=== DUPLICATE DETECTION END - NO DUPLICATE FOUND ===');
    }

    return null; // No duplicate found
  }

  /// Fetch description from JustWatch URL
  Future<String?> _fetchJustWatchDescription(String url) async {
    try {
      late http.Response response;

      if (kIsWeb) {
        // Use allorigins.win proxy for web to bypass CORS
        final proxyUrl = 'https://api.allorigins.win/raw?url=${Uri.encodeComponent(url)}';
        print('AddTasksScreen JustWatch: Using proxy for web: $proxyUrl');
        response = await http.get(Uri.parse(proxyUrl));

        // Check if proxy returned wrong content (JustWatch bot detection)
        if (response.statusCode == 200 && response.body.length < 5000) {
          print('AddTasksScreen JustWatch: Proxy returned suspicious response, checking content...');
          if (response.body.contains('<title>Meaning To</title>') || response.body.contains('Meaning To')) {
            print('AddTasksScreen JustWatch: JustWatch blocked proxy request, descriptions not available on web');
            return null;
          }
        }
      } else {
        // Direct fetch for mobile
        response = await http.get(
          Uri.parse(url),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        );
      }

      if (response.statusCode != 200) {
        return null;
      }

      final document = html_parser.parse(response.body);

      // Extract title using CSS selector h1.title-detail-hero__details__title
      String? title;
      final titleElement = document.querySelector('h1.title-detail-hero__details__title');
      if (titleElement != null) {
        title = titleElement.text.trim();
        if (title.isNotEmpty) {
          print('AddTasksScreen JustWatch: Found title via CSS selector: $title');
        }
      }

      // PRIORITY 1: Try CSS selector for synopsis div > p tag (preferred method)
      final synopsisDiv = document.querySelector('div#synopsis');
      if (synopsisDiv != null) {
        print('AddTasksScreen JustWatch: Found synopsis div, innerHTML: ${synopsisDiv.innerHtml}');
        final synopsisParagraph = synopsisDiv.querySelector('p');
        if (synopsisParagraph != null) {
          final synopsisText = synopsisParagraph.text.trim();
          print('AddTasksScreen JustWatch: Raw synopsis text from CSS selector: "$synopsisText"');
          if (synopsisText.isNotEmpty) {
            print('AddTasksScreen JustWatch: Found synopsis via CSS selector: ${synopsisText.substring(0, synopsisText.length > 50 ? 50 : synopsisText.length)}...');
            // Return just the synopsis - title is already used as task headline
            return synopsisText;
          }
        } else {
          print('AddTasksScreen JustWatch: No <p> tag found within synopsis div');
        }
      } else {
        print('AddTasksScreen JustWatch: No div#synopsis found');
      }

      // PRIORITY 2: Try meta description (fallback)
      String? description = document
          .querySelector('meta[name="description"]')
          ?.attributes['content']
          ?.trim();

      if (description != null && description.isNotEmpty) {
        print('AddTasksScreen JustWatch: Found description via meta description tag');
        // Return just the description - title is already used as task headline
        return description;
      }

      // PRIORITY 3: Try og:description (fallback)
      description = document
          .querySelector('meta[property="og:description"]')
          ?.attributes['content']
          ?.trim();

      if (description != null && description.isNotEmpty) {
        print('AddTasksScreen JustWatch: Found description via og:description tag');
        // Return just the description - title is already used as task headline
        return description;
      }

      // If we only have title, don't return it since it's already the task headline
      if (title != null && title.isNotEmpty) {
        print('AddTasksScreen JustWatch: Found only title, but not returning since it\'s already the task headline');
        return null;
      }

      print('AddTasksScreen JustWatch: No title or description found for URL: $url');
      return null;
    } catch (e) {
      print('AddTasksScreen JustWatch: Error fetching description: $e');
      return null;
    }
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

      // Get existing tasks for duplicate checking - check database directly to avoid race conditions
      print('AddTasksScreen: About to check database for existing tasks...');
      print(
          'AddTasksScreen: Category: ${widget.category.headline} (ID: ${widget.category.id})');
      print('AddTasksScreen: User ID: $userId');

      // Query database directly for existing tasks to avoid cache timing issues
      final response = await supabase
          .from('Tasks')
          .select()
          .eq('category_id', widget.category.id)
          .eq('owner_id', userId)
          .order('created_at', ascending: false);

      final existingTasks = (response as List)
          .map((json) => Task.fromJson(json as Map<String, dynamic>))
          .toList();
      print(
          'AddTasksScreen: Found ${existingTasks.length} existing tasks in database');

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
      print('AddTasksScreen: Category: ${widget.category.headline}');
      print('AddTasksScreen: User ID: $userId');
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

      // Remove @ prefix if present for URL validation
      String urlToCheck = trimmedText;
      if (urlToCheck.startsWith('@')) {
        urlToCheck = urlToCheck.substring(1);
      }

      print('Checking if "$urlToCheck" is a valid URL...');
      print(
          'LinkProcessor.isValidUrl result: ${LinkProcessor.isValidUrl(urlToCheck)}');

      if (LinkProcessor.isValidUrl(urlToCheck)) {
        // Single URL detected - process it through LinkProcessor
        print('Single URL detected: $trimmedText');
        print('Taking single URL processing path...');

        try {
          print('AddTasksScreen: Processing URL: $urlToCheck');
          final processedLink = await LinkProcessor.validateAndProcessLink(
            urlToCheck,
            linkText: '', // Let LinkProcessor fetch the title
          );

          // For JustWatch URLs, try to fetch the description immediately
          String? initialNotes;
          if (urlToCheck.contains('justwatch.com')) {
            try {
              print('AddTasksScreen: Fetching JustWatch description for URL: $urlToCheck');
              initialNotes = await _fetchJustWatchDescription(urlToCheck);
              if (initialNotes != null && initialNotes.isNotEmpty) {
                print('AddTasksScreen: Found JustWatch description: ${initialNotes.substring(0, initialNotes.length > 50 ? 50 : initialNotes.length)}...');
              }
            } catch (e) {
              print('AddTasksScreen: Error fetching JustWatch description: $e');
            }
          }

          // Create a task object for duplicate checking
          final newTask = Task(
            id: DateTime.now().millisecondsSinceEpoch, // Temporary ID
            categoryId: widget.category.id,
            headline: processedLink.title ?? 'Link Task',
            notes: initialNotes,
            ownerId: userId,
            createdAt: DateTime.now(),
            suggestibleAt: null, // Set to null to appear at the beginning
            links: [
              processedLink.originalLink
            ], // Store the processed HTML link with title
            processedLinks: null,
            finished: false,
            shared: !widget.category
                .tasksArePrivate, // Use category's tasksArePrivate setting
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
            final cacheManager = CacheManager();
            await cacheManager.addTask(newTask);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Created task: "${newTask.headline}"'),
                backgroundColor: Colors.green,
              ),
            );
          }

          // Cache is already updated by addTask, no need to refresh

          // Clear the text input
          _textInputController.clear();

          // Navigate to Edit Category screen for cached category
          if (mounted) {
            _navigateToEditCategory();
          }
          return;
        } catch (e) {
          print('Error processing single URL: $e');

          // If URL processing fails, create a task with a reasonable title and proper link
          // Extract a title from the URL for better UX
          String fallbackTitle = trimmedText;
          try {
            final uri = Uri.parse(trimmedText);
            if (uri.host.contains('justwatch.com')) {
              final pathParts = uri.path.split('/').where((part) => part.isNotEmpty).toList();
              if (pathParts.length >= 2 && pathParts[pathParts.length - 2] == 'movie') {
                final movieSlug = pathParts.last;
                fallbackTitle = movieSlug
                    .replaceAll('-', ' ')
                    .split(' ')
                    .map((word) {
                      if (word.isEmpty) return word;
                      return word[0].toUpperCase() + word.substring(1).toLowerCase();
                    })
                    .join(' ');
              }
            }
          } catch (e) {
            // If URL parsing fails, keep the original URL as title
            fallbackTitle = trimmedText;
          }

          final newTask = Task(
            id: DateTime.now().millisecondsSinceEpoch, // Temporary ID
            categoryId: widget.category.id,
            headline: fallbackTitle, // Use extracted title or URL
            notes: 'Failed to fetch webpage title',
            ownerId: userId,
            createdAt: DateTime.now(),
            suggestibleAt: null, // Set to null to appear at the beginning
            links: ['<a href="$trimmedText">$fallbackTitle</a>'], // Store as proper HTML link
            processedLinks: null,
            finished: false,
            shared: !widget.category
                .tasksArePrivate, // Use category's tasksArePrivate setting
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
            final cacheManager = CacheManager();
            await cacheManager.addTask(newTask);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Created task with URL: "${newTask.headline}"'),
                backgroundColor: Colors.orange,
              ),
            );
          }

          // Cache is already updated by addTask, no need to refresh

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

      final inputText = _textInputController.text;
      print('AddTasksScreen: Input text: "$inputText"');
      print('AddTasksScreen: Text length: ${inputText.length}');
      print('AddTasksScreen: Contains \\r: ${inputText.contains('\r')}');
      print('AddTasksScreen: Contains \\n: ${inputText.contains('\n')}');

      await for (final task in TextImporter.processForNewCategory(
        inputText,
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
          links: task.links ?? <String>[],
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
          final cacheManager = CacheManager();
          await cacheManager.addTask(task);
          newTasksCreated++;
          print('Created new task: "${task.headline}"');
        }
      }

      // Wait longer for database transactions to commit, then refresh cache
      await Future.delayed(const Duration(milliseconds: 500));

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

      // Refresh cache after creating tasks
      final cacheManager = CacheManager();
      await cacheManager.initializeWithSavedCategory(widget.category, userId);

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
            'New ${NamingUtils.tasksName(capitalize: false, plural: false)} to ${widget.category.headline}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
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
                      'Register ${NamingUtils.tasksName(plural: true)}:',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'List one or more tasks, one per line:',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[800],
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
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
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _selectAndLoadFile,
                          icon: const Icon(Icons.upload_file),
                          tooltip: 'Upload text file',
                          style: AppButtons.iconGoForth(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
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
                            : 'Register ${NamingUtils.tasksName(plural: true)}'),
                        style: AppButtons.finalize(),
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
              '• Use "${NamingUtils.tasksName(plural: false)}: Note" format to include a note\n'
              '• Click the upload icon to load ${NamingUtils.tasksName(plural: true)} from various file types (.txt, .md, .csv, .rtf, .pdf, .doc, .docx, .odt)\n'
              '• Pasting a Share from elsewhere will do the right thing\n'
              '• So will pasting a URL (address-bar gobbledygook from a web page)\n'
              '• New ${NamingUtils.tasksName(plural: true)} will appear at the beginning of your list',
              style:
                  TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.3),
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
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: FractionallySizedBox(
                        widthFactor: 0.6,
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
