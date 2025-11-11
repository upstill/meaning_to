import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:share_handler/share_handler.dart';
import 'dart:async';
import 'package:meaning_to/utils/incoming_link_processor.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/main.dart';
import 'package:meaning_to/utils/streaming_media_constants.dart';

/// Comprehensive intent handler for all incoming content and deep links
/// Handles: Deep links, Share intents, OAuth callbacks, Manual links, Browser redirects
class IntentHandler {
  static final IntentHandler _instance = IntentHandler._internal();
  factory IntentHandler() => _instance;
  IntentHandler._internal();

  // Core components
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<SharedMedia?>? _shareSubscription;

  // State management
  GlobalKey<NavigatorState>? _navigatorKey;
  GlobalKey<ScaffoldMessengerState>? _scaffoldKey;

  // Pending content handling
  Uri? _pendingDeepLink;
  String? _pendingSharedContent;
  bool _isInitialized = false;

  // Configuration
  bool _logIntents = true;
  Duration _stateRestorationTimeout = const Duration(seconds: 10);

  /// Initialize the intent handler with required keys and callbacks
  Future<void> initialize({
    required GlobalKey<NavigatorState> navigatorKey,
    required GlobalKey<ScaffoldMessengerState> scaffoldKey,
    bool logIntents = true,
    Duration stateRestorationTimeout = const Duration(seconds: 10),
  }) async {
    if (_isInitialized) {
      print('IntentHandler: Already initialized, skipping...');
      return;
    }

    _navigatorKey = navigatorKey;
    _scaffoldKey = scaffoldKey;
    _logIntents = logIntents;
    _stateRestorationTimeout = stateRestorationTimeout;

    print('IntentHandler: Initializing...');

    await _initializeDeepLinks();
    await _initializeShareIntents();

    _isInitialized = true;
    print('IntentHandler: Initialization complete');
  }

