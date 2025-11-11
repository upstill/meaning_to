import 'package:flutter/material.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/dialogs/category_picker_dialog.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/utils/streaming_media_constants.dart';

/// Result of processing an incoming link
class LinkProcessingResult {
  final String url;
  final String? title;
  final String? description;
  final List<DuplicateMatch> duplicates;
  final bool hasValidMetadata;

  LinkProcessingResult({
    required this.url,
    this.title,
    this.description,
    required this.duplicates,
    required this.hasValidMetadata,
  });
}

/// Information about a duplicate link found in the system
class DuplicateMatch {
  final Task task;
  final Category category;
  final String matchingUrl;
  final String originalLinkText;

  DuplicateMatch({
    required this.task,
    required this.category,
    required this.matchingUrl,
    required this.originalLinkText,
  });
}

/// Actions user can take with an incoming link
enum LinkAction {
  createNewTask,
  addToExistingTask,
  viewExistingTask,
  cancel,
}

/// Service for processing incoming shared links
class IncomingLinkProcessor {
  /// Process an incoming link and return comprehensive results
  static Future<LinkProcessingResult> processIncomingLink(String url) async {
    print('IncomingLinkProcessor: Processing incoming link: $url');

    // Normalize and validate URL
    final normalizedUrl = _normalizeUrl(url);
    if (normalizedUrl == null) {
      throw ArgumentError('Invalid URL provided: $url');
    }

    // Extract metadata from the link
    String? title;
    String? description;
    bool hasValidMetadata = false;

    try {
      final content = await LinkProcessor.fetchWebpageContent(normalizedUrl);
      if (content != null) {
        title = content.title;
        description = content.description;
        hasValidMetadata = true;
        print('IncomingLinkProcessor: Extracted metadata - Title: "$title"');
      }
    } catch (e) {
      print('IncomingLinkProcessor: Failed to extract metadata: $e');
    }

    // Find all duplicates across user's tasks
    final duplicates = await findAllDuplicates(normalizedUrl);
    print('IncomingLinkProcessor: Found ${duplicates.length} duplicates');

    return LinkProcessingResult(
      url: normalizedUrl,
      title: title,
      description: description,
      duplicates: duplicates,
      hasValidMetadata: hasValidMetadata,
    );
  }

  /// Find all duplicate links across ALL tasks (not just user's tasks)
  static Future<List<DuplicateMatch>> findAllDuplicates(String url) async {
    final duplicates = <DuplicateMatch>[];

    try {
      final userId = AuthUtils.getCurrentUserId();

      print(
          'IncomingLinkProcessor: Checking for duplicates across ALL tasks in database');

      // Validate URL can be parsed
      final uri = Uri.tryParse(url);
      if (uri == null) {
        print('IncomingLinkProcessor: Could not parse URL: $url');
        return [];
      }

      // Fetch ALL tasks in the database to check for duplicates
      // This allows us to find tasks with the same link across all users
      // so we can properly set original_id for content linking
      final response = await supabase
          .from('Tasks')
          .select('*, Categories!Tasks_category_id_fkey(*)');
      // Note: No owner_id filter - we want to check ALL tasks

      final tasksData = response as List<dynamic>;
      print(
          'IncomingLinkProcessor: Found ${tasksData.length} total tasks in database');

      int matchingTasks = 0;
      int userDuplicates = 0;
      int otherUserTasks = 0;

      for (final taskData in tasksData) {
        try {
          final task = Task.fromJson(taskData);
          final categoryData = taskData['Categories'];

          if (categoryData == null) {
            print(
                'IncomingLinkProcessor: Skipping task ${task.headline} - no category data');
            continue;
          }

          final category = Category.fromJson(categoryData);

          // Check each link in the task
          for (final linkText in task.links ?? []) {
            final linkUrl = _extractUrlFromHtmlLink(linkText);
            if (linkUrl != null && _urlsMatch(url, linkUrl)) {
              matchingTasks++;

              // Only add to duplicates list if it's the current user's task
              if (task.ownerId == userId) {
                userDuplicates++;
                print(
                    'IncomingLinkProcessor: Found duplicate in user task "${task.headline}" in category "${category.headline}"');
                duplicates.add(DuplicateMatch(
                  task: task,
                  category: category,
                  matchingUrl: linkUrl,
                  originalLinkText: linkText,
                ));
              } else {
                otherUserTasks++;
                print(
                    'IncomingLinkProcessor: Found matching task from other user: "${task.headline}" (ID: ${task.id}, original_id: ${task.originalId})');
              }
            }
          }
        } catch (e) {
          print('IncomingLinkProcessor: Error processing task data: $e');
          continue;
        }
      }

      print('IncomingLinkProcessor: Summary:');
      print('  - Total matching tasks: $matchingTasks');
      print('  - User duplicates: $userDuplicates');
      print('  - Other user tasks: $otherUserTasks');
    } catch (e) {
      print('IncomingLinkProcessor: Error during duplicate check: $e');
    }

    return duplicates;
  }

