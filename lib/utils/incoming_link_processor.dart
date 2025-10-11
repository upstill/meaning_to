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

  /// Find all duplicate links across ALL user tasks
  static Future<List<DuplicateMatch>> findAllDuplicates(String url) async {
    final duplicates = <DuplicateMatch>[];

    try {
      final userId = AuthUtils.getCurrentUserId();
      if (userId == null) {
        print(
            'IncomingLinkProcessor: No user ID available for duplicate check');
        return duplicates;
      }

      print(
          'IncomingLinkProcessor: Checking for duplicates across all user tasks');

      // Extract the domain from the URL for efficient database filtering
      final uri = Uri.tryParse(url);
      if (uri == null) {
        print('IncomingLinkProcessor: Could not parse URL: $url');
        return [];
      }

      final domain = uri.host;

      // Fetch all tasks for the user to check for duplicates
      // Note: This is less efficient but more reliable than complex JSON queries
      final response = await supabase
          .from('Tasks')
          .select('*, Categories!Tasks_category_id_fkey(*)')
          .eq('owner_id', userId);

      final tasksData = response as List<dynamic>;
      print(
          'IncomingLinkProcessor: Found ${tasksData.length} tasks with potentially matching links');

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
              print(
                  'IncomingLinkProcessor: Found duplicate in task "${task.headline}" in category "${category.headline}"');
              duplicates.add(DuplicateMatch(
                task: task,
                category: category,
                matchingUrl: linkUrl,
                originalLinkText: linkText,
              ));
            }
          }
        } catch (e) {
          print('IncomingLinkProcessor: Error processing task data: $e');
          continue;
        }
      }
    } catch (e) {
      print('IncomingLinkProcessor: Error during duplicate check: $e');
    }

    return duplicates;
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

    // Check for duplicates and navigate accordingly
    if (result.duplicates.isNotEmpty) {
      // Link exists - go to Edit Task
      await _navigateToEditExistingTask(context, result.duplicates.first);
    } else {
      // Link is new - go to New Task
      await _navigateToTaskEditScreen(context, result, defaultCategory);
    }
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

      // Show informative popup first
      final shouldEdit = await _showDuplicateInfoDialog(context, duplicate);

      if (!context.mounted) return;

      // If user chose not to edit, just return without navigating
      if (shouldEdit != true) {
        return;
      }

      // We need to fetch the category for the task
      final categoryResponse = await supabase
          .from('Categories')
          .select()
          .eq('id', duplicate.task.categoryId)
          .single();

      final category = Category.fromJson(categoryResponse);

      // Navigate to TaskEditScreen with the existing task
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TaskEditScreen(
            category: category,
            task: duplicate.task,
          ),
        ),
      );
    } catch (e) {
      print(
          'IncomingLinkProcessor: Error navigating to edit existing task: $e');
    }
  }

  /// Show informative dialog about duplicate task
  static Future<bool?> _showDuplicateInfoDialog(
    BuildContext context,
    DuplicateMatch duplicate,
  ) async {
    if (!context.mounted) return false;

    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            '${NamingUtils.tasksName(capitalize: true, plural: false)} Already Exists'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${duplicate.task.headline}" is already ${NamingUtils.tasksName(capitalize: false, plural: false, withArticle: true)} for when you want to ${duplicate.category.headline}. You can leave it as is, or edit it to suit--including moving it to another ${NamingUtils.categoriesName(capitalize: false, plural: false)}.',
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.check),
            tooltip: 'That\'s Fine',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.edit),
            tooltip: 'Edit',
          ),
        ],
      ),
    );
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
          title: 'Select Category for New Task',
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

      // Create HTML link from the result
      final htmlLink = result.hasValidMetadata
          ? '<a href="${result.url}">${result.title}</a>'
          : '<a href="${result.url}">${result.url}</a>';

      // Format description with truncation and (more) link if needed
      String? formattedNotes;
      if (result.description != null && result.description!.isNotEmpty) {
        if (result.description!.length > 200) {
          formattedNotes =
              '${result.description!.substring(0, 200)}... <a href="${result.url}">(more)</a>';
        } else {
          formattedNotes = result.description;
        }
      }

      // Navigate to TaskEditScreen with initial data
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TaskEditScreen(
            category: category,
            initialLinks: [htmlLink],
            initialHeadline: result.title,
            initialNotes: formattedNotes,
            showAlternativeOptions:
                false, // Hide bulk import options for single task
          ),
        ),
      );
    } catch (e) {
      print('IncomingLinkProcessor: Error opening TaskEditScreen: $e');
    }
  }

  /// Show dialog when duplicates are found
  static Future<void> _showDuplicateFoundDialog(
    BuildContext context,
    LinkProcessingResult result,
  ) async {
    // Check if context is still mounted
    if (!context.mounted) {
      print(
          'IncomingLinkProcessor: Context no longer mounted, cannot show duplicate dialog');
      return;
    }

    final duplicate = result.duplicates.first; // Show first duplicate

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Link Already Exists'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This link already exists in:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Task: ${duplicate.task.headline}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('Category: ${duplicate.category.headline}'),
                ],
              ),
            ),
            if (result.duplicates.length > 1) ...[
              const SizedBox(height: 8),
              Text('...and ${result.duplicates.length - 1} other location(s)'),
            ],
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
              _navigateToExistingTask(context, duplicate);
            },
            child: const Text('View Task'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _showNewLinkDialog(context, result, ignoreWarnings: true);
            },
            child: const Text('Add Anyway'),
          ),
        ],
      ),
    );
  }

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
      title: 'Select Category for New Task',
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

    try {
      // Create HTML link with proper title
      final htmlLink = result.hasValidMetadata
          ? '<a href="${result.url}">${result.title}</a>'
          : '<a href="${result.url}">${result.url}</a>';

      // Create the task data
      final taskData = {
        'category_id': category.id,
        'headline': result.title ?? 'New Task',
        'links': [htmlLink],
        'notes': null,
        'owner_id': AuthUtils.getCurrentUserId(),
        'suggestible_at': null,
        'triggers_at': null,
        'deferral': 0,
        'finished': false,
        'shared': true,
      };

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
                color: Theme.of(context).colorScheme.surfaceVariant,
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
}
