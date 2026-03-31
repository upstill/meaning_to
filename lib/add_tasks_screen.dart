import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/task_enricher.dart';
import 'package:meaning_to/utils/link_to_task_converter.dart';
import 'package:meaning_to/utils/app_buttons.dart';
import 'package:meaning_to/widgets/add_task_manually_button.dart';
import 'package:file_selector/file_selector.dart';
import 'package:meaning_to/dialogs/category_picker_dialog.dart';

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

  // Duplicate handling state
  bool? _rememberDuplicateChoice; // null = ask each time, true = add link, false = create new
  bool _applyToAllDuplicates = false;

  // Batch duplicate handling state (for multiple links with same headline in one batch)
  bool? _rememberBatchDuplicateChoice; // null = ask each time, true = combine, false = keep separate
  bool _applyToAllBatchDuplicates = false;

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

  /// Select and process a file directly into tasks
  Future<void> _selectAndLoadFile() async {
    try {
      const typeGroup = XTypeGroup(
        label: 'text files',
        extensions: ['txt', 'md', 'csv', 'rtf', 'pdf', 'doc', 'docx', 'odt'],
      );
      const allFiles = XTypeGroup(label: 'All files');

      final XFile? file = await openFile(
        acceptedTypeGroups: [typeGroup, allFiles],
      );

      if (file != null) {
        await _processUploadedFile(file);
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

  /// Process an uploaded file and create tasks
  Future<void> _processUploadedFile(XFile file) async {
    try {
      // Reset duplicate choice state for this new import batch
      _rememberDuplicateChoice = null;
      _applyToAllDuplicates = false;

      final String contents = await file.readAsString();
      String processedContents = contents;

      // Handle different file types
      final fileName = file.name.toLowerCase();
      if (fileName.endsWith('.rtf')) {
        processedContents = _rtfToText(contents);
      } else if (fileName.endsWith('.pdf')) {
        // For PDF files, we'll need to extract text
        // This is a placeholder - you might want to add a PDF parser
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF text extraction not yet implemented'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      } else if (fileName.endsWith('.doc') || fileName.endsWith('.docx')) {
        // For Word documents, we'll need to extract text
        // This is a placeholder - you might want to add a DOC parser
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Word document text extraction not yet implemented'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      // For txt, md, csv, odt - use as is

      // Detect origin hint from filename
      final originHint = _detectOriginHint(fileName);

      // Get current user ID
      final userId = AuthUtils.getCurrentUserId();

      // Process the file contents using TaskEnricher.processBulkInput
      final results = await TaskEnricher.processBulkInput(
        inputText: processedContents,
        categoryId: widget.category.id,
        ownerId: userId,
        originSiteHint: originHint,
      );

      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No tasks found in file'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Process each task result for duplicate checking and database operations
      // Note: Using query-based duplicate detection, no need to pre-load tasks
      int createdCount = 0;
      int updatedCount = 0;

      for (final result in results) {
        // Set shared property based on category setting
        final taskToSave = Task(
          id: result.enrichedTask.id,
          categoryId: result.enrichedTask.categoryId,
          headline: result.enrichedTask.headline,
          notes: result.enrichedTask.notes,
          ownerId: result.enrichedTask.ownerId,
          createdAt: result.enrichedTask.createdAt,
          suggestibleAt: null, // Set to null to appear at the beginning
          links: result.enrichedTask.links,
          processedLinks: result.enrichedTask.processedLinks,
          finished: result.enrichedTask.finished,
          shared: !widget.category
              .tasksArePrivate, // Use category's tasksArePrivate setting
        );

        // Check for duplicates and merge information if needed (query-based, efficient)
        final existingOrUpdatedTask = await _checkForDuplicateAndMerge(taskToSave);

        if (existingOrUpdatedTask != null &&
            existingOrUpdatedTask.id != taskToSave.id) {
          // This was a duplicate - existing task was updated
          updatedCount++;

          // Updated task will be found by the query-based duplicate detection
        } else {
          // No duplicate found - create new task
          final cacheManager = CacheManager();
          await cacheManager.addTask(taskToSave);
          createdCount++;

          // New task will be found by the query-based duplicate detection
        }
      }

      // Show summary message
      final summary = <String>[];
      if (createdCount > 0) summary.add('$createdCount new');
      if (updatedCount > 0) summary.add('$updatedCount updated');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'File processed: ${summary.join(', ')} tasks from ${file.name}'),
          backgroundColor: Colors.green,
        ),
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error processing file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Detect origin site hint from filename
  String? _detectOriginHint(String fileName) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.contains('justwatch')) {
      return 'justwatch.com';
    } else if (lowerName.contains('letterboxd')) {
      return 'letterboxd.com';
    }
    // Could add more site detection logic based on filename patterns
    return null;
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


  /// Extract the link text from an HTML link
  /// Example: '<a href="url">Link Text</a>' -> 'Link Text'
  String? _extractLinkText(String htmlLink) {
    final match = RegExp(r'<a[^>]+>([^<]+)</a>').firstMatch(htmlLink);
    return match?.group(1);
  }

  /// Show dialog to pick a category for a new task
  /// Uses the existing CategoryPickerDialog component with smart suggestions
  /// Returns a map with 'category' and 'applyToAll' keys
  Future<Map<String, dynamic>?> _showCategoryPickerDialog({
    List<int>? suggestedOriginalIds,
    bool showApplyToAll = false,
    String? linkUrl,
    String? linkText,
  }) async {
    Category? selectedCategory;
    bool selectedApplyToAll = false;

    // Show the existing CategoryPickerDialog with optional checkbox
    await CategoryPickerDialog.show(
      context,
      title: 'Choose ${NamingUtils.categoriesName(capitalize: true, plural: false)}',
      subtitle: linkText != null
          ? 'Select a ${NamingUtils.categoriesName(capitalize: false, plural: false)} for "$linkText"'
          : null,
      suggestedCategoryIds: suggestedOriginalIds,
      linkUrl: linkUrl,
      showCreateNew: true,
      showApplyToAllCheckbox: showApplyToAll,
      onCategorySelected: (category, {bool? shouldMove, bool? applyToAll}) {
        selectedCategory = category;
        selectedApplyToAll = applyToAll ?? false;
      },
    );

    // If user cancelled, return null
    if (selectedCategory == null) {
      return null;
    }

    return {
      'category': selectedCategory,
      'applyToAll': selectedApplyToAll,
    };
  }

  /// Show dialog asking user what to do with duplicate task
  /// Returns true if link should be added to existing task, false if new task should be created
  Future<bool?> _showDuplicateDialog(Task existingTask, Task newTask) async {
    bool applyToAll = false;

    // Fetch the category name for the existing task
    final categoryName = await ApiClient.getCategoryHeadlineById(existingTask.categoryId);

    // Extract the link text from the new task
    String? newLinkText;
    if (newTask.links != null && newTask.links!.isNotEmpty) {
      newLinkText = _extractLinkText(newTask.links!.first);
    }

    // Check if the new link already exists in the existing task
    bool linkAlreadyExists = false;
    if (newTask.links != null && newTask.links!.isNotEmpty && existingTask.links != null) {
      final newUrl = _extractUrlFromHtmlLink(newTask.links!.first);
      if (newUrl != null) {
        for (final existingLink in existingTask.links!) {
          final existingUrl = _extractUrlFromHtmlLink(existingLink);
          if (existingUrl != null && newUrl == existingUrl) {
            linkAlreadyExists = true;
            break;
          }
        }
      }
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Duplicate ${NamingUtils.tasksName(capitalize: true, plural: false)} Found'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    linkAlreadyExists
                        ? 'The link'
                        : 'The link',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  if (newLinkText != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      child: Text(
                        newLinkText,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    linkAlreadyExists
                        ? 'is already included in the existing ${NamingUtils.tasksName(capitalize: false, plural: false)}'
                        : 'looks like it belongs in the existing ${NamingUtils.tasksName(capitalize: false, plural: false)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0),
                    child: Text(
                      existingTask.headline,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  if (categoryName != null) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'as filed under',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      child: Text(
                        categoryName,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('Would you like to:', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 8),
                  Text(
                    linkAlreadyExists
                        ? '• Leave the existing ${NamingUtils.tasksName(capitalize: false, plural: false)} as it is, or'
                        : '• Include this link in the existing ${NamingUtils.tasksName(capitalize: false, plural: false)}, or',
                    style: const TextStyle(fontSize: 13),
                  ),
                  Text(
                    '• Create a new ${NamingUtils.tasksName(capitalize: false, plural: false)} with the same name',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text(
                      'Apply to other duplicate links',
                      style: TextStyle(fontSize: 14),
                    ),
                    value: applyToAll,
                    onChanged: (value) {
                      setState(() {
                        applyToAll = value ?? false;
                      });
                    },
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    if (applyToAll) {
                      _applyToAllDuplicates = true;
                      _rememberDuplicateChoice = true;
                    }
                    Navigator.of(context).pop(true); // Add link
                  },
                  child: Text('Keep Existing ${NamingUtils.tasksName(capitalize: true, plural: false)}'),
                ),
                TextButton(
                  onPressed: () {
                    if (applyToAll) {
                      _applyToAllDuplicates = true;
                      _rememberDuplicateChoice = false;
                    }
                    Navigator.of(context).pop(false); // Create new task
                  },
                  child: Text('Create New ${NamingUtils.tasksName(capitalize: true, plural: false)}'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Check if a task with the same headline or same link already exists and merge information if needed
  /// Uses efficient query-based duplicate detection instead of loading all tasks into memory
  Future<Task?> _checkForDuplicateAndMerge(Task newTask) async {
    print('=== DUPLICATE DETECTION START ===');
    print('Checking for duplicates of: "${newTask.headline}"');
    print('New task links: ${newTask.links}');

    // Define special categories that require user confirmation for duplicate headlines
    const streamingMusicCategories = [41, 54, 74]; // Streaming media categories
    const movieTvCategories = [1, 2]; // Movie and TV categories
    final specialCategories = [...streamingMusicCategories, ...movieTvCategories];
    final isSpecialCategory = specialCategories.contains(widget.category.originalId);

    // Use efficient query-based duplicate detection
    // Only searches within user's categories that have matching original_ids
    final userId = AuthUtils.getCurrentUserId();
    final existingTask = await ApiClient.findDuplicateTask(
      userId: userId,
      headline: newTask.headline,
      links: newTask.links,
      categoryOriginalIds: specialCategories,
    );

    if (existingTask != null) {
      print(
          'Found existing task: "${existingTask.headline}" (ID: ${existingTask.id})');
      print('New task: "${newTask.headline}" (ID: ${newTask.id})');
      print('Are they the same? ${existingTask.id == newTask.id}');

      // Found a duplicate - merge information
      print('Found duplicate task: "${newTask.headline}"');
      print('=== DUPLICATE DETECTION END - DUPLICATE FOUND ===');

      // For special categories, ask user what to do (unless they've already chosen "apply to all")
      bool shouldAddLink = true; // Default behavior for non-special categories

      if (isSpecialCategory && newTask.links != null && newTask.links!.isNotEmpty) {
        // Check if user has already made a choice for all duplicates
        if (_applyToAllDuplicates && _rememberDuplicateChoice != null) {
          shouldAddLink = _rememberDuplicateChoice!;
          print('Using remembered choice: ${shouldAddLink ? "add link" : "create new"}');
        } else {
          // Ask user what to do
          print('Asking user what to do with duplicate...');
          final userChoice = await _showDuplicateDialog(existingTask, newTask);

          if (userChoice == null) {
            // User cancelled - treat as create new task
            print('User cancelled dialog - creating new task');
            return null;
          }

          shouldAddLink = userChoice;
          print('User chose: ${shouldAddLink ? "add link" : "create new"}');
        }
      }

      // If user chose to create a new task, return null
      if (!shouldAddLink) {
        print('Creating new task as per user choice');
        return null;
      }

      // User chose to add link (or it's not a special category) - merge information
      Map<String, dynamic> updateData = {};
      List<String>? updatedLinks = existingTask.links != null
          ? List<String>.from(existingTask.links!)
          : [];

      // Add new links only if they don't already exist
      if (newTask.links != null && newTask.links!.isNotEmpty) {
        print('  -> Processing ${newTask.links!.length} new links for addition');
        print('  -> Existing task currently has ${updatedLinks.length} links');

        for (final newLink in newTask.links!) {
          print('  -> Checking new link: $newLink');
          final newUrl = _extractUrlFromHtmlLink(newLink);
          print('  -> Extracted new URL: $newUrl');
          bool linkExists = false;

          // Check if this link already exists in the task
          for (final existingLink in updatedLinks) {
            final existingUrl = _extractUrlFromHtmlLink(existingLink);
            print('  -> Comparing with existing URL: $existingUrl');
            if (newUrl != null && existingUrl != null && newUrl == existingUrl) {
              linkExists = true;
              print('  -> ✗ Link already exists, skipping: $newUrl');
              break;
            }
          }

          if (!linkExists) {
            updatedLinks.add(newLink);
            print('  -> ✓ Added new link! Total links now: ${updatedLinks.length}');
          }
        }

        // Always include links in update to ensure database has complete list
        updateData['links'] = updatedLinks.isNotEmpty ? updatedLinks : null;
        if (updatedLinks.length > (existingTask.links?.length ?? 0)) {
          print('  -> Added new links! Will update database with ${updatedLinks.length} total links');
        } else {
          print('  -> No new links added (all were duplicates), but updating database anyway');
        }
      }

      // Add notes if the new task has them and the existing task doesn't
      if (newTask.notes != null &&
          newTask.notes!.isNotEmpty &&
          (existingTask.notes == null || existingTask.notes!.isEmpty)) {
        updateData['notes'] = newTask.notes;
        print('  -> Adding notes to existing task');
      }

      // Always update the existing task to move it to the top of the list
      // Set suggestibleAt to null to make it appear first
      try {
        final userId = AuthUtils.getCurrentUserId();

        // Add suggestibleAt: null to the update data to move task to top
        updateData['suggestible_at'] = null;

        print('  -> About to update database with:');
        print('     Task ID: ${existingTask.id}');
        print('     Update data keys: ${updateData.keys.toList()}');
        if (updateData.containsKey('links')) {
          print('     Links to save: ${(updateData['links'] as List).length} links');
          for (int i = 0; i < (updateData['links'] as List).length; i++) {
            print('       Link $i: ${(updateData['links'] as List)[i]}');
          }
        } else {
          print('     WARNING: No links in updateData!');
        }

        final response = await supabase
            .from('Tasks')
            .update(updateData)
            .eq('id', existingTask.id)
            .eq('owner_id', userId)
            .select()
            .single();

        print('  -> Database update successful');
        print('  -> Response links: ${response['links']}');

        // Create the updated task object
        // IMPORTANT: Use updatedLinks directly, not updateData['links']
        // because updateData['links'] is only set if we added NEW links,
        // but updatedLinks always contains all links (existing + new)
        final updatedTask = Task(
          id: existingTask.id,
          categoryId: existingTask.categoryId,
          ownerId: existingTask.ownerId,
          headline: existingTask.headline,
          notes: updateData['notes'] ?? existingTask.notes,
          links: updatedLinks.isNotEmpty ? updatedLinks : null,
          processedLinks: existingTask.processedLinks,
          createdAt: existingTask.createdAt,
          suggestibleAt: null, // Set to null to move to top
          finished: existingTask.finished,
        );

        print('  -> Updated task object created with ${updatedTask.links?.length ?? 0} total links');

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

  /// Check if a string is a URL
  bool _isUrl(String text) {
    final trimmed = text.trim();
    return trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('www.');
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
      // Reset duplicate choice state for this new import batch
      _rememberDuplicateChoice = null;
      _applyToAllDuplicates = false;

      setState(() {
        _isLoading = true;
      });

      final userId = AuthUtils.getCurrentUserId();

      // Using query-based duplicate detection - no need to load all tasks into memory
      print('AddTasksScreen: Category: ${widget.category.headline}');
      print('AddTasksScreen: User ID: $userId');
      print('AddTasksScreen: Using query-based duplicate detection');

      // Check if the input is single line or multi-line
      final trimmedText = _textInputController.text.trim();

      // Handle case where headline is empty but currentTask has links - use link as input
      if (trimmedText.isEmpty &&
          widget.currentTask != null &&
          widget.currentTask!.links != null &&
          widget.currentTask!.links!.isNotEmpty) {
        print(
            'AddTasksScreen: Empty headline but currentTask has links, using first link as input');
        final linkToProcess = widget.currentTask!.links!.first;
        print('AddTasksScreen: Processing link: $linkToProcess');

        try {
          final enrichmentResult = await TaskEnricher.processSingleLineInput(
            inputLine: linkToProcess,
            categoryId: widget.category.id,
            ownerId: userId,
          );

          // Set shared property based on category setting
          final newTask = Task(
            id: enrichmentResult.enrichedTask.id,
            categoryId: enrichmentResult.enrichedTask.categoryId,
            headline: enrichmentResult.enrichedTask.headline,
            notes: enrichmentResult.enrichedTask.notes,
            ownerId: enrichmentResult.enrichedTask.ownerId,
            createdAt: enrichmentResult.enrichedTask.createdAt,
            suggestibleAt: null, // Set to null to appear at the beginning
            links: enrichmentResult.enrichedTask.links,
            processedLinks: enrichmentResult.enrichedTask.processedLinks,
            finished: enrichmentResult.enrichedTask.finished,
            shared: !widget.category
                .tasksArePrivate, // Use category's tasksArePrivate setting
          );

          print(
              'AddTasksScreen: Created task from link with headline: "${newTask.headline}"');
          print('AddTasksScreen: Task links: ${newTask.links}');

          // Check for duplicates and merge information if needed (query-based, efficient)
          final existingOrUpdatedTask = await _checkForDuplicateAndMerge(newTask);

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

          // Clear the text input
          _textInputController.clear();

          if (mounted) {
            Navigator.pop(context, true);
          }
          return;
        } catch (e) {
          print('Error processing link from currentTask: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error processing link: $e'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      final lines = trimmedText
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();

      if (lines.length == 1) {
        // Single line input
        print('Single line input detected: $trimmedText');

        try {
          Task newTask;

          // Check if this is a URL - if so, use LinkToTaskConverter
          if (_isUrl(trimmedText)) {
            print('Single line is a URL, using LinkToTaskConverter');

            // Use LinkToTaskConverter for proper headline/notes extraction
            final proposedTask =
                await LinkToTaskConverter.createProposedTaskFromLink(
              trimmedText,
              userId,
              currentCategory: null, // Don't pass current category, we'll pick it later
            );

            print(
                'AddTasksScreen: ProposedTask created - headline: "${proposedTask.headline}", notes: "${proposedTask.notes}"');
            print(
                'AddTasksScreen: Suggested category IDs: ${proposedTask.suggestedCategoryOriginalIds}');

            // Check for duplicates using the suggested categories
            final existingTask = await ApiClient.findDuplicateTask(
              userId: userId,
              headline: proposedTask.headline,
              links: proposedTask.links,
              categoryOriginalIds: proposedTask.suggestedCategoryOriginalIds.isNotEmpty
                  ? proposedTask.suggestedCategoryOriginalIds
                  : [1, 2, 41, 54, 74], // Fallback to common categories
            );

            if (existingTask != null) {
              print('Found duplicate task: "${existingTask.headline}"');

              // Check if user has already made a choice for all duplicates
              bool? shouldAddLink;
              if (_applyToAllDuplicates && _rememberDuplicateChoice != null) {
                shouldAddLink = _rememberDuplicateChoice!;
                print('Using remembered choice for duplicate: ${shouldAddLink ? "add link" : "create new"}');
              } else {
                // Show "keep or add" dialog
                shouldAddLink = await _showDuplicateDialog(
                  existingTask,
                  Task(
                    id: DateTime.now().millisecondsSinceEpoch,
                    categoryId: existingTask.categoryId,
                    headline: proposedTask.headline,
                    notes: proposedTask.notes,
                    ownerId: userId,
                    createdAt: DateTime.now(),
                    links: proposedTask.links,
                    synopsis: proposedTask.synopsis,
                    finished: false,
                  ),
                );
              }

              if (shouldAddLink == null) {
                // User cancelled
                setState(() {
                  _isLoading = false;
                });
                return;
              }

              if (shouldAddLink) {
                // Add link to existing task
                final updatedLinks = existingTask.links != null
                    ? List<String>.from(existingTask.links!)
                    : [];

                // Add new links
                for (final newLink in proposedTask.links) {
                  final newUrl = _extractUrlFromHtmlLink(newLink);
                  bool linkExists = false;

                  for (final existingLink in updatedLinks) {
                    final existingUrl = _extractUrlFromHtmlLink(existingLink);
                    if (newUrl != null && existingUrl != null && newUrl == existingUrl) {
                      linkExists = true;
                      break;
                    }
                  }

                  if (!linkExists) {
                    updatedLinks.add(newLink);
                  }
                }

                // Update existing task
                await supabase
                    .from('Tasks')
                    .update({
                      'links': updatedLinks,
                      'suggestible_at': null,
                    })
                    .eq('id', existingTask.id)
                    .eq('owner_id', userId);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Updated existing task: "${existingTask.headline}"'),
                    backgroundColor: Colors.blue,
                  ),
                );

                _textInputController.clear();
                if (mounted) {
                  Navigator.pop(context, true);
                }
                return;
              }
              // If shouldAddLink is false, continue to create new task with category picker
            }

            // No duplicate found (or user chose to create new) - show category picker
            print('No duplicate found, showing category picker');

            // Extract URL and text from the first link
            String? linkUrl;
            String? linkText;
            if (proposedTask.links.isNotEmpty) {
              linkUrl = LinkToTaskConverter.extractUrlFromHtmlLink(proposedTask.links.first);
              linkText = _extractLinkText(proposedTask.links.first);
            }

            final result = await _showCategoryPickerDialog(
              suggestedOriginalIds: proposedTask.suggestedCategoryOriginalIds,
              showApplyToAll: false, // Single link, no need for "apply to all"
              linkUrl: linkUrl,
              linkText: linkText,
            );

            if (result == null) {
              // User cancelled category selection
              setState(() {
                _isLoading = false;
              });
              return;
            }

            final selectedCategory = result['category'] as Category;
            print('User selected category: "${selectedCategory.headline}"');

            // Convert ProposedTask to Task with selected category
            newTask = Task(
              id: DateTime.now().millisecondsSinceEpoch,
              categoryId: selectedCategory.id,
              headline: proposedTask.headline,
              notes: proposedTask.notes,
              ownerId: userId,
              createdAt: DateTime.now(),
              suggestibleAt: null, // Set to null to appear at the beginning
              links: proposedTask.links,
              synopsis: proposedTask.synopsis,
              originalId: proposedTask.existingTaskOriginalId,
              finished: false,
              shared: !selectedCategory
                  .tasksArePrivate, // Use selected category's tasksArePrivate setting
            );
          } else {
            print('Single line is not a URL, using TaskEnricher');

            // Use TaskEnricher for non-URL text
            final enrichmentResult = await TaskEnricher.processSingleLineInput(
              inputLine: trimmedText,
              categoryId: widget.category.id,
              ownerId: userId,
            );

            // Set shared property based on category setting
            newTask = Task(
              id: enrichmentResult.enrichedTask.id,
              categoryId: enrichmentResult.enrichedTask.categoryId,
              headline: enrichmentResult.enrichedTask.headline,
              notes: enrichmentResult.enrichedTask.notes,
              ownerId: enrichmentResult.enrichedTask.ownerId,
              createdAt: enrichmentResult.enrichedTask.createdAt,
              suggestibleAt: null, // Set to null to appear at the beginning
              links: enrichmentResult.enrichedTask.links,
              processedLinks: enrichmentResult.enrichedTask.processedLinks,
              finished: enrichmentResult.enrichedTask.finished,
              shared: !widget.category
                  .tasksArePrivate, // Use category's tasksArePrivate setting
            );
          }

          print(
              'AddTasksScreen: Created task with headline: "${newTask.headline}"');
          print('AddTasksScreen: Task links: ${newTask.links}');

          // Create new task (duplicate checking already handled above for URLs)
          final cacheManager = CacheManager();
          await cacheManager.addTask(newTask);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Created task: "${newTask.headline}"'),
              backgroundColor: Colors.green,
            ),
          );

          // Clear the text input
          _textInputController.clear();

          if (mounted) {
            Navigator.pop(context, true);
          }
          return;
        } catch (e) {
          print('Error processing single line input: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error processing input: $e'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      // Multi-line input - process each line with TaskEnricher
      final inputText = _textInputController.text;
      print('AddTasksScreen: Multi-line input text: "$inputText"');
      print('AddTasksScreen: Text length: ${inputText.length}');

      // Split input into lines and process each line
      final inputLines = inputText
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      print('AddTasksScreen: Processing ${inputLines.length} lines');

      // Track category selection for URLs
      Category? rememberedCategoryForUrls;
      bool applyToAllRemaining = false;

      // Track updated tasks (for duplicates that were merged)
      int updatedTasksCount = 0;

      // Now process each line
      final tasksToProcess = <Task>[];

      for (int i = 0; i < inputLines.length; i++) {
        final line = inputLines[i];
        print('AddTasksScreen: Processing line ${i + 1}: "$line"');

        // Show progress for multi-line processing at the start of each iteration
        if (inputLines.length > 1 && mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Processing ${i + 1} of ${inputLines.length}...'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.blue[700],
            ),
          );
        }

        try {
          Task modifiedTask;

          // Check if this line is a URL - if so, use LinkToTaskConverter
          if (_isUrl(line)) {
            print('AddTasksScreen: Line is a URL, using LinkToTaskConverter');

            // Use LinkToTaskConverter for proper headline/notes extraction
            final proposedTask =
                await LinkToTaskConverter.createProposedTaskFromLink(
              line,
              userId,
              currentCategory: null,
            );

            print(
                'AddTasksScreen: ProposedTask created - headline: "${proposedTask.headline}", notes: "${proposedTask.notes}"');

            // Check for duplicates
            final existingTask = await ApiClient.findDuplicateTask(
              userId: userId,
              headline: proposedTask.headline,
              links: proposedTask.links,
              categoryOriginalIds: proposedTask.suggestedCategoryOriginalIds.isNotEmpty
                  ? proposedTask.suggestedCategoryOriginalIds
                  : [1, 2, 41, 54, 74],
            );

            if (existingTask != null) {
              print('Found duplicate for line ${i + 1}: "${existingTask.headline}"');

              // Check if user has already made a choice for all duplicates
              bool? shouldAddLink;
              if (_applyToAllDuplicates && _rememberDuplicateChoice != null) {
                shouldAddLink = _rememberDuplicateChoice!;
                print('Using remembered choice for duplicate: ${shouldAddLink ? "add link" : "create new"}');
              } else {
                // Show "keep or add" dialog
                shouldAddLink = await _showDuplicateDialog(
                  existingTask,
                  Task(
                    id: DateTime.now().millisecondsSinceEpoch,
                    categoryId: existingTask.categoryId,
                    headline: proposedTask.headline,
                    notes: proposedTask.notes,
                    ownerId: userId,
                    createdAt: DateTime.now(),
                    links: proposedTask.links,
                    synopsis: proposedTask.synopsis,
                    finished: false,
                  ),
                );
              }

              if (shouldAddLink == null) {
                // User cancelled
                continue;
              }

              if (!shouldAddLink) {
                // User chose to create new task - fall through to category picker below
              } else {
                // Add link to existing task
                final updatedLinks = existingTask.links != null
                    ? List<String>.from(existingTask.links!)
                    : [];

                for (final newLink in proposedTask.links) {
                  final newUrl = _extractUrlFromHtmlLink(newLink);
                  bool linkExists = false;

                  for (final existingLink in updatedLinks) {
                    final existingUrl = _extractUrlFromHtmlLink(existingLink);
                    if (newUrl != null && existingUrl != null && newUrl == existingUrl) {
                      linkExists = true;
                      break;
                    }
                  }

                  if (!linkExists) {
                    updatedLinks.add(newLink);
                  }
                }

                // Update existing task
                await supabase
                    .from('Tasks')
                    .update({
                      'links': updatedLinks,
                      'suggestible_at': null,
                    })
                    .eq('id', existingTask.id)
                    .eq('owner_id', userId);

                updatedTasksCount++;
                print('Updated existing task with new link');
                continue;
              }
            }

            // No duplicate (or user chose to create new) - need a category
            Category? selectedCategory;

            if (applyToAllRemaining && rememberedCategoryForUrls != null) {
              // Use remembered category
              selectedCategory = rememberedCategoryForUrls;
              print('Using remembered category: "${selectedCategory.headline}"');
            } else {
              // Show category picker
              // Count remaining URLs to decide if we should show "apply to all" checkbox
              final remainingUrlCount = inputLines.skip(i + 1).where((line) => _isUrl(line)).length;
              final showApplyToAll = remainingUrlCount > 0;

              // Extract URL and text from the first link
              String? linkUrl;
              String? linkText;
              if (proposedTask.links.isNotEmpty) {
                linkUrl = LinkToTaskConverter.extractUrlFromHtmlLink(proposedTask.links.first);
                linkText = _extractLinkText(proposedTask.links.first);
              }

              print('Showing category picker (remaining URLs: $remainingUrlCount)');
              final result = await _showCategoryPickerDialog(
                suggestedOriginalIds: proposedTask.suggestedCategoryOriginalIds,
                showApplyToAll: showApplyToAll,
                linkUrl: linkUrl,
                linkText: linkText,
              );

              if (result == null) {
                // User cancelled
                print('User cancelled category selection');
                continue;
              }

              selectedCategory = result['category'] as Category;
              applyToAllRemaining = result['applyToAll'] as bool;

              if (applyToAllRemaining) {
                rememberedCategoryForUrls = selectedCategory;
                print('User selected category: "${selectedCategory.headline}" and chose to apply to all remaining');
              } else {
                print('User selected category: "${selectedCategory.headline}"');
              }
            }

            // Create task with selected category
            modifiedTask = Task(
              id: DateTime.now().millisecondsSinceEpoch,
              categoryId: selectedCategory.id,
              headline: proposedTask.headline,
              notes: proposedTask.notes,
              ownerId: userId,
              createdAt: DateTime.now(),
              suggestibleAt: null,
              links: proposedTask.links,
              synopsis: proposedTask.synopsis,
              originalId: proposedTask.existingTaskOriginalId,
              finished: false,
              shared: !selectedCategory.tasksArePrivate,
            );
          } else {
            print('AddTasksScreen: Line is not a URL, using TaskEnricher');

            // Use TaskEnricher for non-URL text
            final enrichmentResult = await TaskEnricher.processSingleLineInput(
              inputLine: line,
              categoryId: widget.category.id,
              ownerId: userId,
            );

            // Set shared property based on category setting and suggestibleAt to null
            modifiedTask = Task(
              id: enrichmentResult.enrichedTask.id,
              categoryId: enrichmentResult.enrichedTask.categoryId,
              headline: enrichmentResult.enrichedTask.headline,
              notes: enrichmentResult.enrichedTask.notes,
              ownerId: enrichmentResult.enrichedTask.ownerId,
              createdAt: enrichmentResult.enrichedTask.createdAt,
              suggestibleAt: null, // Set to null to appear at the beginning
              links: enrichmentResult.enrichedTask.links,
              processedLinks: enrichmentResult.enrichedTask.processedLinks,
              finished: enrichmentResult.enrichedTask.finished,
              shared: !widget.category
                  .tasksArePrivate, // Use category's tasksArePrivate setting
            );
          }

          // Check for batch duplicates (same headline within the current batch)
          final existingTaskInBatch = tasksToProcess.where((t) => t.headline == modifiedTask.headline).firstOrNull;

          if (existingTaskInBatch != null) {
            print('Found batch duplicate: "${modifiedTask.headline}"');

            // Check if we have a remembered choice
            bool shouldCombine;

            // If user already chose to add links to existing tasks via the duplicate dialog,
            // apply that same choice to batch duplicates
            if (_applyToAllDuplicates && _rememberDuplicateChoice != null && _rememberDuplicateChoice == true) {
              shouldCombine = true;
              print('Using remembered duplicate choice (add to existing) for batch duplicate');
            } else if (_applyToAllBatchDuplicates && _rememberBatchDuplicateChoice != null) {
              shouldCombine = _rememberBatchDuplicateChoice!;
              print('Using remembered batch duplicate choice: ${shouldCombine ? "combine" : "keep separate"}');
            } else {
              // COMMENTED OUT: Show consolidation dialog
              // Default to combining links with the same headline
              shouldCombine = true;
              print('Auto-combining batch duplicate (dialog commented out)');

              // // Show consolidation dialog
              // final userChoice = await _showConsolidateLinksDialog(
              //   modifiedTask.headline,
              //   2, // At least 2 links (existing + new)
              // );

              // if (userChoice == null) {
              //   // User cancelled
              //   print('User cancelled batch consolidation');
              //   continue;
              // }

              // shouldCombine = userChoice;
            }

            if (shouldCombine) {
              // Combine links into the existing task
              final List<String> updatedLinks = existingTaskInBatch.links != null
                  ? List<String>.from(existingTaskInBatch.links!)
                  : <String>[];

              // Add new links if they don't already exist
              for (final newLink in modifiedTask.links ?? []) {
                final newUrl = _extractUrlFromHtmlLink(newLink);
                bool linkExists = false;

                for (final existingLink in updatedLinks) {
                  final existingUrl = _extractUrlFromHtmlLink(existingLink);
                  if (newUrl != null && existingUrl != null && newUrl == existingUrl) {
                    linkExists = true;
                    break;
                  }
                }

                if (!linkExists) {
                  updatedLinks.add(newLink);
                }
              }

              // Update the existing task in the batch with the new links
              final taskIndex = tasksToProcess.indexOf(existingTaskInBatch);
              tasksToProcess[taskIndex] = Task(
                id: existingTaskInBatch.id,
                categoryId: existingTaskInBatch.categoryId,
                headline: existingTaskInBatch.headline,
                notes: existingTaskInBatch.notes,
                ownerId: existingTaskInBatch.ownerId,
                createdAt: existingTaskInBatch.createdAt,
                suggestibleAt: existingTaskInBatch.suggestibleAt,
                links: updatedLinks,
                synopsis: existingTaskInBatch.synopsis ?? modifiedTask.synopsis,
                originalId: existingTaskInBatch.originalId,
                finished: existingTaskInBatch.finished,
                shared: existingTaskInBatch.shared,
              );

              print('Combined ${modifiedTask.links?.length ?? 0} new link(s) into existing batch task');
              continue; // Skip adding this as a separate task
            } else {
              // User chose to keep separate - add as normal
              print('Keeping as separate task per user choice');
            }
          }

          tasksToProcess.add(modifiedTask);
          print(
              'AddTasksScreen: Successfully processed line ${i + 1}: "${modifiedTask.headline}"');
        } catch (e) {
          print('AddTasksScreen: Error processing line ${i + 1} ("$line"): $e');
          // Continue processing other lines even if one fails
        }
      }

      // Create all new tasks (duplicate checking already handled above for URLs)
      int newTasksCreated = 0;

      for (final task in tasksToProcess) {
        print('Creating task: "${task.headline}" (ID: ${task.id})');

        // Insert task directly into database
        await supabase.from('Tasks').insert({
          'category_id': task.categoryId,
          'headline': task.headline,
          'notes': task.notes,
          'synopsis': task.synopsis,
          'owner_id': task.ownerId,
          'created_at': task.createdAt.toIso8601String(),
          'suggestible_at': task.suggestibleAt?.toIso8601String(),
          'triggers_at': task.triggersAt?.toIso8601String(),
          'deferral': task.deferral,
          'links': task.links ?? <String>[],
          'finished': task.finished,
          'shared': task.shared,
          'original_id': task.originalId,
        });

        newTasksCreated++;
        print('Created new task: "${task.headline}"');
      }

      // Check if we processed anything at all
      if (newTasksCreated == 0 && updatedTasksCount == 0) {
        throw Exception('No valid tasks found in text input');
      }

      // Wait longer for database transactions to commit, then refresh cache
      await Future.delayed(const Duration(milliseconds: 500));

      // Show success message
      String message;
      if (newTasksCreated > 0 && updatedTasksCount > 0) {
        message = 'Created $newTasksCreated new tasks and updated $updatedTasksCount existing tasks';
      } else if (newTasksCreated > 0) {
        message = 'Created $newTasksCreated new tasks';
      } else {
        message = 'Updated $updatedTasksCount existing tasks';
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
        title: Text(
            'New ${NamingUtils.tasksName(capitalize: true, plural: true)} to ${widget.category.headline}'),
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
                      'Register ${NamingUtils.tasksName(plural: true)}, one per line:',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    // const SizedBox(height: 12),
                    // Text(
                    //   'List ${NamingUtils.tasksName(plural: true)}, one per line:',
                    //   style: TextStyle(
                    //     fontSize: 14,
                    //     color: Colors.grey[800],
                    //     height: 1.2,
                    //   ),
                    // ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _textInputController,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText:
                                  '${NamingUtils.tasksName(capitalize: true, plural: false)} 1\n${NamingUtils.tasksName(capitalize: true, plural: false)} 2: A great ${NamingUtils.tasksName(capitalize: false, plural: false)}\n${NamingUtils.tasksName(capitalize: true, plural: false)} 3: https://example.com/${NamingUtils.tasksName(capitalize: false, plural: false)}3',
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
                    Row(
                      children: [
                        // Cancel button
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isLoading
                                ? null
                                : () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[300],
                              foregroundColor: Colors.black,
                              minimumSize: const Size(0, 48),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Register button
                        Expanded(
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
                            style: AppButtons.finalize().copyWith(
                              minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
                            ),
                          ),
                        ),
                      ],
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