  /// Find the original_id for a link by checking all tasks in the database
  static Future<int?> findOriginalIdForLink(String url) async {
    try {
      print('IncomingLinkProcessor: Finding original_id for URL: $url');

      // Fetch ALL tasks in the database to find the original
      final response = await supabase
          .from('Tasks')
          .select()
          .order('created_at', ascending: true); // Oldest first

      final tasksData = response as List<dynamic>;
      print(
          'IncomingLinkProcessor: Checking ${tasksData.length} tasks for original_id');

      for (final taskData in tasksData) {
        try {
          final task = Task.fromJson(taskData);

          // Check each link in the task
          for (final linkText in task.links ?? []) {
            final linkUrl = _extractUrlFromHtmlLink(linkText);
            if (linkUrl != null && _urlsMatch(url, linkUrl)) {
              // Found a task with this link
              // If it has an original_id, use that; otherwise use its own id
              final originalId = task.originalId ?? task.id;
              print(
                  'IncomingLinkProcessor: Found original_id: $originalId (from task: "${task.headline}", created: ${task.createdAt})');
              return originalId;
            }
          }
        } catch (e) {
          print(
              'IncomingLinkProcessor: Error processing task for original_id: $e');
          continue;
        }
      }

      print('IncomingLinkProcessor: No existing task found with this link');
      return null;
    } catch (e) {
      print('IncomingLinkProcessor: Error finding original_id: $e');
      return null;
    }
  }

  /// Show the main link action dialog to the user
  static Future<void> showLinkActionDialog(
    BuildContext context,
    String url, {
    Category? defaultCategory,
  }) async {
    print('IncomingLinkProcessor: Processing incoming link: $url');

    // Parse the incoming text as if it's from an import
    final result = await processIncomingLink(url);

    if (!context.mounted) return;

    // Check for URL duplicates first
    if (result.duplicates.isNotEmpty) {
      // Link exists - go to Edit Task
      await _navigateToEditExistingTask(context, result.duplicates.first);
      return;
    }

    // No URL duplicates - check if this is a Tidal link with artist matching
    if (isStreamingMediaUrl(result.url) && result.title != null) {
      final artistWorkInfo = extractArtistAndWorkFromTidal(result.title!);

      if (artistWorkInfo != null) {
        print(
            'IncomingLinkProcessor: Detected Tidal link - Artist: "${artistWorkInfo.artist}", Work: "${artistWorkInfo.work}"');

        // Search for existing task with this artist
        final userId = AuthUtils.getCurrentUserId();
        final existingTask = await findTaskByArtistInStreamingCategories(
            artistWorkInfo.artist, userId);

        if (existingTask != null && context.mounted) {
          // Found exactly one matching artist task
          // Get the category for the existing task
          final categoryResponse = await supabase
              .from('Categories')
              .select()
              .eq('id', existingTask.categoryId)
              .single();

          final category = Category.fromJson(categoryResponse);

          // Show dialog asking if user wants to add to existing or create new
          final userChoice = await _showArtistMatchDialog(
            context,
            existingTask,
            category,
            artistWorkInfo.work,
          );

          if (!context.mounted) return;

          if (userChoice == 'add') {
            // User wants to add to existing task
            await _navigateToAddWorkToExistingTask(
              context,
              existingTask,
              category,
              artistWorkInfo.work,
              result.url,
              result.title!,
            );
            return;
          } else if (userChoice == 'new') {
            // User wants to create new task - continue with normal flow
            // but use artist as headline and work as notes
            await _navigateToTaskEditScreenWithArtistWork(
              context,
              result,
              defaultCategory,
              artistWorkInfo,
            );
            return;
          }
          // If userChoice is null, user dismissed dialog - do nothing
          return;
        }

        // No matching artist found or multiple matches - create new task with artist/work
        await _navigateToTaskEditScreenWithArtistWork(
          context,
          result,
          defaultCategory,
          artistWorkInfo,
        );
        return;
      }
    }

    // Not a Tidal link or couldn't parse artist/work - use normal flow
    await _navigateToTaskEditScreen(context, result, defaultCategory);
  }