  /// Initialize deep link handling
  Future<void> _initializeDeepLinks() async {
    print('IntentHandler: Setting up deep link handlers...');

    _appLinks = AppLinks();

    // Handle initial deep link (app launched via link)
    try {
      final initialUri = await _appLinks.getInitialAppLink();
      if (initialUri != null) {
        print('IntentHandler: Initial deep link detected: $initialUri');
        _pendingDeepLink = initialUri;

        // Handle immediately for certain types, defer others
        if (_shouldHandleImmediately(initialUri)) {
          await _handleDeepLink(initialUri, isInitial: true);
        }
      }
    } catch (e) {
      print('IntentHandler: Error getting initial deep link: $e');
    }

    // Handle subsequent deep links
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) async {
        print('IntentHandler: Deep link received: $uri');
        await _handleDeepLink(uri, isInitial: false);
      },
      onError: (error) {
        print('IntentHandler: Deep link error: $error');
        _logIntent(IntentType.deepLinkError, {'error': error.toString()});
      },
    );
  }

  /// Initialize share intent handling
  Future<void> _initializeShareIntents() async {
    print('IntentHandler: Setting up share intent handlers...');

    // Handle initial shared content (app launched via share)
    try {
      final initialMedia =
          await ShareHandlerPlatform.instance.getInitialSharedMedia();
      if (initialMedia?.content != null) {
        print('IntentHandler: Initial shared content detected');
        _pendingSharedContent = initialMedia!.content;
        await _handleShareIntent(initialMedia, isInitial: true);
      }
    } catch (e) {
      print('IntentHandler: Error getting initial shared media: $e');
    }

    // Handle subsequent share intents
    _shareSubscription = ShareHandlerPlatform.instance.sharedMediaStream.listen(
      (media) async {
        if (media?.content != null) {
          print('IntentHandler: Share intent received');
          await _handleShareIntent(media!, isInitial: false);
        }
      },
      onError: (error) {
        print('IntentHandler: Share intent error: $error');
        _logIntent(IntentType.shareError, {'error': error.toString()});
      },
    );
  }

  /// Handle deep link routing and processing
  Future<void> _handleDeepLink(Uri uri, {required bool isInitial}) async {
    _logIntent(IntentType.deepLink, {
      'uri': uri.toString(),
      'scheme': uri.scheme,
      'host': uri.host,
      'path': uri.path,
      'query': uri.queryParameters,
      'isInitial': isInitial,
    });

    final intent = _parseDeepLink(uri);
    await _processIntent(intent);
  }

  /// Handle share intent processing
  Future<void> _handleShareIntent(SharedMedia media,
      {required bool isInitial}) async {
    _logIntent(IntentType.shareIntent, {
      'content': media.content,
      'serviceName': media.serviceName,
      'attachments': media.attachments?.length ?? 0,
      'isInitial': isInitial,
    });

    final intent = _parseShareIntent(media);
    await _processIntent(intent);
  }

  /// Process manual link entry from user
  Future<void> handleManualLink(String link, {BuildContext? context}) async {
    _logIntent(IntentType.manualLink, {'link': link});

    final intent = ProcessedIntent(
      type: IntentType.manualLink,
      action: IntentAction.processLink,
      data: {'url': link},
      priority: IntentPriority.user,
    );

    await _processIntent(intent, context: context);
  }

  /// Process OAuth callback
  Future<void> handleOAuthCallback(Uri uri) async {
    _logIntent(IntentType.oauthCallback, {
      'uri': uri.toString(),
      'fragment': uri.fragment,
      'query': uri.queryParameters,
    });

    final intent = ProcessedIntent(
      type: IntentType.oauthCallback,
      action: IntentAction.authenticate,
      data: {
        'uri': uri.toString(),
        'fragment': uri.fragment,
        'queryParameters': uri.queryParameters,
      },
      priority: IntentPriority.system,
    );

    await _processIntent(intent);
  }

  /// Central intent processing with proper routing and context awareness
  Future<void> _processIntent(ProcessedIntent intent,
      {BuildContext? context}) async {
    print(
        'IntentHandler: Processing intent - Type: ${intent.type}, Action: ${intent.action}');

    // Get or wait for context
    final processingContext = context ?? await _getContext();
    if (processingContext == null && intent.priority != IntentPriority.system) {
      print('IntentHandler: No context available, deferring intent processing');
      await _deferIntentProcessing(intent);
      return;
    }

    // Wait for state restoration if needed
    if (intent.priority == IntentPriority.user) {
      await _waitForStateRestoration();
    }

    // Route intent to appropriate handler
    switch (intent.action) {
      case IntentAction.processLink:
        await _processLinkIntent(intent, processingContext);
        break;

      case IntentAction.navigateToCategory:
        await _navigateToCategoryIntent(intent, processingContext);
        break;

      case IntentAction.authenticate:
        await _processAuthIntent(intent, processingContext);
        break;

      case IntentAction.showTaskEditor:
        await _showTaskEditorIntent(intent, processingContext);
        break;

      case IntentAction.unknown:
        print('IntentHandler: Unknown intent action, ignoring');
        break;
    }
  }

  /// Process link-related intents (URLs, shared content with links)
  Future<void> _processLinkIntent(
      ProcessedIntent intent, BuildContext? context) async {
    final url = intent.data['url'] as String?;
    if (url == null || context == null) return;

    print('IntentHandler: Processing link intent for URL: $url');

    // Analyze URL and determine suggested categories
    final suggestedCategoryIds = _analyzeLinkForCategorySuggestions(url);
    if (suggestedCategoryIds.isNotEmpty) {
      print('IntentHandler: URL suggests category IDs: $suggestedCategoryIds');
      intent.data['suggestedCategoryIds'] = suggestedCategoryIds;
    }

    // First, check for existing tasks with this link
    await _checkForDuplicateLinkAndHandle(url, intent, context);
  }

  /// Check for duplicate links and handle based on ownership
  Future<void> _checkForDuplicateLinkAndHandle(
      String url, ProcessedIntent intent, BuildContext context) async {
    try {
      print('IntentHandler: Checking for duplicate links...');

      // Use IncomingLinkProcessor to find duplicates
      final result = await IncomingLinkProcessor.processIncomingLink(url);

      if (result.duplicates.isEmpty) {
        print(
            'IntentHandler: No duplicate links found, proceeding with new task creation');
        await _handleNewLinkCreation(url, intent, context);
        return;
      }

      print('IntentHandler: Found ${result.duplicates.length} duplicate(s)');

      // Get current user ID for ownership comparison
      final currentUserId = AuthUtils.getCurrentUserId();
      if (currentUserId == null) {
        print('IntentHandler: No current user, cannot process link');
        return;
      }

      // Separate duplicates by ownership
      final ownedDuplicates = result.duplicates
          .where((dup) => dup.task.ownerId == currentUserId)
          .toList();

      final otherUserDuplicates = result.duplicates
          .where((dup) => dup.task.ownerId != currentUserId)
          .toList();

      // Handle user-owned duplicates first (higher priority)
      if (ownedDuplicates.isNotEmpty) {
        print(
            'IntentHandler: Found ${ownedDuplicates.length} user-owned duplicate(s)');
        await _handleUserOwnedDuplicate(
            ownedDuplicates.first, url, intent, context);
      } else if (otherUserDuplicates.isNotEmpty) {
        print(
            'IntentHandler: Found ${otherUserDuplicates.length} other-user duplicate(s)');
        await _handleOtherUserDuplicate(
            otherUserDuplicates.first, url, intent, context);
      }
    } catch (e) {
      print('IntentHandler: Error checking for duplicates: $e');
      // Fallback to new task creation
      await _handleNewLinkCreation(url, intent, context);
    }
  }

  /// Handle duplicate link owned by current user
  Future<void> _handleUserOwnedDuplicate(DuplicateMatch duplicate, String url,
      ProcessedIntent intent, BuildContext context) async {
    print(
        'IntentHandler: Handling user-owned duplicate for task: ${duplicate.task.headline}');

    // Show dialog asking user if they want to keep existing or create new
    final action = await _showUserOwnedDuplicateDialog(context, duplicate);

    switch (action) {
      case DuplicateAction.keepExisting:
        print('IntentHandler: User chose to keep existing task');
        // Navigate to task editor for existing task
        await _navigateToTaskEditor(
            duplicate.task, duplicate.category, context);
        break;

      case DuplicateAction.createNew:
        print('IntentHandler: User chose to create new task');
        // Go to New Content screen with preloaded link and original_id
        await _navigateToNewContentWithLinkAndOriginal(url, intent, context, duplicate);
        break;

      case DuplicateAction.cancel:
        print('IntentHandler: User cancelled');
        break;
    }
  }

  /// Handle duplicate link owned by another user
  Future<void> _handleOtherUserDuplicate(DuplicateMatch duplicate, String url,
      ProcessedIntent intent, BuildContext context) async {
    print(
        'IntentHandler: Handling other-user duplicate for task: ${duplicate.task.headline}');

    // Find user's equivalent category (same original_id)
    final userCategory = await _findUserEquivalentCategory(duplicate.category);

    if (userCategory != null) {
      print(
          'IntentHandler: Found user equivalent category: ${userCategory.headline}');
      // Navigate to New Content screen with other user's task data but user's category
      await _navigateToNewContentWithTaskData(
          duplicate.task, userCategory, url, context);
    } else {
      print(
          'IntentHandler: No equivalent category found, creating new task with link and original_id');
      // Fallback to just the link but still preserve original_id relationship
      await _navigateToNewContentWithLinkAndOriginal(url, intent, context, duplicate);
    }
  }

  /// Handle new link creation (no duplicates found)
  Future<void> _handleNewLinkCreation(
      String url, ProcessedIntent intent, BuildContext context) async {
    print('IntentHandler: Creating new task for link: $url');
    await _navigateToNewContentWithLink(url, intent, context);
  }

  /// Handle new link creation when duplicates exist (set original_id)
  Future<void> _handleNewLinkWithDuplicates(
      String url, ProcessedIntent intent, BuildContext context, List<DuplicateMatch> duplicates) async {

    // Find the most appropriate original task to link to
    final originalTask = _findBestOriginalTask(duplicates);

    print('IntentHandler: Creating new task for link with original_id: ${originalTask.task.originalId ?? originalTask.task.id}');

    await _navigateToNewContentWithLinkAndOriginal(url, intent, context, originalTask);
  }

  /// Show dialog for user-owned duplicate
  Future<DuplicateAction> _showUserOwnedDuplicateDialog(
      BuildContext context, DuplicateMatch duplicate) async {
    return await showDialog<DuplicateAction>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
                '${NamingUtils.tasksName(capitalize: true, plural: false)} Already Exists'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You already have ${NamingUtils.tasksName(capitalize: false, plural: false, withArticle: true)} with this link:',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        duplicate.task.headline,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'In: ${duplicate.category.headline}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      if (duplicate.task.finished)
                        Text(
                          'Status: Finished',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('What would you like to do?'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(DuplicateAction.cancel),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(DuplicateAction.keepExisting),
                child: Text(
                    duplicate.task.finished ? 'View/Edit' : 'Keep Existing'),
              ),
              ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).pop(DuplicateAction.createNew),
                child: const Text('Create New Anyway'),
              ),
            ],
          ),
        ) ??
        DuplicateAction.cancel;
  }

  /// Navigate to task editor for existing task
  Future<void> _navigateToTaskEditor(
      Task task, Category category, BuildContext context) async {
    if (_navigatorKey == null) return;

    // Use the existing task edit route structure
    _navigatorKey!.currentState?.pushNamed(
      '/edit-task',
      arguments: {
        'task': task,
        'category': category,
      },
    );
  }

  /// Navigate to New Content screen with preloaded link
  Future<void> _navigateToNewContentWithLink(
      String url, ProcessedIntent intent, BuildContext context) async {
    if (_navigatorKey == null) return;

    // Try to get intelligently suggested category first
    final suggestedCategory = await _getOrCreateSuggestedCategory(intent, context);
    final defaultCategory = suggestedCategory ?? _getCurrentCategory();

    _navigatorKey!.currentState?.pushNamed(
      '/new-content',
      arguments: {
        'selectedCategory': defaultCategory,
        'initialLinks': [url],
        'initialHeadline': intent.data['title'] as String?,
        'initialNotes': intent.data['description'] as String?,
      },
    );
  }

  /// Navigate to New Content screen with other user's task data
  Future<void> _navigateToNewContentWithTaskData(Task otherTask,
      Category userCategory, String url, BuildContext context) async {
    if (_navigatorKey == null) return;

    print(
        'IntentHandler: Creating task with other user\'s data in user\'s category');

    // Determine the original_id to use (preserve the chain)
    final originalId = otherTask.originalId ?? otherTask.id;

    _navigatorKey!.currentState?.pushNamed(
      '/new-content',
      arguments: {
        'selectedCategory': userCategory,
        'categoryLocked': true,
        'initialLinks': [url],
        'initialHeadline': otherTask.headline,
        'initialNotes': otherTask.notes,
        'originalId': originalId,  // Pass the original_id to link tasks
      },
    );
  }

  /// Navigate to New Content screen with preloaded link and original_id
  Future<void> _navigateToNewContentWithLinkAndOriginal(
      String url, ProcessedIntent intent, BuildContext context, DuplicateMatch duplicate) async {
    if (_navigatorKey == null) return;

    // Try to get intelligently suggested category first
    final suggestedCategory = await _getOrCreateSuggestedCategory(intent, context);
    final defaultCategory = suggestedCategory ?? _getCurrentCategory();

    // Determine the original_id to use (preserve the chain)
    final originalId = duplicate.task.originalId ?? duplicate.task.id;

    print('IntentHandler: Creating new task with original_id: $originalId');

    _navigatorKey!.currentState?.pushNamed(
      '/new-content',
      arguments: {
        'selectedCategory': defaultCategory,
        'initialLinks': [url],
        'initialHeadline': intent.data['title'] as String?,
        'initialNotes': intent.data['description'] as String?,
        'originalId': originalId,  // Pass the original_id to link tasks
      },
    );
  }

  /// Find the best original task to link to from duplicates
  DuplicateMatch _findBestOriginalTask(List<DuplicateMatch> duplicates) {
    // Prioritize tasks that are themselves originals (no original_id)
    final originalTasks = duplicates.where((dup) => dup.task.originalId == null).toList();

    if (originalTasks.isNotEmpty) {
      // Return the first original task found
      return originalTasks.first;
    }

    // If no original tasks, return the first duplicate
    // (its original_id will be used to continue the chain)
    return duplicates.first;
  }

  /// Analyze URL to suggest appropriate categories based on domain and path
  List<String> _analyzeLinkForCategorySuggestions(String url) {
    try {
      final uri = Uri.parse(url.toLowerCase());
      final domain = uri.host;
      final path = uri.path;

      print('IntentHandler: Analyzing URL - domain: $domain, path: $path');

      // IMDb links -> can be either movies or TV shows
      if (domain.contains('imdb.com')) {
        print('IntentHandler: IMDb link detected, suggesting both movie and TV categories');
        // Check if we can determine the type from the path
        if (path.contains('/tv/') || path.contains('tvseries')) {
          print('IntentHandler: IMDb TV content detected, prioritizing TV category');
          return ['2', '1']; // TV first, then movie
        } else if (path.contains('/title/')) {
          print('IntentHandler: IMDb title detected, could be either type');
          return ['1', '2']; // Movie first, then TV (more common)
        } else {
          print('IntentHandler: IMDb general link, suggesting both options');
          return ['1', '2']; // Movie first, then TV
        }
      }

      // Letterboxd links -> primarily movies but occasionally has TV series
      if (domain.contains('letterboxd.com')) {
        print('IntentHandler: Letterboxd link detected, suggesting movie category with TV option');
        return ['1', '2']; // Movie first (primary), TV second (occasional)
      }

      // JustWatch links -> depends on path
      if (domain.contains('justwatch.com')) {
        print('IntentHandler: JustWatch link detected, analyzing path...');
        if (path.contains('/movie/')) {
          print('IntentHandler: JustWatch movie link, suggesting movie category');
          return ['1']; // Just movie
        } else if (path.contains('/tv-show/')) {
          print('IntentHandler: JustWatch TV show link, suggesting TV category');
          return ['2']; // Just TV
        } else {
          print('IntentHandler: JustWatch link without specific type, suggesting both');
          return ['1', '2']; // Both options
        }
      }

      // Tidal links -> streaming media categories
      if (domain.contains('tidal.com')) {
        print('IntentHandler: Tidal link detected, suggesting streaming media categories');
        // Return streaming media category IDs as strings
        return STREAMING_MEDIA_CATEGORY_IDS.map((id) => id.toString()).toList();
      }

      // Future streaming services can be added here:
      // Spotify, Apple Music, YouTube Music, etc.
      // if (domain.contains('spotify.com') || domain.contains('music.apple.com')) {
      //   print('IntentHandler: Streaming media link detected');
      //   return STREAMING_MEDIA_CATEGORY_IDS.map((id) => id.toString()).toList();
      // }

      print('IntentHandler: No category suggestion for domain: $domain');
      return [];

    } catch (e) {
      print('IntentHandler: Error analyzing URL for category suggestions: $e');
      return [];
    }
  }

  /// Get or create the suggested category for the user
  Future<Category?> _getOrCreateSuggestedCategory(ProcessedIntent intent, BuildContext context) async {
    final suggestedCategoryIds = intent.data['suggestedCategoryIds'] as List<String>?;
    if (suggestedCategoryIds == null || suggestedCategoryIds.isEmpty) return null;

    print('IntentHandler: Looking for suggested categories with original_ids: $suggestedCategoryIds');

    try {
      final currentUserId = AuthUtils.getCurrentUserId();
      if (currentUserId == null) return null;

      // Check if user already has any of the suggested categories
      for (final suggestedId in suggestedCategoryIds) {
        final existingResponse = await supabase
            .from('Categories')
            .select()
            .eq('owner_id', currentUserId)
            .eq('original_id', suggestedId)
            .limit(1)
            .maybeSingle();

        if (existingResponse != null) {
          final existingCategory = Category.fromJson(existingResponse);
          print('IntentHandler: Found existing user category: ${existingCategory.headline}');
          return existingCategory;
        }
      }

      // User doesn't have any of the suggested categories, offer choices
      return await _showMultipleCategoryOptions(context, suggestedCategoryIds, currentUserId);

    } catch (e) {
      print('IntentHandler: Error getting or creating suggested category: $e');
      return null;
    }
  }

  /// Show dialog with multiple category options
  Future<Category?> _showMultipleCategoryOptions(BuildContext context, List<String> suggestedIds, String userId) async {
    try {
      print('IntentHandler: Fetching category options for IDs: $suggestedIds');

      // Fetch all the suggested original categories
      final List<Category> categoryOptions = [];

      for (final id in suggestedIds) {
        final response = await supabase
            .from('Categories')
            .select()
            .eq('id', id)
            .limit(1)
            .maybeSingle();

        if (response != null) {
          categoryOptions.add(Category.fromJson(response));
        }
      }

      if (categoryOptions.isEmpty) {
        print('IntentHandler: No category options found');
        return null;
      }

      if (categoryOptions.length == 1) {
        // Only one option available, show single adoption dialog
        final shouldAdopt = await _showCategoryAdoptionDialog(context, categoryOptions.first);
        if (shouldAdopt) {
          return await _createCategoryCopy(categoryOptions.first, userId);
        }
        return null;
      }

      // Multiple options available, show selection dialog
      final selectedCategory = await _showCategorySelectionDialog(context, categoryOptions);
      if (selectedCategory != null) {
        return await _createCategoryCopy(selectedCategory, userId);
      }

      return null;

    } catch (e) {
      print('IntentHandler: Error showing multiple category options: $e');
      return null;
    }
  }

  /// Show dialog for selecting between multiple suggested categories
  Future<Category?> _showCategorySelectionDialog(BuildContext context, List<Category> options) async {
    return await showDialog<Category>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Choose ${NamingUtils.categoriesName(capitalize: true, plural: false)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This link could belong in one of these ${NamingUtils.categoriesName(plural: true, capitalize: false)}:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            ...options.map((category) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(category),
                  style: ElevatedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.all(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        category.headline,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      if (category.invitation != null && category.invitation!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          category.invitation!,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Use current category instead'),
          ),
        ],
      ),
    );
  }

  /// Show dialog asking user if they want to adopt a suggested category
  Future<bool> _showCategoryAdoptionDialog(BuildContext context, Category originalCategory) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Suggested ${NamingUtils.categoriesName(capitalize: true, plural: false)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This link looks like it belongs in:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    originalCategory.headline,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  if (originalCategory.invitation != null && originalCategory.invitation!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      originalCategory.invitation!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Would you like to adopt this ${NamingUtils.categoriesName(plural: false, capitalize: false)} for your own use?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No, use current'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Yes, adopt this ${NamingUtils.categoriesName(plural: false, capitalize: false)}'),
          ),
        ],
      ),
    ) ?? false;
  }

  /// Create a copy of a category for the current user
  Future<Category?> _createCategoryCopy(Category originalCategory, String userId) async {
    try {
      print('IntentHandler: Creating category copy for user: $userId');

      final categoryData = {
        'headline': originalCategory.headline,
        'invitation': originalCategory.invitation,
        'owner_id': userId,
        'original_id': originalCategory.id, // Link to the original
        'private': originalCategory.private,
        'tasks_are_private': originalCategory.tasksArePrivate,
      };

      final response = await supabase
          .from('Categories')
          .insert(categoryData)
          .select()
          .single();

      final newCategory = Category.fromJson(response);
      print('IntentHandler: Created category copy: ${newCategory.headline}');

      // Initialize cache with the new category
      final cacheManager = CacheManager();
      await cacheManager.initializeWithSavedCategory(newCategory, userId);

      return newCategory;

    } catch (e) {
      print('IntentHandler: Error creating category copy: $e');
      return null;
    }
  }

  /// Find user's equivalent category (same original_id)
  Future<Category?> _findUserEquivalentCategory(Category otherCategory) async {
    try {
      final currentUserId = AuthUtils.getCurrentUserId();
      if (currentUserId == null || otherCategory.originalId == null) {
        return null;
      }

      print(
          'IntentHandler: Looking for user category with original_id: ${otherCategory.originalId}');

      // Query for user's categories with the same original_id
      final response = await supabase
          .from('Categories')
          .select()
          .eq('owner_id', currentUserId)
          .eq('original_id', otherCategory.originalId!)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        final userCategory = Category.fromJson(response);
        print(
            'IntentHandler: Found equivalent category: ${userCategory.headline}');
        return userCategory;
      }

      print(
          'IntentHandler: No equivalent category found for original_id: ${otherCategory.originalId}');
      return null;
    } catch (e) {
      print('IntentHandler: Error finding equivalent category: $e');
      return null;
    }
  }

  /// Process category navigation intents
  Future<void> _navigateToCategoryIntent(
      ProcessedIntent intent, BuildContext? context) async {
    final categoryId = intent.data['categoryId'] as String?;
    if (categoryId == null || _navigatorKey == null) return;

    print('IntentHandler: Navigating to category: $categoryId');

    // Set flag to prevent route conflicts
    MyApp.isHandlingDeepLink = true;

    try {
      _navigatorKey!.currentState?.pushReplacementNamed(
        '/category',
        arguments: {'categoryId': categoryId},
      );
    } finally {
      MyApp.isHandlingDeepLink = false;
    }
  }

  /// Process authentication intents (OAuth callbacks)
  Future<void> _processAuthIntent(
      ProcessedIntent intent, BuildContext? context) async {
    final uri = intent.data['uri'] as String?;
    if (uri == null) return;

    print('IntentHandler: Processing auth callback');

    // Handle OAuth callback
    final parsedUri = Uri.parse(uri);
    if (parsedUri.fragment.contains('access_token') ||
        parsedUri.fragment.contains('error')) {
      // This is a Supabase OAuth callback
      try {
        // Let Supabase handle the OAuth callback
        print('IntentHandler: Handling Supabase OAuth callback');
        // The auth flow will be handled by Supabase automatically
      } catch (e) {
        print('IntentHandler: Error processing OAuth callback: $e');
      }
    }
  }

  /// Show task editor intent
  Future<void> _showTaskEditorIntent(
      ProcessedIntent intent, BuildContext? context) async {
    if (context == null || _navigatorKey == null) return;

    final category = _getCurrentCategory();
    if (category == null) {
      print('IntentHandler: No current category for task editor');
      return;
    }

    print('IntentHandler: Showing task editor');

    _navigatorKey!.currentState?.pushNamed(
      '/new-content',
      arguments: {
        'category': category,
        'initialLinks': intent.data['links'] as List<String>?,
        'initialHeadline': intent.data['headline'] as String?,
        'initialNotes': intent.data['notes'] as String?,
      },
    );
  }

  /// Parse deep link into a processed intent
  ProcessedIntent _parseDeepLink(Uri uri) {
    // Handle category deep links
    if (uri.path.startsWith('/category/') ||
        (uri.scheme == 'meaningto' && uri.host == 'category')) {
      final categoryId = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : uri.pathSegments[1];

      return ProcessedIntent(
        type: IntentType.deepLink,
        action: IntentAction.navigateToCategory,
        data: {'categoryId': categoryId},
        priority: IntentPriority.navigation,
      );
    }

    // Handle auth callbacks
    if (uri.scheme == 'meaningto' && uri.host == 'auth') {
      return ProcessedIntent(
        type: IntentType.deepLink,
        action: IntentAction.authenticate,
        data: {
          'uri': uri.toString(),
          'fragment': uri.fragment,
          'queryParameters': uri.queryParameters,
        },
        priority: IntentPriority.system,
      );
    }

    // Handle generic links (treat as processable URLs)
    if (uri.scheme.startsWith('http')) {
      return ProcessedIntent(
        type: IntentType.deepLink,
        action: IntentAction.processLink,
        data: {'url': uri.toString()},
        priority: IntentPriority.user,
      );
    }

    // Unknown deep link
    return ProcessedIntent(
      type: IntentType.deepLink,
      action: IntentAction.unknown,
      data: {'uri': uri.toString()},
      priority: IntentPriority.low,
    );
  }

  /// Parse share intent into a processed intent
  ProcessedIntent _parseShareIntent(SharedMedia media) {
    final content = media.content ?? '';

    // Extract URLs from shared content
    final urls = _extractUrls(content);

    if (urls.isNotEmpty) {
      // Shared content contains URLs
      return ProcessedIntent(
        type: IntentType.shareIntent,
        action: IntentAction.processLink,
        data: {
          'url': urls.first,
          'allUrls': urls,
          'originalContent': content,
          'serviceName': media.serviceName,
        },
        priority: IntentPriority.user,
      );
    }

    // Shared text without URLs - could be task content
    return ProcessedIntent(
      type: IntentType.shareIntent,
      action: IntentAction.showTaskEditor,
      data: {
        'headline':
            content.length > 100 ? content.substring(0, 100) + '...' : content,
        'notes': content.length > 100 ? content : null,
        'serviceName': media.serviceName,
      },
      priority: IntentPriority.user,
    );
  }

  /// Helper methods

  bool _shouldHandleImmediately(Uri uri) {
    // Handle auth callbacks immediately
    if (uri.scheme == 'meaningto' && uri.host == 'auth') {
      return true;
    }

    // On non-web platforms, handle category links immediately
    if (!kIsWeb &&
        (uri.path.startsWith('/category/') ||
            (uri.scheme == 'meaningto' && uri.host == 'category'))) {
      return true;
    }

    return false;
  }

  Future<BuildContext?> _getContext() async {
    int attempts = 0;
    const maxAttempts = 10;

    while (attempts < maxAttempts) {
      final context = _navigatorKey?.currentContext;
      if (context != null) return context;

      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }

    return null;
  }

  Future<void> _waitForStateRestoration() async {
    if (MyApp.isStateRestored) return;

    print('IntentHandler: Waiting for state restoration...');

    int attempts = 0;
    final maxAttempts = _stateRestorationTimeout.inMilliseconds ~/ 500;

    while (!MyApp.isStateRestored && attempts < maxAttempts) {
      await Future.delayed(const Duration(milliseconds: 500));
      attempts++;
    }

    if (MyApp.isStateRestored) {
      print('IntentHandler: State restoration complete');
    } else {
      print('IntentHandler: State restoration timeout, proceeding anyway');
    }
  }

  Future<void> _deferIntentProcessing(ProcessedIntent intent) async {
    print('IntentHandler: Deferring intent processing...');

    // Retry with exponential backoff
    await Future.delayed(const Duration(milliseconds: 1000));

    final context = await _getContext();
    if (context != null) {
      await _processIntent(intent, context: context);
    } else {
      print('IntentHandler: Failed to get context for deferred intent');
    }
  }

  Category? _getCurrentCategory() {
    try {
      return CacheManager().currentCategory;
    } catch (e) {
      print('IntentHandler: Error getting current category: $e');
      return null;
    }
  }

  List<String> _extractUrls(String text) {
    final urlRegex = RegExp(
      r'https?://[^\s<>"{}|\\^`\[\]]+',
      caseSensitive: false,
      multiLine: true,
    );

    return urlRegex.allMatches(text).map((match) => match.group(0)!).toList();
  }

  void _logIntent(IntentType type, Map<String, dynamic> data) {
    if (!_logIntents) return;

    final timestamp = DateTime.now().toIso8601String();
    print('\n=== Intent Handler Log ===');
    print('Time: $timestamp');
    print('Type: ${type.name}');
    print('Data: $data');
    print('========================\n');

    // Show user notification
    _scaffoldKey?.currentState?.showSnackBar(
      SnackBar(
        content: Text('Received ${type.name} intent'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Public methods for checking pending intents

  bool get hasPendingDeepLink => _pendingDeepLink != null;
  bool get hasPendingSharedContent => _pendingSharedContent != null;
  Uri? get pendingDeepLink => _pendingDeepLink;
  String? get pendingSharedContent => _pendingSharedContent;

  void clearPendingDeepLink() => _pendingDeepLink = null;
  void clearPendingSharedContent() => _pendingSharedContent = null;

  /// Process any pending intents after state restoration
  Future<void> processPendingIntents() async {
    if (_pendingDeepLink != null) {
      print('IntentHandler: Processing pending deep link');
      await _handleDeepLink(_pendingDeepLink!, isInitial: true);
      _pendingDeepLink = null;
    }

    if (_pendingSharedContent != null) {
      print('IntentHandler: Processing pending shared content');
      final media = SharedMedia(content: _pendingSharedContent);
      await _handleShareIntent(media, isInitial: true);
      _pendingSharedContent = null;
    }
  }

  /// Cleanup
  void dispose() {
    _linkSubscription?.cancel();
    _shareSubscription?.cancel();
    _isInitialized = false;
    print('IntentHandler: Disposed');
  }
}

/// Data classes for intent processing

enum IntentType {
  deepLink,
  shareIntent,
  manualLink,
  oauthCallback,
  deepLinkError,
  shareError,
}

enum IntentAction {
  processLink,
  navigateToCategory,
  authenticate,
  showTaskEditor,
  unknown,
}

enum IntentPriority {
  system, // Auth callbacks, critical system operations
  navigation, // Category navigation, route changes
  user, // User-initiated actions, shared content
  low, // Unknown or unhandled intents
}

class ProcessedIntent {
  final IntentType type;
  final IntentAction action;
  final Map<String, dynamic> data;
  final IntentPriority priority;
  final DateTime timestamp;

  ProcessedIntent({
    required this.type,
    required this.action,
    required this.data,
    required this.priority,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return 'ProcessedIntent(type: $type, action: $action, priority: $priority, data: $data)';
  }
}

/// Actions user can take when a duplicate link is found
enum DuplicateAction {
  keepExisting, // Keep the existing task, possibly edit it
  createNew, // Create a new task with the same link
  cancel, // Cancel the operation
}