  /// Navigate to Edit Task screen for existing duplicate task
  static Future<void> _navigateToEditExistingTask(
    BuildContext context,
    DuplicateMatch duplicate,
  ) async {
    if (!context.mounted) return;

    try {
      print(
          'IncomingLinkProcessor: Navigating to edit existing task: ${duplicate.task.headline}');

      // Show dialog with three options
      final userChoice = await _showDuplicateOptionsDialog(context, duplicate);

      if (!context.mounted) return;

      if (userChoice == 'edit') {
        // User chose to edit the existing task
        final categoryResponse = await supabase
            .from('Categories')
            .select()
            .eq('id', duplicate.task.categoryId)
            .single();

        final category = Category.fromJson(categoryResponse);

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TaskEditScreen(
              category: category,
              task: duplicate.task,
            ),
          ),
        );
      } else if (userChoice == 'new') {
        // User chose to create a new task anyway
        print(
            'IncomingLinkProcessor: User chose to create new task despite duplicate');
        // Get the URL from the duplicate to use for the new task
        final url = duplicate.matchingUrl;

        // Process the link and navigate to create new task
        final result = await processIncomingLink(url);

        if (!context.mounted) return;

        // Navigate to new task screen
        await _navigateToTaskEditScreen(context, result, null);
      }
      // If userChoice is null or 'done', do nothing (user chose "All Done")
    } catch (e) {
      print(
          'IncomingLinkProcessor: Error navigating to edit existing task: $e');
    }
  }

  /// Show dialog with options for handling duplicate task
  static Future<String?> _showDuplicateOptionsDialog(
    BuildContext context,
    DuplicateMatch duplicate,
  ) async {
    if (!context.mounted) return null;

    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Similar ${NamingUtils.tasksName(capitalize: true, plural: false)} Found',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'There\'s a similar task already on file. Do you really want to create a new one, just edit the old one, or stand pat?',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    duplicate.task.headline,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'in ${duplicate.category.headline}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('done'),
            child: const Text('All Done'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('new'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.green[700],
            ),
            child: const Text('Make New'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop('edit'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
            ),
            child: const Text('Edit Old'),
          ),
        ],
      ),
    );
  }

  /// Navigate to edit existing task and add new work to it
  static Future<void> _navigateToAddWorkToExistingTask(
    BuildContext context,
    Task existingTask,
    Category category,
    String workTitle,
    String url,
    String linkTitle,
  ) async {
    if (!context.mounted) return;

    try {
      print(
          'IncomingLinkProcessor: Adding work "$workTitle" to existing task "${existingTask.headline}"');

      // Prepare the new notes: append work title to existing notes
      final existingNotes = existingTask.notes ?? '';
      final newNotes = existingNotes.isEmpty
          ? workTitle
          : '$existingNotes\n$workTitle';

      // Prepare the new link to add to links array
      final newLink = '<a href="$url">$linkTitle</a>';

      // Navigate to TaskEditScreen with pre-filled data
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TaskEditScreen(
            category: category,
            task: existingTask,
            initialNotes: newNotes,
            initialLinks: [
              ...existingTask.links ?? [],
              newLink,
            ],
          ),
        ),
      );
    } catch (e) {
      print(
          'IncomingLinkProcessor: Error navigating to add work to existing task: $e');
    }
  }

  /// Navigate to TaskEditScreen with artist/work pre-filled for new task
  static Future<void> _navigateToTaskEditScreenWithArtistWork(
    BuildContext context,
    LinkProcessingResult result,
    Category? defaultCategory,
    ArtistWorkInfo artistWorkInfo,
  ) async {
    if (!context.mounted) return;

    try {
      // If we have a default category, use it; otherwise show category picker
      Category? category = defaultCategory;

      if (category == null) {
        // Show category picker first - suggest streaming media categories
        await CategoryPickerDialog.show(
          context,
          title:
              'Select ${NamingUtils.categoriesName(capitalize: true, plural: false)} for New ${NamingUtils.tasksName(capitalize: true, plural: false)}',
          onCategorySelected: (Category selectedCategory,
              {bool? shouldMove}) async {
            await Future.delayed(const Duration(milliseconds: 100));
            await _openTaskEditScreenWithArtistWork(
                context, result, selectedCategory, artistWorkInfo);
          },
        );
        return;
      }

      await _openTaskEditScreenWithArtistWork(
          context, result, category, artistWorkInfo);
    } catch (e) {
      print(
          'IncomingLinkProcessor: Error navigating to task edit screen with artist/work: $e');
    }
  }

  /// Open TaskEditScreen with artist as headline and work in notes
  static Future<void> _openTaskEditScreenWithArtistWork(
    BuildContext context,
    LinkProcessingResult result,
    Category category,
    ArtistWorkInfo artistWorkInfo,
  ) async {
    try {
      print(
          'IncomingLinkProcessor: Opening TaskEditScreen with artist: ${artistWorkInfo.artist}, work: ${artistWorkInfo.work}');

      // Create HTML link from the result
      final htmlLink = '<a href="${result.url}">${result.title}</a>';

      // Navigate to TaskEditScreen with artist as headline and work as notes
      final taskSaved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => TaskEditScreen(
            category: category,
            initialLinks: [htmlLink],
            initialHeadline: artistWorkInfo.artist, // Artist as headline
            initialNotes: artistWorkInfo.work, // Work as notes
            showAlternativeOptions: false,
          ),
        ),
      );

      // Refresh cache if task was saved
      if (taskSaved == true) {
        final cacheManager = CacheManager();
        if (cacheManager.currentCategory?.id == category.id) {
          await cacheManager.refreshCurrentCategoryTasks();
        }
      }
    } catch (e) {
      print(
          'IncomingLinkProcessor: Error opening TaskEditScreen with artist/work: $e');
    }
  }

  /// Navigate to TaskEditScreen with the processed link data
  static Future<void> _navigateToTaskEditScreen(
    BuildContext context,
    LinkProcessingResult result,
    Category? defaultCategory,
  ) async {
    if (!context.mounted) return;

    try {
      // If we have a default category, use it; otherwise show category picker
      Category? category = defaultCategory;

      if (category == null) {
        // Show category picker first
        await CategoryPickerDialog.show(
          context,
          title:
              'Select ${NamingUtils.categoriesName(capitalize: true, plural: false)} for New ${NamingUtils.tasksName(capitalize: true, plural: false)}',
          onCategorySelected: (Category selectedCategory,
              {bool? shouldMove}) async {
            await Future.delayed(const Duration(milliseconds: 100));
            await _openTaskEditScreen(context, result, selectedCategory);
          },
        );
        return;
      }

      await _openTaskEditScreen(context, result, category);
    } catch (e) {
      print('IncomingLinkProcessor: Error navigating to task edit screen: $e');
    }
  }

  /// Open the TaskEditScreen with the specified category and result data
  static Future<void> _openTaskEditScreen(
    BuildContext context,
    LinkProcessingResult result,
    Category category,
  ) async {
    try {
      print(
          'IncomingLinkProcessor: Opening TaskEditScreen with category: ${category.headline}');
      print('IncomingLinkProcessor: URL: ${result.url}');
      print('IncomingLinkProcessor: Title: ${result.title}');

      // Create HTML link from the result
      final htmlLink = result.hasValidMetadata && result.title != null
          ? '<a href="${result.url}">${result.title}</a>'
          : '<a href="${result.url}">${result.url}</a>';

      // Note: Synopsis will be auto-fetched by SynopsisFetcher when the task is viewed
      // We don't pre-populate it here to keep the initial task creation simple

      // Navigate to TaskEditScreen with initial data and await the result
      final taskSaved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => TaskEditScreen(
            category: category,
            initialLinks: [htmlLink],
            initialHeadline: result.title,
            initialNotes: null, // Notes are user-entered, not auto-filled
            showAlternativeOptions:
                false, // Hide bulk import options for single task
          ),
        ),
      );

      // If task was saved successfully, refresh the cache for the current category
      // This ensures that if we're on the HomeScreen showing this category,
      // it will display the newly added task
      if (taskSaved == true) {
        print(
            'IncomingLinkProcessor: Task saved successfully, checking if HomeScreen needs refresh...');
        final cacheManager = CacheManager();

        // Check if the saved task's category matches the current category on HomeScreen
        if (cacheManager.currentCategory?.id == category.id) {
          print(
              'IncomingLinkProcessor: Saved task is in current category (${category.headline}), refreshing HomeScreen...');
          await cacheManager.refreshCurrentCategoryTasks();
          print('IncomingLinkProcessor: HomeScreen cache refreshed');
        } else {
          print(
              'IncomingLinkProcessor: Saved task category (${category.headline}) does not match current category (${cacheManager.currentCategory?.headline}), no refresh needed');
        }
      } else {
        print(
            'IncomingLinkProcessor: Task not saved (user cancelled or error occurred)');
      }
    } catch (e) {
      print('IncomingLinkProcessor: Error opening TaskEditScreen: $e');
    }
  }

  /// Show dialog when duplicates are found
  /// Show dialog for new (non-duplicate) links
  static Future<void> _showNewLinkDialog(
    BuildContext context,
    LinkProcessingResult result, {
    Category? defaultCategory,
    bool ignoreWarnings = false,
  }) async {
    // Check if context is still mounted
    if (!context.mounted) {
      print(
          'IncomingLinkProcessor: Context no longer mounted, cannot show new link dialog');
      return;
    }

    final title = result.title ?? 'Untitled Link';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (result.hasValidMetadata) ...[
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                result.url,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ] else ...[
              Text('Link: ${result.url}'),
              if (!ignoreWarnings) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Could not extract title from this link',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 16),
            const Text('What would you like to do?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _showTaskSelectionDialog(context, result);
            },
            child: const Text('Add to Existing Task'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _showCategorySelectionDialog(context, result,
                  defaultCategory: defaultCategory);
            },
            child: const Text('Create New Task'),
          ),
        ],
      ),
    );
  }

  /// Show category selection dialog for new task creation
  static Future<void> _showCategorySelectionDialog(
    BuildContext context,
    LinkProcessingResult result, {
    Category? defaultCategory,
  }) async {
    print('IncomingLinkProcessor: Showing category selection dialog');

    // Check if context is still mounted
    if (!context.mounted) {
      print(
          'IncomingLinkProcessor: Context no longer mounted, cannot show category dialog');
      return;
    }

    // Store the context at the root level to avoid context becoming unmounted
    final rootContext = context;

    await CategoryPickerDialog.show(
      context,
      title:
          'Select ${NamingUtils.categoriesName(capitalize: true, plural: false)} for New ${NamingUtils.tasksName(capitalize: true, plural: false)}',
      defaultCategory: defaultCategory,
      onCategorySelected: (Category category, {bool? shouldMove}) async {
        // Use the stored root context instead of the dialog context
        // Add a small delay to ensure the dialog is fully dismissed
        await Future.delayed(const Duration(milliseconds: 100));

        // Try to create the task using a different approach
        await _createTaskDirectly(result, category);
      },
    );
  }

  /// Create a new task directly without relying on context
  static Future<void> _createTaskDirectly(
    LinkProcessingResult result,
    Category category,
  ) async {
    print(
        'IncomingLinkProcessor: Creating task directly for category: ${category.headline}');
    print('IncomingLinkProcessor: URL: ${result.url}');
    print('IncomingLinkProcessor: Title: ${result.title}');

    try {
      // Validate that we have a URL
      if (result.url.isEmpty) {
        throw ArgumentError('Cannot create task with empty URL');
      }

      // Create HTML link with proper title
      final htmlLink = result.hasValidMetadata && result.title != null
          ? '<a href="${result.url}">${result.title}</a>'
          : '<a href="${result.url}">${result.url}</a>';

      print('IncomingLinkProcessor: Created HTML link: $htmlLink');

      // Find the original_id by checking if any other task has this same link
      print('IncomingLinkProcessor: Looking for original_id...');
      final originalId = await findOriginalIdForLink(result.url);

      // Format description for synopsis if available
      String? synopsis;
      if (result.description != null && result.description!.isNotEmpty) {
        if (result.description!.length > 200) {
          synopsis =
              '${result.description!.substring(0, 200)}... <a href="${result.url}">(more)</a>';
        } else {
          synopsis =
              '${result.description!} <a href="${result.url}">(reference)</a>';
        }
      }

      // Create the task data
      final taskData = {
        'category_id': category.id,
        'headline': result.title ?? 'New Task',
        'links': [
          htmlLink
        ], // Ensure this is always an array with at least one element
        'notes': null, // User-entered notes (none yet)
        'synopsis': synopsis, // Auto-fetched description
        'original_id': originalId, // Link to original task if it exists
        'owner_id': AuthUtils.getCurrentUserId(),
        'suggestible_at': null,
        'triggers_at': null,
        'deferral': 0,
        'finished': false,
        'shared': true,
      };

      print(
          'IncomingLinkProcessor: Task data prepared: ${taskData['headline']}');
      print(
          'IncomingLinkProcessor: Links array length: ${(taskData['links'] as List).length}');
      print('IncomingLinkProcessor: original_id: $originalId');

      // Save to database
      final response = await supabase.from('Tasks').insert(taskData).select();

      if (response.isNotEmpty) {
        print('IncomingLinkProcessor: Task created successfully');

        // Notify cache manager to refresh
        await CacheManager().refreshCurrentCategoryTasks();

        // Show success message (we'll need to get context from somewhere)
        print('IncomingLinkProcessor: Task created - ${result.title}');
      } else {
        print('IncomingLinkProcessor: Failed to create task - no response');
      }
    } catch (e) {
      print('IncomingLinkProcessor: Error creating task directly: $e');
    }
  }

  /// Create a new task in the specified category with the link
  static Future<void> _createTaskInCategory(
    BuildContext context,
    LinkProcessingResult result,
    Category category,
  ) async {
    print(
        'IncomingLinkProcessor: Creating new task in category: ${category.headline}');

    // Check if context is still mounted
    if (!context.mounted) {
      print(
          'IncomingLinkProcessor: Context no longer mounted, trying alternative approach');

      // Try to use a different approach - get context from the app's navigator
      try {
        // Import the main app's navigator key if available
        // For now, just return with an error message
        print('IncomingLinkProcessor: Cannot create task - context unmounted');
        return;
      } catch (e) {
        print('IncomingLinkProcessor: Error in context recovery: $e');
        return;
      }
    }

    // Create HTML link with proper title
    // Navigate to TaskEditScreen to create new task
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TaskEditScreen(
          category: category,
        ),
      ),
    );
  }

  /// Show the existing task with action options
  static Future<void> _navigateToExistingTask(
    BuildContext context,
    DuplicateMatch duplicate,
  ) async {
    print(
        'IncomingLinkProcessor: Showing existing task dialog: ${duplicate.task.headline}');

    // Check if context is still mounted
    if (!context.mounted) {
      print(
          'IncomingLinkProcessor: Context no longer mounted, cannot show task dialog');
      return;
    }

    await _showExistingTaskDialog(context, duplicate);
  }

  /// Show dialog with existing task details and action options
  static Future<void> _showExistingTaskDialog(
    BuildContext context,
    DuplicateMatch duplicate,
  ) async {
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Task Already Exists'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This link already exists in your tasks:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            // Task display similar to Home Screen
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Task headline
                  Text(
                    duplicate.task.headline,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: duplicate.task.finished
                              ? Colors.grey
                              : Colors.black,
                        ),
                  ),
                  const SizedBox(height: 8),

                  // Task status
                  Row(
                    children: [
                      Icon(
                        duplicate.task.finished
                            ? Icons.check_circle
                            : Icons.schedule,
                        size: 16,
                        color: duplicate.task.finished
                            ? Colors.grey
                            : Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        duplicate.task.finished ? 'Finished' : 'Available',
                        style: TextStyle(
                          fontSize: 12,
                          color: duplicate.task.finished
                              ? Colors.grey
                              : Colors.orange,
                        ),
                      ),
                      if (duplicate.task.suggestibleAt != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '• Suggestible ${_formatSuggestibleTime(duplicate.task.suggestibleAt!)}',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),

                  // Category info
                  const SizedBox(height: 4),
                  Text(
                    'Category: ${duplicate.category.headline}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),

                  // Link preview
                  if (duplicate.originalLinkText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Link: ${duplicate.originalLinkText}',
                      style: const TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (duplicate.task.finished) ...[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _reviveTask(context, duplicate.task);
              },
              child: const Text('Revive Task'),
            ),
          ],
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _editExistingTask(context, duplicate.task);
            },
            child: const Text('Edit Task'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _createNewTaskAnyway(context, duplicate);
            },
            child: const Text('Create New'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Keep As Is'),
          ),
        ],
      ),
    );
  }

  /// Format suggestible time for display
  static String _formatSuggestibleTime(DateTime date) {
    final now = DateTime.now();
    final difference = date.difference(now);

    if (difference.isNegative) {
      return 'now';
    } else if (difference.inDays > 0) {
      return 'in ${difference.inDays} day${difference.inDays == 1 ? '' : 's'}';
    } else if (difference.inHours > 0) {
      return 'in ${difference.inHours} hour${difference.inHours == 1 ? '' : 's'}';
    } else {
      return 'in ${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'}';
    }
  }

  /// Revive a finished task (set finished to false and reset suggestible_at)
  static Future<void> _reviveTask(BuildContext context, Task task) async {
    try {
      print('IncomingLinkProcessor: Reviving task: ${task.headline}');

      // Update task to make it available again
      final updatedTaskData = {
        'finished': false,
        'suggestible_at': null,
      };

      await supabase.from('Tasks').update(updatedTaskData).eq('id', task.id);

      // Refresh cache
      await CacheManager().refreshCurrentCategoryTasks();

      print('IncomingLinkProcessor: Task revived successfully');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task revived and made available'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('IncomingLinkProcessor: Error reviving task: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reviving task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Navigate to edit the existing task
  static Future<void> _editExistingTask(BuildContext context, Task task) async {
    try {
      print('IncomingLinkProcessor: Editing existing task: ${task.headline}');

      // We need to fetch the category for the task
      final categoryResponse = await supabase
          .from('Categories')
          .select()
          .eq('id', task.categoryId)
          .single();

      final category = Category.fromJson(categoryResponse);

      // Navigate to TaskEditScreen with the existing task
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TaskEditScreen(
            category: category,
            task: task,
          ),
        ),
      );
    } catch (e) {
      print('IncomingLinkProcessor: Error navigating to edit task: $e');
    }
  }

  /// Create a new task anyway despite the duplicate
  static Future<void> _createNewTaskAnyway(
      BuildContext context, DuplicateMatch duplicate) async {
    try {
      print('IncomingLinkProcessor: Creating new task despite duplicate');

      // Navigate to TaskEditScreen to create a new task
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TaskEditScreen(
            category: duplicate.category,
          ),
        ),
      );
    } catch (e) {
      print('IncomingLinkProcessor: Error creating new task: $e');
    }
  }

  /// Show task selection dialog for adding to existing task
  static Future<void> _showTaskSelectionDialog(
    BuildContext context,
    LinkProcessingResult result,
  ) async {
    // TODO: Implement task selection dialog
    print('IncomingLinkProcessor: TODO - Show task selection dialog');
  }

  /// Normalize URL for comparison (remove tracking parameters, etc.)
  static String? _normalizeUrl(String url) {
    try {
      // Handle plain URLs and extract from HTML links
      String cleanUrl = url.trim();

      // Extract URL from HTML link if provided
      final htmlMatch =
          RegExp(r'<a[^>]+href="([^"]*)"[^>]*>').firstMatch(cleanUrl);
      if (htmlMatch != null) {
        cleanUrl = htmlMatch.group(1)!;
      }

      // Parse and normalize
      final uri = Uri.parse(cleanUrl);

      // Remove common tracking parameters
      final cleanParams = Map<String, String>.from(uri.queryParameters);
      final trackingParams = {
        'utm_source',
        'utm_medium',
        'utm_campaign',
        'utm_term',
        'utm_content',
        'fbclid',
        'gclid',
        'ref',
        'source',
        '_campaign'
      };

      for (final param in trackingParams) {
        cleanParams.remove(param);
      }

      // Rebuild URL without tracking parameters
      final cleanUri = uri.replace(
          queryParameters: cleanParams.isEmpty ? null : cleanParams);
      return cleanUri.toString();
    } catch (e) {
      print('IncomingLinkProcessor: Error normalizing URL "$url": $e');
      return null;
    }
  }

  /// Extract URL from HTML link string
  static String? _extractUrlFromHtmlLink(String htmlLink) {
    final match = RegExp(r'<a[^>]+href="([^"]*)"').firstMatch(htmlLink);
    return match?.group(1);
  }

  /// Compare two URLs for matching (handles normalization)
  static bool _urlsMatch(String url1, String url2) {
    final normalized1 = _normalizeUrl(url1);
    final normalized2 = _normalizeUrl(url2);

    if (normalized1 == null || normalized2 == null) {
      return false;
    }

    return normalized1 == normalized2;
  }

  /// Get the currently active category from cache/context
  static Category? getCurrentCategory() {
    // TODO: Implement cache-aware category detection
    return null;
  }

  /// Search for a task by artist name in streaming media categories
  /// Returns exactly one task if found, otherwise null
  static Future<Task?> findTaskByArtistInStreamingCategories(
    String artist,
    String userId,
  ) async {
    try {
      print(
          'IncomingLinkProcessor: Searching for artist "$artist" in streaming media categories');

      // Get all user's categories to filter for streaming media ones
      final categoriesResponse = await supabase
          .from('Categories')
          .select()
          .eq('owner_id', userId);

      final categoriesData = categoriesResponse as List<dynamic>;

      // Filter to only streaming media category IDs
      final streamingCategoryIds = categoriesData
          .where((catData) {
            final originalId = catData['original_id'] as int?;
            return originalId != null &&
                STREAMING_MEDIA_CATEGORY_IDS.contains(originalId);
          })
          .map((catData) => catData['id'] as int)
          .toList();

      if (streamingCategoryIds.isEmpty) {
        print(
            'IncomingLinkProcessor: User has no streaming media categories');
        return null;
      }

      print(
          'IncomingLinkProcessor: Searching in category IDs: $streamingCategoryIds');

      // Search for tasks with matching artist name (case-insensitive)
      final tasksResponse = await supabase
          .from('Tasks')
          .select()
          .eq('owner_id', userId)
          .inFilter('category_id', streamingCategoryIds)
          .ilike('headline', artist); // Exact match, case-insensitive

      final tasksData = tasksResponse as List<dynamic>;

      print(
          'IncomingLinkProcessor: Found ${tasksData.length} tasks matching artist "$artist"');

      // Return exactly one match, or null if not exactly one
      if (tasksData.length == 1) {
        final task = Task.fromJson(tasksData[0]);
        print(
            'IncomingLinkProcessor: Found exactly one matching task: "${task.headline}"');
        return task;
      } else if (tasksData.length > 1) {
        print(
            'IncomingLinkProcessor: Found multiple tasks (${tasksData.length}), not showing match dialog');
        return null;
      } else {
        print('IncomingLinkProcessor: No tasks found for this artist');
        return null;
      }
    } catch (e) {
      print('IncomingLinkProcessor: Error searching for artist: $e');
      return null;
    }
  }

  /// Show dialog asking if user wants to add to existing artist task or create new
  static Future<String?> _showArtistMatchDialog(
    BuildContext context,
    Task existingTask,
    Category category,
    String workTitle,
  ) async {
    if (!context.mounted) return null;

    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Found Existing Artist',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You already have a ${NamingUtils.tasksName(capitalize: false, plural: false)} for this artist:',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existingTask.headline,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'in ${category.headline}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (existingTask.notes != null &&
                      existingTask.notes!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      existingTask.notes!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Would you like to add "$workTitle" to this ${NamingUtils.tasksName(capitalize: false, plural: false)}?',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('new'),
            child: const Text('Create New'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop('add'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
            ),
            child: const Text('Add to Existing'),
          ),
        ],
      ),
    );
  }
}
