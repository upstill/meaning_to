import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/utils/link_to_task_converter.dart';
import 'package:meaning_to/edit_category_screen.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/new_content_screen.dart';
import 'package:meaning_to/performance_monitor_screen.dart';
import 'package:meaning_to/find_screen.dart';
import 'package:meaning_to/verify_links_screen.dart';
import 'package:meaning_to/dialogs/task_created_dialog.dart';
import 'package:meaning_to/widgets/edit_category_dialog.dart';
import 'dart:async';

import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/utils/app_buttons.dart';
import 'package:meaning_to/utils/synopsis_fetcher.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/deep_link_generator.dart';
import 'package:meaning_to/widgets/task_display.dart';
import 'package:clipboard/clipboard.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

enum HomeTaskSortOption { alphabetical, priority, age }

class HomeScreen extends StatefulWidget {
  static final ValueNotifier<bool> needsTaskReload = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> needsDataReload = ValueNotifier<bool>(false);

  final String? initialCategoryId;

  const HomeScreen({super.key, this.initialCategoryId});

  @override
  HomeScreenState createState() => HomeScreenState();

  // Static variable to track if data has been modified
  static bool _dataModified = false;

  // Method to mark that data has been modified (call from other screens)
  static void markDataModified() {
    _dataModified = true;
    needsDataReload.value = true; // Notify listeners
  }

  // Method to check and reset the modified flag
  static bool checkAndResetDataModified() {
    final wasModified = _dataModified;
    _dataModified = false;
    return wasModified;
  }
}

class HomeScreenState extends State<HomeScreen> {
  List<Category> _categories = [];
  Category? _selectedCategory;
  Task? _randomTask;
  bool _showTaskListMode = false;
  final TextEditingController _taskSearchController = TextEditingController();
  HomeTaskSortOption _taskListSortOption = HomeTaskSortOption.priority;
  bool _isSearchingTasks = false;
  bool _isTaskListSorting = false;
  List<Task> _listModeTasks = <Task>[];
  bool _isListModeLoading = false;
  bool _isListProgressiveLoading = false;
  int _visibleTaskCount = 0;
  static const int _initialListTaskCount = 16;
  static const int _listBatchSize = 24;
  bool _isLoading = true;
  bool _isLoadingTask = false;
  String? _error;
  bool _isReloading = false; // Guard to prevent concurrent reloads
  // Synopsis fetching state
  bool _isFetchingSynopsis = false;
  String? _fetchedSynopsis;

  // Non-null while edit panel is open
  Task? _editingTask;

  // CacheManager instance for managing current category and tasks
  final CacheManager _cacheManager = CacheManager();

  // Add getter for selected category
  Category? get selectedCategory => _selectedCategory;

  // Track if welcome dialog has been shown
  bool _welcomeDialogShown = false;

  // Track if this is the first load (to handle initial category selection from deep link)
  bool _isFirstLoad = true;

  // Check if current user is the developer
  bool get _isDeveloperUser {
    final userId = AuthUtils.getCurrentUserId();
    final isDev = userId == 'ed1e8fd6-44cc-4fff-b717-57ffb551cb2d';
    return isDev;
  }

  /// Build AppBar actions with conditional developer menu
  List<Widget> _buildAppBarActions() {
    final actions = <Widget>[];

    // Debug button - only show in debug mode
    if (foundation.kDebugMode) {
      actions.add(
        PopupMenuButton<String>(
          icon: const Icon(Icons.analytics),
          tooltip: 'Debug Tools',
          onSelected: (value) {
            if (value == 'performance') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PerformanceMonitorScreen(),
                ),
              );
            } else if (value == 'find') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const FindScreen(),
                ),
              );
            } else if (value == 'verify_links') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const VerifyLinksScreen(),
                ),
              );
            }
          },
          itemBuilder: (BuildContext context) => [
            const PopupMenuItem<String>(
              value: 'performance',
              child: Row(
                children: [
                  Icon(Icons.speed, size: 20),
                  SizedBox(width: 8),
                  Text('Performance Monitor'),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'find',
              child: Row(
                children: [
                  Icon(Icons.search, size: 20),
                  SizedBox(width: 8),
                  Text('Find Tasks'),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'verify_links',
              child: Row(
                children: [
                  Icon(Icons.link, size: 20),
                  SizedBox(width: 8),
                  Text('Verify Links'),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Developer menu - only show for developer user
    if (_isDeveloperUser) {
      actions.add(
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.orange,
            borderRadius: BorderRadius.circular(8),
          ),
          child: IconButton(
            icon: const Icon(
              Icons.build,
              color: Colors.white,
              size: 24,
            ),
            tooltip: 'Developer Tools',
            onPressed: () {
              _fixRawUrlsInTasks();
            },
          ),
        ),
      );
    }

    // Help button - always show
    actions.add(
      IconButton(
        icon: const Icon(Icons.info_outline),
        onPressed: () {
          Navigator.pushNamed(context, '/help');
        },
        tooltip: 'Help',
      ),
    );

    // Account menu - always show
    actions.add(
      PopupMenuButton<String>(
        icon: const Icon(Icons.account_circle),
        tooltip: 'Account',
        onSelected: (String value) async {
          if (value == 'logout') {
            await _handleLogout();
          } else if (value == 'delete') {
            await _handleDeleteAccount();
          }
        },
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
            value: 'logout',
            child: ListTile(
              leading: Icon(Icons.logout),
              title: Text('Logout'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const PopupMenuItem<String>(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete_forever, color: Colors.red),
              title:
                  Text('Delete Account', style: TextStyle(color: Colors.red)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );

    return actions;
  }

  /// Handle logout action
  Future<void> _handleLogout() async {
    await AuthUtils.signOut();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  /// Handle delete account action
  Future<void> _handleDeleteAccount() async {
    // Show confirmation dialog
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.red, size: 32),
              SizedBox(width: 8),
              Text('Delete Account'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WARNING: This action cannot be undone!',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                  fontSize: 16,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Deleting your account will permanently remove:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('• All your tasks'),
              Text('• All your categories'),
              Text('• Your user account'),
              SizedBox(height: 16),
              Text(
                'This data cannot be recovered.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete My Account'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _deleteAccountData();
    }
  }

  /// Delete all user data and account
  Future<void> _deleteAccountData() async {
    // Show loading indicator
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Deleting account...'),
            ],
          ),
        );
      },
    );

    try {
      final userId = AuthUtils.getCurrentUserId();

      // Delete all tasks for this user
      await supabase.from('Tasks').delete().eq('owner_id', userId);

      // Delete all categories for this user
      await supabase.from('Categories').delete().eq('owner_id', userId);

      // Try to delete the user's auth account
      // This requires either an RPC function or proper permissions
      try {
        // Attempt to use RPC function to delete user
        // You'll need to create this function in Supabase:
        // CREATE OR REPLACE FUNCTION delete_user()
        // RETURNS void
        // LANGUAGE plpgsql
        // SECURITY DEFINER
        // AS $$
        // BEGIN
        //   DELETE FROM auth.users WHERE id = auth.uid();
        // END;
        // $$;
        await supabase.rpc('delete_user');
      } catch (rpcError) {
        print('Could not delete auth user via RPC: $rpcError');
        // If RPC doesn't exist, data is still deleted
        // User account will remain in auth.users but with no data
      }

      // Sign out
      await AuthUtils.signOut();

      // Close loading dialog and navigate to auth screen
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        Navigator.pushReplacementNamed(context, '/');
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();

        // Show error dialog
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Error'),
              content: Text('Failed to delete account: $e'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      }
    }
  }

  /// Debug function to fix raw URLs in task links
  /// Converts any raw URL strings in the links array to proper HTML link format
  /// Processes all tasks in descending ID order
  Future<void> _fixRawUrlsInTasks() async {
    print('DEBUG: Starting to fix raw URLs in tasks');

    try {
      final userId = AuthUtils.getCurrentUserId();

      // Fetch all tasks for this user, ordered by ID descending
      final response = await supabase
          .from('Tasks')
          .select()
          .eq('owner_id', userId)
          .order('id', ascending: false);

      final tasks =
          (response as List).map((json) => Task.fromJson(json)).toList();

      print('DEBUG: Found ${tasks.length} total tasks to check');

      int tasksModified = 0;
      int linksFixed = 0;

      for (final task in tasks) {
        print('DEBUG: Processing task ID ${task.id}: "${task.headline}"');

        // Skip tasks with no links
        if (task.links == null || task.links!.isEmpty) {
          print('DEBUG: Task has no links, skipping');
          continue;
        }

        print('DEBUG: Task has ${task.links!.length} links');

        bool modified = false;
        final updatedLinks = <String>[];

        for (int i = 0; i < task.links!.length; i++) {
          final link = task.links![i];
          print('DEBUG: Link $i: $link');

          // Check if this is a raw URL (doesn't start with <a)
          if (!link.trim().startsWith('<a')) {
            print('DEBUG: Found raw URL, converting to HTML link');
            print('DEBUG: Original URL: $link');

            // Normalize the URL first (this handles TIDAL /u stripping, etc.)
            final normalizedUrl = LinkToTaskConverter.normalizeUrl(link);
            print('DEBUG: Normalized URL: $normalizedUrl');

            // Process the normalized URL to create HTML link
            final processedLink =
                await LinkProcessor.validateAndProcessLink(normalizedUrl);
            final htmlLink =
                '<a href="${processedLink.url}">${processedLink.title ?? processedLink.url}</a>';

            print('DEBUG: Converted to: $htmlLink');
            updatedLinks.add(htmlLink);
            modified = true;
            linksFixed++;
          } else {
            print(
                'DEBUG: Link is already HTML formatted, checking if URL needs normalization');

            // Extract URL from HTML link
            final urlMatch = RegExp(r'href="([^"]+)"').firstMatch(link);
            if (urlMatch != null) {
              final originalUrl = urlMatch.group(1)!;
              print('DEBUG: Extracted URL: $originalUrl');

              // Normalize the URL
              final normalizedUrl =
                  LinkToTaskConverter.normalizeUrl(originalUrl);
              print('DEBUG: Normalized URL: $normalizedUrl');

              // Check if URL changed after normalization
              if (normalizedUrl != originalUrl) {
                print('DEBUG: URL was normalized, updating link');

                // Replace the old URL with normalized one in the HTML link
                final updatedLink = link.replaceAll(originalUrl, normalizedUrl);
                print('DEBUG: Updated link: $updatedLink');

                updatedLinks.add(updatedLink);
                modified = true;
                linksFixed++;
              } else {
                print('DEBUG: URL did not need normalization');
                updatedLinks.add(link);
              }
            } else {
              print('DEBUG: Could not extract URL from HTML link');
              updatedLinks.add(link);
            }
          }
        }

        if (modified) {
          print('DEBUG: Updating task ${task.id} with fixed links');
          print('DEBUG: Total links being saved: ${updatedLinks.length}');
          print('DEBUG: Links: ${updatedLinks.join(", ")}');

          // Update the task in the database
          await supabase
              .from('Tasks')
              .update({'links': updatedLinks}).eq('id', task.id);

          print('DEBUG: Task ${task.id} updated successfully');
          tasksModified++;
        } else {
          print(
              'DEBUG: No raw URLs found in task ${task.id}, continuing to next task');
        }
      }

      print('DEBUG: Finished processing tasks');
      print('DEBUG: Total tasks modified: $tasksModified');
      print('DEBUG: Total links fixed: $linksFixed');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Fixed $linksFixed raw URLs across $tasksModified tasks'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('DEBUG: Error fixing raw URLs: $e');
      print('DEBUG: Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    print('HomeScreen: initState called');
    // Listen for task reload requests
    HomeScreen.needsTaskReload.addListener(_handleTaskReloadRequest);
    // Listen for data reload requests (categories and tasks)
    HomeScreen.needsDataReload.addListener(_handleDataReloadRequest);

    // Load categories after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadCategories();
      }
    });
  }

  /// Select the initial category if one was provided
  void _selectInitialCategory() {
    print(
        '_selectInitialCategory called with initialCategoryId: ${widget.initialCategoryId}');
    print('Categories available: ${_categories.length}');
    if (widget.initialCategoryId != null && _categories.isNotEmpty) {
      try {
        final categoryId = int.parse(widget.initialCategoryId!);
        print('Parsed category ID: $categoryId');
        print('Looking for category with ID: $categoryId');

        final category = _categories.firstWhere(
          (c) => c.id == categoryId,
          orElse: () => _categories.first,
        );

        print('Found category: ${category.headline} (ID: ${category.id})');

        if (category.id == categoryId) {
          print('Setting selected category to: ${category.headline}');
          setState(() {
            _selectedCategory = category;
          });
          _loadRandomTask(category);
          // Update last_access for the selected category
          _updateCategoryLastAccess(category);
        } else {
          print(
              'Category ID mismatch - expected: $categoryId, got: ${category.id}');
        }
      } catch (e) {
        print('Error parsing category ID: ${widget.initialCategoryId} - $e');
      }
    } else {
      print('No initial category ID or no categories available');
    }
  }

  @override
  void dispose() {
    HomeScreen.needsTaskReload.removeListener(_handleTaskReloadRequest);
    HomeScreen.needsDataReload.removeListener(_handleDataReloadRequest);
    _taskSearchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check if data was modified by other screens
    final dataModified = HomeScreen.checkAndResetDataModified();

    // Refresh cache when dependencies change (e.g., when returning from other screens)
    if (_selectedCategory != null) {
      _refreshCacheIfNeeded(forceDatabaseRefresh: dataModified);
    } else if (dataModified) {
      // If no category is selected but data was modified (e.g., new categories imported),
      // reload categories to pick up the new data
      print(
          'HomeScreen: No category selected but data was modified, reloading categories');
      _loadCategories();
    }
  }

  /// Smart refresh that can skip database calls when appropriate
  Future<void> _refreshCacheIfNeeded(
      {bool forceDatabaseRefresh = false}) async {
    // Guard: Skip if already reloading
    if (_isReloading) {
      print(
          'HomeScreen: Reload already in progress, skipping _refreshCacheIfNeeded');
      return;
    }

    _isReloading = true;
    try {
      final cacheManager = CacheManager();
      final currentTaskId = _randomTask?.id;

      if (cacheManager.currentCategory?.id != _selectedCategory!.id ||
          cacheManager.currentTasks == null) {
        print(
          'HomeScreen: Refreshing cache for category ${_selectedCategory!.headline}',
        );
        await _loadRandomTask(_selectedCategory!);
      } else {
        print(
          'HomeScreen: Cache is up to date for category ${_selectedCategory!.headline}',
        );

        if (forceDatabaseRefresh) {
          // Force refresh from database to ensure we have the latest data
          await cacheManager.refreshFromApi();
          print('HomeScreen: Forced database refresh completed');
        } else {
          // Use local cache refresh for better performance
          cacheManager.refreshLocalCache();
          print('HomeScreen: Local cache refresh completed');
        }

        // Check if the current task still exists before reloading
        if (currentTaskId != null) {
          final currentTaskStillExists = cacheManager.currentTasks?.any(
                (task) => task.id == currentTaskId && !task.finished,
              ) ??
              false;

          if (currentTaskStillExists) {
            // Current task still exists - just update it in case it was modified
            final updatedTask = cacheManager.currentTasks!.firstWhere(
              (task) => task.id == currentTaskId,
            );

            print('HomeScreen: Current task still valid, keeping it displayed');
            if (mounted) {
              setState(() {
                _randomTask = updatedTask;
              });
              // Also refresh the task list view if it's visible
              if (_showTaskListMode) {
                _rebuildTaskListFromCache();
              }
            }
            return; // Don't load a new random task
          }
        }

        // Only reload the random task if current one doesn't exist or was finished
        await _loadRandomTask(_selectedCategory!);
      }
    } finally {
      _isReloading = false;
    }
  }

  /// Determine if a database refresh is needed based on various factors
  bool _shouldRefreshFromApi() {
    // Add your logic here to determine when database refresh is needed
    // For example:
    // - Time since last refresh
    // - Whether user has been editing tasks
    // - Network connectivity
    // - Cache staleness indicators

    // For now, return false to use local refresh by default
    return false;
  }

  /// Force refresh and verify database state for debugging
  Future<void> _forceRefreshAndVerify() async {
    print('HomeScreen: Force refresh and verify called');
    await _cacheManager.forceRefreshAndVerify();

    // Reload the random task with the verified data
    if (_selectedCategory != null) {
      await _loadRandomTask(_selectedCategory!);
    }
  }

  Future<void> _loadRandomTask(Category category) async {
    print(
      'HomeScreen: Starting to load random task for category: ${category.headline}',
    );
    try {
      setState(() {
        _isLoadingTask = true;
        _error = null;
      });

      final userId = AuthUtils.getCurrentUserId();
      print(
        'HomeScreen: Using user ID: $userId (guest: ${AuthUtils.isGuestUser()})',
      );

      // Initialize CacheManager with the selected category
      if (!_cacheManager.isInitialized ||
          _cacheManager.currentCategory?.id != category.id) {
        print(
          'HomeScreen: Initializing CacheManager with category: ${category.headline}',
        );
        await _cacheManager.initializeWithSavedCategory(category, userId);
      }

      // Get a random unfinished task from the cache
      final task = _cacheManager.getRandomUnfinishedTask();
      print('HomeScreen: Task loaded: \'${task?.headline}\'');

      if (mounted) {
        setState(() {
          _randomTask = task;
          _isLoadingTask = false;
          _fetchedSynopsis = null; // Reset fetched synopsis for new task
        });
        print('HomeScreen: State updated with new task');

        // Try to fetch synopsis if the task has no synopsis but has links
        if (_shouldFetchNotes()) {
          _fetchSynopsisFromLinks();
        }
      } else {
        print('HomeScreen: Widget not mounted after loading task');
      }
    } catch (e) {
      print('HomeScreen: Error loading random task: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoadingTask = false;
        });
      }
      rethrow;
    }
  }

  void _toggleTaskListMode() {
    if (_selectedCategory == null) {
      return;
    }

    final turningOn = !_showTaskListMode;
    setState(() {
      _showTaskListMode = turningOn;
    });

    if (turningOn) {
      _rebuildTaskListFromCache();
      if (_cacheManager.currentCategory?.id != _selectedCategory?.id ||
          _cacheManager.currentTasks == null) {
        setState(() {
          _isListModeLoading = true;
        });
        unawaited(_loadTaskListDataInBackground());
      } else {
        setState(() {
          _isListModeLoading = false;
        });
      }
    }
  }

  Future<void> _loadTaskListDataInBackground() async {
    final category = _selectedCategory;
    if (category == null) {
      return;
    }

    try {
      final userId = AuthUtils.getCurrentUserId();
      await _cacheManager.initializeWithSavedCategory(category, userId);

      if (mounted && _showTaskListMode) {
        setState(() {
          _rebuildTaskListFromCache();
          _isListModeLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isListModeLoading = false;
        });
      }
      print('HomeScreen: Background list load failed: $e');
    }
  }

  List<Task> _computeTasksForSelectedCategory() {
    final categoryId = _selectedCategory?.id;
    if (categoryId == null) {
      return <Task>[];
    }

    var tasks = (_cacheManager.currentTasks ?? <Task>[])
        .where((task) => task.categoryId == categoryId)
        .toList();

    final query = _taskSearchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      tasks = tasks
          .where((task) => task.headline.toLowerCase().contains(query))
          .toList();
    }

    switch (_taskListSortOption) {
      case HomeTaskSortOption.alphabetical:
        tasks.sort(
          (a, b) => _compareTasksBySort(a, b, HomeTaskSortOption.alphabetical),
        );
        break;
      case HomeTaskSortOption.priority:
        tasks.sort(
          (a, b) => _compareTasksBySort(a, b, HomeTaskSortOption.priority),
        );
        break;
      case HomeTaskSortOption.age:
        tasks.sort((a, b) => _compareTasksBySort(a, b, HomeTaskSortOption.age));
        break;
    }

    return tasks;
  }

  int _compareTasksBySort(Task a, Task b, HomeTaskSortOption option) {
    switch (option) {
      case HomeTaskSortOption.alphabetical:
        return a.headline.toLowerCase().compareTo(b.headline.toLowerCase());
      case HomeTaskSortOption.priority:
        if (a.finished != b.finished) {
          return a.finished ? 1 : -1;
        }
        if (a.suggestibleAt == null && b.suggestibleAt == null) {
          return b.createdAt.compareTo(a.createdAt);
        }
        if (a.suggestibleAt == null) {
          return -1;
        }
        if (b.suggestibleAt == null) {
          return 1;
        }
        return a.suggestibleAt!.compareTo(b.suggestibleAt!);
      case HomeTaskSortOption.age:
        return b.createdAt.compareTo(a.createdAt);
    }
  }

  Future<void> _applySortOptionAsync(HomeTaskSortOption option) async {
    if (_taskListSortOption == option || _isTaskListSorting) {
      return;
    }

    setState(() {
      _taskListSortOption = option;
      _isTaskListSorting = true;
    });

    await Future.delayed(const Duration(milliseconds: 1));

    final previousVisibleCount = _visibleTaskCount;
    final sorted = List<Task>.from(_listModeTasks)
      ..sort((a, b) => _compareTasksBySort(a, b, option));

    if (!mounted) return;

    setState(() {
      _listModeTasks = sorted;
      _visibleTaskCount = previousVisibleCount.clamp(0, sorted.length);
      if (_visibleTaskCount == 0) {
        _prepareVisibleTaskCount();
      } else if (_visibleTaskCount < sorted.length &&
          !_isListProgressiveLoading) {
        unawaited(_loadMoreListTasksProgressively());
      }
      _isTaskListSorting = false;
    });
  }

  void _rebuildTaskListFromCache() {
    _listModeTasks = _computeTasksForSelectedCategory();
    _prepareVisibleTaskCount();
  }

  void _prepareVisibleTaskCount() {
    if (_listModeTasks.length > 50) {
      _visibleTaskCount = _initialListTaskCount.clamp(0, _listModeTasks.length);
      _isListProgressiveLoading = false;
      unawaited(_loadMoreListTasksProgressively());
    } else {
      _visibleTaskCount = _listModeTasks.length;
      _isListProgressiveLoading = false;
    }
  }

  Future<void> _loadMoreListTasksProgressively() async {
    if (_isListProgressiveLoading) return;
    _isListProgressiveLoading = true;

    while (mounted &&
        _showTaskListMode &&
        _visibleTaskCount < _listModeTasks.length) {
      await Future.delayed(const Duration(milliseconds: 45));

      if (!mounted || !_showTaskListMode) break;

      setState(() {
        _visibleTaskCount = (_visibleTaskCount + _listBatchSize)
            .clamp(0, _listModeTasks.length);
      });
    }

    _isListProgressiveLoading = false;
  }

  Future<void> _toggleTaskCompletionFromList(Task task) async {
    try {
      if (task.finished) {
        await _cacheManager.unfinishTask(task.id);
      } else {
        await _cacheManager.finishTask(task.id);
      }

      if (mounted) {
        setState(() {
          _rebuildTaskListFromCache();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteTaskFromList(Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Are you sure you want to delete "${task.headline}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _cacheManager.removeTask(task.id);
      if (_randomTask?.id == task.id) {
        _randomTask = null;
      }
      if (mounted) {
        setState(() {
          _rebuildTaskListFromCache();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteCategory(Category category) async {
    final catName = NamingUtils.categoriesName(plural: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $catName'),
        content: Text(
          'Are you sure you want to delete "${category.headline}"? '
          'All ${NamingUtils.tasksName()} in this $catName will also be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase.from('Categories').delete().eq('id', category.id);
      if (mounted) await _loadCategories();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting $catName: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleTaskShareFromList(Task task, bool newSharedState) async {
    final updatedTask = Task(
      id: task.id,
      categoryId: task.categoryId,
      headline: task.headline,
      notes: task.notes,
      synopsis: task.synopsis,
      ownerId: task.ownerId,
      createdAt: task.createdAt,
      suggestibleAt: task.suggestibleAt,
      triggersAt: task.triggersAt,
      deferral: task.deferral,
      links: task.links,
      processedLinks: task.processedLinks,
      finished: task.finished,
      shared: newSharedState,
      originalId: task.originalId,
      dirty: true,
    );

    try {
      await _cacheManager.updateTask(updatedTask);
      if (_randomTask?.id == task.id) {
        _randomTask = updatedTask.markClean();
      }
      if (mounted) {
        setState(() {
          _rebuildTaskListFromCache();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating share state: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildTaskListModeContent() {
    final tasks = _listModeTasks;
    final displayedTasks =
        (_visibleTaskCount <= 0 || _visibleTaskCount >= tasks.length)
            ? tasks
            : tasks.take(_visibleTaskCount).toList();

    Widget buildSortRow(HomeTaskSortOption option, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Radio<HomeTaskSortOption>(
            value: option,
            groupValue: _taskListSortOption,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            onChanged: (HomeTaskSortOption? value) {
              if (value == null) return;
              unawaited(_applySortOptionAsync(value));
            },
          ),
          Text(label),
        ],
      );
    }

    final sortWidget = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text('Sort By:'),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            buildSortRow(HomeTaskSortOption.priority, 'Priority'),
            buildSortRow(HomeTaskSortOption.alphabetical, 'A-Z'),
            buildSortRow(HomeTaskSortOption.age, 'Age'),
          ],
        ),
      ],
    );

    final searchWidget = TextField(
      controller: _taskSearchController,
      decoration: InputDecoration(
        hintText:
            'Search ${NamingUtils.tasksName(capitalize: true, plural: true)}...',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _isSearchingTasks
            ? const Padding(
                padding: EdgeInsets.all(12.0),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _taskSearchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      setState(() {
                        _taskSearchController.clear();
                        _rebuildTaskListFromCache();
                      });
                    },
                  )
                : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) {
        setState(() {
          _isSearchingTasks = true;
          _rebuildTaskListFromCache();
        });
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) {
            setState(() {
              _isSearchingTasks = false;
            });
          }
        });
      },
    );

    if (_isListModeLoading && tasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (tasks.isEmpty) {
      return Center(
        child: Column(
          children: [
            const Text('No tasks yet.', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            Text(
              'Tap the + button to add ${NamingUtils.tasksName(plural: true, capitalize: false)}.',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final sortAreaWidth =
                (constraints.maxWidth * 0.35).clamp(0.0, 240.0);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: sortAreaWidth,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: sortWidget,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: searchWidget),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        if (_isTaskListSorting) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ),
        ],
        Text(
          '${tasks.length} ${NamingUtils.tasksName(plural: true, capitalize: false)}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 8),
        ...displayedTasks.map(
          (task) => TaskDisplay(
            key: ValueKey(
                'home-task-${task.id}-${task.finished}-${task.shared}'),
            task: task,
            withControls: true,
            onEdit: () => _showEditPanel(task),
            onDelete: () => _deleteTaskFromList(task),
            onTap: () => _toggleTaskCompletionFromList(task),
            onShareToggle: (newSharedState) =>
                _toggleTaskShareFromList(task, newSharedState),
            isCategoryPrivate: _selectedCategory?.isPrivate ?? false,
          ),
        ),
        if (_isListProgressiveLoading && _visibleTaskCount < tasks.length)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _rejectCurrentTask() async {
    try {
      setState(() {
        _isLoadingTask = true;
        _error = null;
      });

      if (_randomTask == null) {
        throw Exception('No current task to reject');
      }

      // Use CacheManager to reject the task
      await _cacheManager.rejectTask(_randomTask!.id);

      // Load a new random task
      if (_selectedCategory != null) {
        await _loadRandomTask(_selectedCategory!);
      } else {
        setState(() {
          _randomTask = null;
          _isLoadingTask = false;
        });
      }
    } catch (e) {
      print('Error rejecting task: $e');
      setState(() {
        _error = e.toString();
        _isLoadingTask = false;
      });
    }
  }

  Future<void> _finishCurrentTask() async {
    try {
      setState(() {
        _isLoadingTask = true;
        _error = null;
      });

      if (_randomTask == null) {
        throw Exception('No current task to finish');
      }

      // Use CacheManager to finish the task
      await _cacheManager.finishTask(_randomTask!.id);

      // Load a new random task
      if (_selectedCategory != null) {
        await _loadRandomTask(_selectedCategory!);
      } else {
        setState(() {
          _randomTask = null;
          _isLoadingTask = false;
        });
      }
    } catch (e) {
      print('Error finishing task: $e');
      setState(() {
        _error = e.toString();
        _isLoadingTask = false;
      });
    }
  }

  Future<void> _reviveCurrentTask() async {
    try {
      if (_randomTask == null) {
        throw Exception('No current task to revive');
      }

      final userId = AuthUtils.getCurrentUserId();
      print(
        'HomeScreen: Using user ID: $userId (guest: ${AuthUtils.isGuestUser()})',
      );

      // Use CacheManager to revive the task
      await _cacheManager.reviveTask(_randomTask!.id);

      // Update the current task reference
      final updatedTask = _cacheManager.currentTasks?.firstWhere(
        (t) => t.id == _randomTask!.id,
        orElse: () => _randomTask!,
      );

      if (updatedTask != null) {
        setState(() {
          _randomTask = updatedTask;
        });
      }
    } catch (e) {
      print('Error reviving task: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error reviving task: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Update the last_access timestamp for a category when it's selected
  Future<void> _updateCategoryLastAccess(Category category) async {
    try {
      await supabase
          .from('Categories')
          .update({'last_access': DateTime.now().toUtc().toIso8601String()}).eq(
              'id', category.id);

      print('Updated last_access for category: ${category.headline}');

      // Move the selected category to the top of the list
      setState(() {
        final selectedIndex =
            _categories.indexWhere((c) => c.id == category.id);
        if (selectedIndex != -1) {
          // Remove the selected category from its current position
          final selectedCategory = _categories.removeAt(selectedIndex);
          // Add it to the beginning of the list (top of dropdown)
          _categories.insert(0, selectedCategory);
        }
      });
    } catch (e) {
      print('Error updating last_access for category: $e');
      // Don't show error to user as this is not critical functionality
    }
  }

  Future<void> _loadCategories() async {
    try {
      print('Starting to load categories...');

      // For now, we'll use guest mode since we haven't implemented serverless auth yet
      print('Using guest mode for category loading');
      final guestUserId = AuthUtils.getCurrentUserId();
      print('Guest user ID: $guestUserId');

      try {
        print('Fetching categories from API...');
        final categories = await ApiClient.getCategories();
        print('API response: ${categories.length} categories');

        setState(() {
          _categories = categories;
          _isLoading = false;
        });
        print('Categories loaded successfully');

        // Only select initial category on first load (e.g., from deep link)
        // On subsequent reloads, preserve the user's dropdown selection
        if (_isFirstLoad) {
          _selectInitialCategory();
          _isFirstLoad = false;

          // If there's only one category and no category is selected, select it automatically
          if (categories.length == 1 && _selectedCategory == null) {
            print(
                'HomeScreen: Only one category available, selecting it automatically');
            setState(() {
              _selectedCategory = categories.first;
            });
            _loadRandomTask(categories.first);
            _updateCategoryLastAccess(categories.first);
          }
        } else {
          // On subsequent loads, update the selected category reference to the new object
          if (_selectedCategory != null) {
            final updatedCategory = categories.firstWhere(
              (c) => c.id == _selectedCategory!.id,
              orElse: () =>
                  categories.isNotEmpty ? categories.first : _selectedCategory!,
            );
            if (updatedCategory.id == _selectedCategory!.id) {
              setState(() {
                _selectedCategory = updatedCategory;
              });
            }
          } else if (categories.length == 1) {
            // Auto-select if there's only one category and none is currently selected
            // This handles the case where a user imports their first category
            print(
                'HomeScreen: Only one category available on reload, selecting it automatically');
            setState(() {
              _selectedCategory = categories.first;
            });
            _loadRandomTask(categories.first);
            _updateCategoryLastAccess(categories.first);
          }
        }

        // Ensure we always have an actively selected category when categories exist.
        // This guarantees task selection on startup even with multiple categories.
        if (categories.isNotEmpty && _selectedCategory == null) {
          setState(() {
            _selectedCategory = categories.first;
          });
          _loadRandomTask(categories.first);
          _updateCategoryLastAccess(categories.first);
        }

        // Show welcome dialog for authenticated users with no categories
        // Reset flag on each category load to show dialog on each login
        if (!AuthUtils.isGuestUser() && categories.isEmpty) {
          _welcomeDialogShown = false; // Reset to allow showing again
          _checkAndShowWelcomeDialog();
        }
      } catch (e) {
        print('Error loading categories: $e');
        setState(() {
          _categories = [];
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      print('Error loading categories: $e');
      print('Stack trace: $stackTrace');

      // Check if it's a network error
      String errorMessage;
      if (e.toString().contains('Failed host lookup') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('Network is unreachable')) {
        errorMessage =
            "Sorry, but we can't connect to the cloud. Are you online?";
      } else {
        errorMessage = e.toString();
      }

      setState(() {
        _error = errorMessage;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleCategorySelection(Category? newValue) async {
    // If the edit panel is open, intercept and show copy/move dialog instead
    if (_editingTask != null && newValue != null) {
      await _handleEditPanelCategoryChange(_editingTask!, newValue);
      return;
    }

    // Evaluate before setState so _isListModeLoading can be set in the same
    // frame — preventing a "No tasks yet" flash while the load is pending.
    final needsLoad = _showTaskListMode &&
        newValue != null &&
        (_cacheManager.currentCategory?.id != newValue.id ||
            _cacheManager.currentTasks == null);

    setState(() {
      _selectedCategory = newValue;
      _randomTask = null;
      if (_showTaskListMode) {
        _rebuildTaskListFromCache();
        if (needsLoad) _isListModeLoading = true;
      }
    });

    if (newValue != null) {
      await _updateCategoryLastAccess(newValue);
      if (_showTaskListMode) {
        if (needsLoad) {
          unawaited(_loadTaskListDataInBackground());
        }
      } else {
        _loadRandomTask(newValue);
      }
    }
  }

  void _handleTaskReloadRequest() {
    print('HomeScreen: Task reload requested');
    if (HomeScreen.needsTaskReload.value && mounted) {
      print('HomeScreen: Handling task reload request');
      print('HomeScreen: Current category: \'${_selectedCategory?.headline}\'');
      print('HomeScreen: Current task: \'${_randomTask?.headline}\'');

      HomeScreen.needsTaskReload.value = false; // Reset the flag
      _handleEditComplete();
    } else {
      print(
        'HomeScreen: Task reload requested but widget not mounted or flag not set',
      );
      print(
        'HomeScreen: mounted: $mounted, needsTaskReload: ${HomeScreen.needsTaskReload.value}',
      );
    }
  }

  void _handleDataReloadRequest() {
    print('HomeScreen: Data reload requested');
    if (HomeScreen.needsDataReload.value && mounted) {
      print('HomeScreen: Handling data reload request');
      HomeScreen.needsDataReload.value = false; // Reset the flag

      // Reload categories and tasks
      _loadCategories().then((_) {
        // After categories are loaded, reload the current task if we have a selected category
        if (_selectedCategory != null && mounted) {
          _loadRandomTask(_selectedCategory!);
        }
      });
    } else {
      print(
        'HomeScreen: Data reload requested but widget not mounted or flag not set',
      );
      print(
        'HomeScreen: mounted: $mounted, needsDataReload: ${HomeScreen.needsDataReload.value}',
      );
    }
  }

  void _navigateToNewCategory() {
    print('HomeScreen: Starting navigation to new category screen...');

    if (!mounted) {
      print('HomeScreen: Not mounted before navigation');
      return;
    }

    Navigator.pushNamed(context, '/new-category').then((result) {
      // If we got a result (Category from direct creation, or true from ShopEndeavorsScreen import), reload categories
      if (result != null) {
        print(
            'HomeScreen: Category was created or imported, reloading categories');
        _loadCategories();
      }
    });
  }

  void _navigateToNewContent() async {
    print('HomeScreen: Starting navigation to new content screen...');

    if (!mounted) {
      print('HomeScreen: Not mounted before navigation');
      return;
    }

    // Navigate directly to New Content screen
    // It will show New Task variant if categories exist, or New Category variant if not
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewContentScreen(
          selectedCategory: _selectedCategory,
        ),
      ),
    ).then((result) async {
      if (result != null) {
        if (result is Map<String, dynamic>) {
          final count = result['count'] ?? 1;
          if (count == 1) {
            // Single task created - show popup
            await _handleSingleTaskCreated(result);
          } else {
            // Multiple tasks created - go to Edit Category
            await _handleMultipleTasksCreated(result);
          }
        } else if (result == true) {
          // Category created or bulk import without specific data - reload data
          print('HomeScreen: Content was created, reloading data');
          _loadCategories();
          if (_selectedCategory != null) {
            _loadRandomTask(_selectedCategory!);
          }
        }
      }
    });
  }

  Future<void> _handleSingleTaskCreated(Map<String, dynamic> result) async {
    final taskData = result['task'];
    final categoryData = result['category'];
    final category = Category.fromJson(categoryData);

    final action = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return TaskCreatedDialog(
          taskData: taskData,
          category: category,
        );
      },
    );

    if (action == 'edit' && mounted) {
      // Create Task object from the data for editing
      final task = Task.fromJson(taskData);

      // Navigate to edit screen
      final editResult = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TaskEditScreen(
            task: task,
            category: category,
          ),
        ),
      );

      // Reload data if task was modified
      if (editResult == true && mounted) {
        _loadCategories();
        if (_selectedCategory != null) {
          _loadRandomTask(_selectedCategory!);
        }
      }
    } else {
      // User accepted or dismissed - reload data
      _loadCategories();
      if (_selectedCategory != null) {
        _loadRandomTask(_selectedCategory!);
      }
    }
  }

  Future<void> _handleMultipleTasksCreated(Map<String, dynamic> result) async {
    final categoryData = result['category'];
    final category = Category.fromJson(categoryData);

    // Navigate directly to Edit Category screen showing the new tasks
    if (mounted) {
      final editResult = await Navigator.pushNamed(
        context,
        '/edit-category',
        arguments: {
          'category': category,
          'tasksOnly': false,
        },
      );

      // Reload data when returning from Edit Category
      if (mounted) {
        _loadCategories();
        if (_selectedCategory != null) {
          _loadRandomTask(_selectedCategory!);
        }
      }
    }
  }

  void _showCategoryInfo(Category category) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(category.headline),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (category.invitation != null &&
                    category.invitation!.isNotEmpty) ...[
                  const Text(
                    'Invitation:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    category.invitation!,
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _shareCategory(Category category) {
    bool makePublic = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: Text('Share "${category.headline}"'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Warning for private categories
                  if (category.isPrivate) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        border: Border.all(color: Colors.orange.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This category is private to you. You can make it public if you want to share it with others.',
                              style: TextStyle(
                                color: Colors.orange.shade800,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Checkbox to make category public
                    CheckboxListTile(
                      title: const Text(
                        'Make it public',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: const Text(
                        'Allow others to access this category via the shared link',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: makePublic,
                      onChanged: (value) {
                        setState(() {
                          makePublic = value ?? false;
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Text(
                    'Share this category with others using one of these methods:',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  _buildShareOption(
                    context,
                    'Copy Link',
                    Icons.link,
                    Colors.blue,
                    () => _copyCategoryLink(category, makePublic),
                  ),
                  const SizedBox(height: 8),
                  _buildShareOption(
                    context,
                    'Share via App',
                    Icons.share,
                    Colors.green,
                    () => _shareViaApp(category, makePublic),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildShareOption(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            Icon(Icons.arrow_forward_ios,
                size: 16, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  void _copyCategoryLink(Category category, bool makePublic) async {
    // If user wants to make category public, update it first
    if (makePublic && category.isPrivate) {
      await _makeCategoryPublic(category);
    }

    final link = DeepLinkGenerator.generateCategoryLink(category.id);
    FlutterClipboard.copy(link).then((value) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Link copied to clipboard: $link'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.green,
        ),
      );
    });
    Navigator.of(context).pop();
  }

  void _shareViaApp(Category category, bool makePublic) async {
    // If user wants to make category public, update it first
    if (makePublic && category.isPrivate) {
      await _makeCategoryPublic(category);
    }

    final link = DeepLinkGenerator.generateCategoryLink(category.id);
    // You can implement native sharing here using packages like share_plus
    // For now, just show the link
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Share Link'),
          content: SelectableText(link),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  /// Make a category public by updating its privacy setting
  Future<void> _makeCategoryPublic(Category category) async {
    try {
      print('HomeScreen: Making category "${category.headline}" public');

      // Update in API
      await ApiClient.updateCategory(category.id.toString(), {
        'private': false,
      });

      // Update local state
      category.isPrivate = false;

      // Update the categories list to reflect the change
      setState(() {});

      print('HomeScreen: Category made public successfully');

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Category is now public! You can share it with others.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error making category public: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error making category public: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _navigateToEditCategory([Category? category]) async {
    print('HomeScreen: Starting navigation to edit category screen...');
    print('HomeScreen: Current category: \'${_selectedCategory?.headline}\'');
    print('HomeScreen: Current task: \'${_randomTask?.headline}\'');

    if (!mounted) {
      print('HomeScreen: Not mounted before navigation');
      return;
    }

    // Set up the static callback before navigation
    EditCategoryScreen.onEditComplete = () {
      print('HomeScreen: Edit complete callback received');
      if (mounted) {
        print('HomeScreen: Widget mounted, triggering task reload');
        // Force a rebuild and task reload
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            print('HomeScreen: Post frame callback executing');
            setState(() {
              print('HomeScreen: Setting needsTaskReload to true');
              HomeScreen.needsTaskReload.value = true;
            });
            // The listener will call _handleEditComplete(), no need to call it directly
          } else {
            print('HomeScreen: Widget not mounted in post frame callback');
          }
        });
      } else {
        print('HomeScreen: Widget not mounted, cannot trigger task reload');
      }
    };
    print(
      'HomeScreen: Set static callback: ${EditCategoryScreen.onEditComplete != null}',
    );

    try {
      print('HomeScreen: About to push route...');
      // Create the screen
      final screen = EditCategoryScreen(
        key: ValueKey('edit_category_${category?.id ?? 'new'}'),
        category: category,
        tasksOnly: false,
        startInCategoryEditorPanel: true,
      );
      print('HomeScreen: Created EditCategoryScreen');

      // Push the route and wait for result
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => screen, fullscreenDialog: true),
      );
      print(
        'HomeScreen: Returned from edit category screen with result: $result',
      );

      // If we got a result (true), reload categories
      if (result == true) {
        print('HomeScreen: Category was created/edited, reloading categories');
        await _loadCategories();
      }
    } catch (e, stackTrace) {
      print('HomeScreen: Error during navigation: $e');
      print('HomeScreen: Stack trace: $stackTrace');
    } finally {
      // Always clear the callback after navigation
      EditCategoryScreen.onEditComplete = null;
      print('HomeScreen: Cleared static callback');
    }
  }

  Future<void> _showEditPanel(Task task) async {
    print('HomeScreen: Showing edit panel for task: ${task.headline}');
    if (!mounted || _selectedCategory == null) {
      print('HomeScreen: Not mounted or no category selected');
      return;
    }

    setState(() => _editingTask = task);

    TaskEditScreen.onEditComplete = () {
      print('HomeScreen: Task edit complete callback received');
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              HomeScreen.needsTaskReload.value = true;
            });
          }
        });
      }
    };

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.97,
        expand: false,
        builder: (_, __) => Material(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: TaskEditScreen(
            category: _selectedCategory!,
            task: task,
            isPanel: true,
            onCategoryChange: (newCategory) =>
                _handleEditPanelCategoryChange(task, newCategory),
          ),
        ),
      ),
    );

    TaskEditScreen.onEditComplete = null;
    setState(() => _editingTask = null);
  }

  Future<void> _handleEditPanelCategoryChange(
      Task task, Category newCategory) async {
    bool shouldMove = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(
              'Change ${NamingUtils.categoriesName(capitalize: false, plural: false)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Move "${task.headline}" to "${newCategory.headline}"?'),
              const SizedBox(height: 16),
              RadioListTile<bool>(
                title: const Text('Move'),
                subtitle: Text('Remove from "${_selectedCategory!.headline}"'),
                value: true,
                groupValue: shouldMove,
                onChanged: (v) => setDlgState(() => shouldMove = v ?? true),
              ),
              RadioListTile<bool>(
                title: const Text('Copy'),
                subtitle: Text(
                    'Keep in both "${_selectedCategory!.headline}" and "${newCategory.headline}"'),
                value: false,
                groupValue: shouldMove,
                onChanged: (v) => setDlgState(() => shouldMove = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, shouldMove),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    // Close the edit panel
    if (mounted) Navigator.pop(context);

    try {
      if (result) {
        // Move: update category_id
        await supabase
            .from('Tasks')
            .update({'category_id': newCategory.id})
            .eq('id', task.id);
      } else {
        // Copy: insert new row
        final userId = AuthUtils.getCurrentUserId();
        await supabase.from('Tasks').insert({
          'headline': task.headline,
          'notes': task.notes,
          'category_id': newCategory.id,
          'owner_id': userId,
          'finished': false,
          'shared': task.shared,
          'links': task.links ?? [],
          'synopsis': task.synopsis,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }

    // Refresh current view (stay in original category)
    if (mounted) {
      setState(() {
        HomeScreen.needsTaskReload.value = true;
      });
    }
  }

  void _navigateToEditTasks() {
    print(
      'HomeScreen: Navigating to edit category: ${_selectedCategory?.headline}',
    );
    if (!mounted || _selectedCategory == null) {
      print('HomeScreen: Not mounted or no category selected');
      return;
    }

    // Set up the static callback before navigation
    EditCategoryScreen.onEditComplete = () {
      print('HomeScreen: Category edit complete callback received');
      if (mounted) {
        print('HomeScreen: Widget mounted, triggering task reload');
        // Force a rebuild and task reload
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            print('HomeScreen: Post frame callback executing');
            setState(() {
              print('HomeScreen: Setting needsTaskReload to true');
              HomeScreen.needsTaskReload.value = true;
            });
            // The listener will call _handleEditComplete(), no need to call it directly
          } else {
            print('HomeScreen: Widget not mounted in post frame callback');
          }
        });
      } else {
        print('HomeScreen: Widget not mounted, cannot trigger task reload');
      }
    };
    print(
      'HomeScreen: Set static callback for category edit: ${EditCategoryScreen.onEditComplete != null}',
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditCategoryScreen(
          category: _selectedCategory,
          tasksOnly: false, // Changed to false to edit the category
          startInCategoryEditorPanel: true,
        ),
      ),
    ).then((_) {
      // Clear the callback after navigation
      EditCategoryScreen.onEditComplete = null;
      print('HomeScreen: Cleared static callback after category edit');
    });
  }

  Future<void> _checkAndShowWelcomeDialog() async {
    // Show the welcome dialog if it hasn't been shown in this session yet
    if (!_welcomeDialogShown) {
      _showWelcomeDialog();
    }
  }

  void _showWelcomeDialog() {
    if (_welcomeDialogShown) return;

    _welcomeDialogShown = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Welcome to I\'ve Been Meaning To...!',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              content: Text(
                'It can be a pretty empty experience in the beginning, so the first thing you\'ll want is to define some ${NamingUtils.categoriesName()} (like \'Watch a Movie\'), and then some ${NamingUtils.tasksName()} for pursuing them (like \'The Godfather\' or \'Die Hard\')',
                style: const TextStyle(fontSize: 16),
              ),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      flex: 1,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          Navigator.pushNamed(context, '/help');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.yellow[700],
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        child: const Text(
                          'More Info',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          // Navigate to create new category
                          _navigateToNewCategory();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        child: Text(
                          'Create Your First ${NamingUtils.categoriesName(capitalize: true, plural: false)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.visible,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      }
    });
  }

  void _showGuestSignupDialog({String content = 'Your message here'}) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title:
              Text('Add Your Own ${NamingUtils.categoriesName(plural: false)}'),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushNamed(context, '/auth');
              },
              child: const Text('Sign Up'),
            ),
          ],
        );
      },
    );
  }

  void _handleEditComplete() async {
    print('HomeScreen: Handling edit complete');

    // Guard: Skip if already reloading
    if (_isReloading) {
      print(
          'HomeScreen: Reload already in progress, skipping _handleEditComplete');
      return;
    }

    _isReloading = true;
    try {
      // Store the current task ID before reloading
      final currentTaskId = _randomTask?.id;
      final previousSelectedCategory = _selectedCategory;

      // Reload categories first
      print('HomeScreen: Reloading categories...');
      await _loadCategories();
      print('HomeScreen: Categories reloaded');

      // Check if the previously selected category still exists
      if (previousSelectedCategory != null) {
        final categoryStillExists = _categories
            .any((category) => category.id == previousSelectedCategory.id);

        if (!categoryStillExists) {
          print(
              'HomeScreen: Previously selected category was deleted, clearing selection');
          setState(() {
            _selectedCategory = null;
            _randomTask = null;
          });
          return; // Exit early since the category was deleted
        }
      }

      // Then check if we need to reload the task
      if (_selectedCategory != null) {
        // Force a cache refresh by reinitializing with the current category
        final userId = AuthUtils.getCurrentUserId();
        await _cacheManager.initializeWithSavedCategory(
          _selectedCategory!,
          userId,
        );

        // Also force refresh from API to ensure we have the latest data
        await _cacheManager.refreshFromApi();

        // Check if the current task still exists and is valid
        if (currentTaskId != null) {
          final currentTaskStillExists = _cacheManager.currentTasks?.any(
                (task) => task.id == currentTaskId && !task.finished,
              ) ??
              false;

          if (currentTaskStillExists) {
            // Current task still exists - just update it in case it was modified
            final updatedTask = _cacheManager.currentTasks!.firstWhere(
              (task) => task.id == currentTaskId,
            );

            print(
                'HomeScreen: Current task still exists, keeping it displayed');
            if (mounted) {
              setState(() {
                _randomTask = updatedTask;
              });
              // Also refresh the task list view if it's visible
              if (_showTaskListMode) {
                _rebuildTaskListFromCache();
              }
            }
            return; // Don't load a new random task
          } else {
            print(
                'HomeScreen: Current task was deleted or finished, loading new task');
          }
        }

        // Only load a new random task if the current one was deleted/finished or doesn't exist
        await _loadRandomTask(_selectedCategory!);

        if (mounted) {
          print(
            'HomeScreen: New random task loaded: \'${_randomTask?.headline}\'',
          );
        }
      } else {
        print('HomeScreen: No category selected, skipping task load');
      }
    } catch (e) {
      print('HomeScreen: Error handling edit complete: $e');
    } finally {
      _isReloading = false;
    }
  }

  void _handleCategoryEditComplete() async {
    print('HomeScreen: Handling category edit complete');

    // Guard: Skip if already reloading
    if (_isReloading) {
      print(
          'HomeScreen: Reload already in progress, skipping _handleCategoryEditComplete');
      return;
    }

    _isReloading = true;
    try {
      // Store the current task ID before reloading
      final currentTaskId = _randomTask?.id;
      final previousSelectedCategory = _selectedCategory;

      // Reload categories first
      print('HomeScreen: Reloading categories...');
      await _loadCategories();
      print('HomeScreen: Categories reloaded');

      // Check if the previously selected category still exists
      if (previousSelectedCategory != null) {
        final categoryStillExists = _categories
            .any((category) => category.id == previousSelectedCategory.id);

        if (!categoryStillExists) {
          print(
              'HomeScreen: Previously selected category was deleted, clearing selection');
          setState(() {
            _selectedCategory = null;
            _randomTask = null;
          });
          return; // Exit early since the category was deleted
        }
      }

      // Then check if we need to reload the task
      if (_selectedCategory != null) {
        // Force a cache refresh by reinitializing with the current category
        final userId = AuthUtils.getCurrentUserId();
        await _cacheManager.initializeWithSavedCategory(
          _selectedCategory!,
          userId,
        );

        // Also force refresh from API to ensure we have the latest data
        await _cacheManager.refreshFromApi();

        // Check if the current task still exists and is valid
        if (currentTaskId != null) {
          final currentTaskStillExists = _cacheManager.currentTasks?.any(
                (task) => task.id == currentTaskId && !task.finished,
              ) ??
              false;

          if (currentTaskStillExists) {
            // Current task still exists - just update it in case it was modified
            final updatedTask = _cacheManager.currentTasks!.firstWhere(
              (task) => task.id == currentTaskId,
            );

            print(
                'HomeScreen: Current task still exists, keeping it displayed');
            if (mounted) {
              setState(() {
                _randomTask = updatedTask;
              });
              // Also refresh the task list view if it's visible
              if (_showTaskListMode) {
                _rebuildTaskListFromCache();
              }
            }
            return; // Don't load a new random task
          } else {
            print(
                'HomeScreen: Current task was deleted or finished, loading new task');
          }
        }

        // Only load a new random task if the current one was deleted/finished or doesn't exist
        await _loadRandomTask(_selectedCategory!);

        if (mounted) {
          print(
            'HomeScreen: New random task loaded: \'${_randomTask?.headline}\'',
          );
        }
      } else {
        print('HomeScreen: No category selected, skipping task load');
      }
    } catch (e) {
      print('HomeScreen: Error handling category edit complete: $e');
    } finally {
      _isReloading = false;
    }
  }

  /// Fetch synopsis from task links using the SynopsisFetcher utility
  Future<void> _fetchSynopsisFromLinks() async {
    // Skip if already fetching or no task
    if (_isFetchingSynopsis || _randomTask == null) {
      return;
    }

    setState(() {
      _isFetchingSynopsis = true;
    });

    try {
      final result = await SynopsisFetcher.fetchSynopsisForTask(_randomTask!);

      if (result != null && mounted) {
        setState(() {
          _fetchedSynopsis = result.synopsis;
        });
        print('HomeScreen: Synopsis fetched from ${result.source.name}');
      }
    } catch (e) {
      print('HomeScreen: Error fetching synopsis: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingSynopsis = false;
        });
      }
    }
  }

  /// Check if we should fetch synopsis for the current task
  bool _shouldFetchNotes() {
    return _randomTask != null &&
        (_randomTask!.synopsis == null ||
            _randomTask!.synopsis!.trim().isEmpty) &&
        _randomTask!.links != null &&
        _randomTask!.links!.isNotEmpty;
  }

  /// Preprocess notes text for HTML rendering
  /// Converts plain text newlines to HTML <br> tags if text doesn't already contain HTML
  String _preprocessNotesForHtml(String notes) {
    // Check if the text already contains HTML tags
    final hasHtmlTags = RegExp(r'<[^>]+>').hasMatch(notes);

    if (hasHtmlTags) {
      // Already has HTML, return as-is
      return notes;
    }

    // Plain text - convert newlines to <br> tags
    return notes.replaceAll('\n', '<br>');
  }

  @override
  Widget build(BuildContext context) {
    // Check if data was modified after this frame completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dataModified = HomeScreen.checkAndResetDataModified();
      if (dataModified && mounted) {
        print('HomeScreen.build: Data was modified, triggering reload');
        if (_selectedCategory != null) {
          _refreshCacheIfNeeded(forceDatabaseRefresh: true);
        } else {
          print('HomeScreen.build: No category selected, reloading categories');
          _loadCategories();
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('ROUZ'),
        automaticallyImplyLeading: false,
        actions: _buildAppBarActions(),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else if (_error != null)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          _loadCategories();
                          if (_selectedCategory != null) {
                            _loadRandomTask(_selectedCategory!);
                          }
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try Again'),
                      ),
                    ],
                  ),
                )
              else if (_categories.isEmpty)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.info_outline,
                            size: 48, color: Colors.grey),
                        onPressed: () {
                          Navigator.pushNamed(context, '/help');
                        },
                        tooltip: 'Help',
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No ${NamingUtils.categoriesName(plural: true)} available',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AuthUtils.isGuestUser()
                            ? 'Guest users can only view demo data. Sign up/in to create your own ${NamingUtils.categoriesName()}.'
                            : '',
                        style:
                            const TextStyle(fontSize: 14, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      if (AuthUtils.isGuestUser())
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pushNamed(context, '/auth');
                                },
                                icon: const Icon(Icons.login),
                                label: const Text('Sign In'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pushNamed(context, '/auth');
                                },
                                icon: const Icon(Icons.person_add),
                                label: const Text('Sign Up'),
                              ),
                            ),
                          ],
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: _navigateToNewCategory,
                          icon: const Icon(Icons.add),
                          label: Text(
                              'Define ${NamingUtils.categoriesName(plural: false, withArticle: true)} to get started'),
                          style: AppButtons.finalize(),
                        ),
                    ],
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Rouse me to...',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                      TextButton.icon(
                                        icon: const Icon(Icons.add_task, color: Colors.deepPurple),
                                        label: const Text(
                                          'Add Idea',
                                          style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold),
                                        ),
                                        onPressed: () {
                                          if (AuthUtils.isGuestUser()) {
                                            _showGuestSignupDialog(
                                              content:
                                                  'Here\'s where you can add ${NamingUtils.tasksName()} once you\'re logged in. Sign up to create your own ${NamingUtils.categoriesName()} and ${NamingUtils.tasksName()}!',
                                            );
                                            return;
                                          }
                                          _navigateToNewContent();
                                        },
                                      ),
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert),
                                        tooltip: '${NamingUtils.categoriesName(capitalize: true, plural: false)} options',
                                        onSelected: (value) async {
                                          if (AuthUtils.isGuestUser()) {
                                            _showGuestSignupDialog(
                                              content:
                                                  'Here\'s where you can edit ${NamingUtils.categoriesName(plural: false, withArticle: true)} once you\'re logged in. Sign up to create your own ${NamingUtils.categoriesName()} and ${NamingUtils.tasksName()}!',
                                            );
                                            return;
                                          }
                                          switch (value) {
                                            case 'add':
                                              _navigateToNewCategory();
                                            case 'edit':
                                              if (_selectedCategory != null) {
                                                final updated = await showDialog<Category>(
                                                  context: context,
                                                  builder: (_) => EditCategoryDialog(category: _selectedCategory!),
                                                );
                                                if (updated != null) {
                                                  await _loadCategories();
                                                }
                                              }
                                            case 'delete':
                                              if (_selectedCategory != null) _deleteCategory(_selectedCategory!);
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          PopupMenuItem<String>(
                                            value: 'add',
                                            child: ListTile(
                                              leading: const Icon(Icons.add),
                                              title: Text('New ${NamingUtils.categoriesName(capitalize: true, plural: false)}'),
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                          PopupMenuItem<String>(
                                            value: 'edit',
                                            child: ListTile(
                                              leading: const Icon(Icons.edit),
                                              title: Text('Edit ${NamingUtils.categoriesName(capitalize: true, plural: false)}'),
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                          PopupMenuItem<String>(
                                            value: 'delete',
                                            child: ListTile(
                                              leading: const Icon(Icons.delete, color: Colors.red),
                                              title: Text(
                                                'Delete ${NamingUtils.categoriesName(capitalize: true, plural: false)}',
                                                style: const TextStyle(color: Colors.red),
                                              ),
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Flexible(
                                        fit: FlexFit.loose,
                                        child: Text(
                                          _selectedCategory?.headline ??
                                              _categories.first.headline,
                                          style: TextStyle(
                                            fontSize: (Theme.of(context)
                                                        .textTheme
                                                        .bodyLarge
                                                        ?.fontSize ??
                                                    16) +
                                                10,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1A237E),
                                          ),
                                        ),
                                      ),
                                      PopupMenuButton<Category>(
                                        tooltip:
                                            'Choose ${NamingUtils.categoriesName(capitalize: false, plural: false)}',
                                        icon: const Icon(
                                          Icons.arrow_drop_down,
                                          size: 32,
                                        ),
                                        enabled: _categories.length > 1,
                                        onSelected: (category) {
                                          unawaited(_handleCategorySelection(
                                              category));
                                        },
                                        itemBuilder: (context) => _categories
                                            .map(
                                              (category) =>
                                                  PopupMenuItem<Category>(
                                                value: category,
                                                child: Text(category.headline),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ],
                                  ),
                                  if ((_selectedCategory?.invitation ?? '')
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      _selectedCategory!.invitation!,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_selectedCategory != null) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () async {
                                try {
                                  setState(() {
                                    _showTaskListMode = false;
                                    _isLoadingTask = true;
                                    _error = null;
                                  });
                                  if (_randomTask != null) {
                                    await _rejectCurrentTask();
                                  }
                                  if (_selectedCategory != null) {
                                    await _loadRandomTask(_selectedCategory!);
                                  }
                                } catch (e) {
                                  print('Error in Hit Me: $e');
                                  setState(() {
                                    _error = e.toString();
                                    _isLoadingTask = false;
                                  });
                                }
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text(
                                'Hit Me',
                                style: TextStyle(fontSize: 18),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 48),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: () {
                                if (!_showTaskListMode) _toggleTaskListMode();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 48),
                              ),
                              child: const Text(
                                'Show All',
                                style: TextStyle(fontSize: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Debug info (commented out)
                      // Text('Selected Category: ${_selectedCategory!.headline}'),
                      // Text('Loading Task: $_isLoadingTask'),
                      // Text('Random Task: ${_randomTask?.headline ?? "null"}'),
                      // Text('Error: ${_error ?? "none"}'),
                      if (_showTaskListMode)
                        _buildTaskListModeContent()
                      else if (_isLoadingTask ||
                          (_cacheManager.currentCategory?.id !=
                                  _selectedCategory?.id ||
                              _cacheManager.currentTasks == null))
                        const Center(child: CircularProgressIndicator())
                      else if (_randomTask != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 14),
                            SizedBox(
                              width: MediaQuery.of(context).size.width - 32,
                              child: Card(
                                key: ValueKey(
                                  'task_${_randomTask!.id}_${_randomTask!.headline}',
                                ),
                                color: const Color(0xFF4A148C),
                                child: Stack(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        16,
                                        16,
                                        0,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Expanded(
                                                child: GestureDetector(
                                                  onTap: () =>
                                                      _showEditPanel(
                                                    _randomTask!,
                                                  ),
                                                  child: Text(
                                                    _randomTask!.headline,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodyLarge
                                                        ?.copyWith(
                                                          fontSize: 22,
                                                          fontWeight: _randomTask!
                                                                          .suggestibleAt ==
                                                                      null ||
                                                                  !_randomTask!
                                                                      .suggestibleAt!
                                                                      .isAfter(
                                                                    DateTime
                                                                        .now(),
                                                                  )
                                                              ? FontWeight.bold
                                                              : FontWeight
                                                                  .normal,
                                                          color: _randomTask!
                                                                          .suggestibleAt !=
                                                                      null &&
                                                                  _randomTask!
                                                                      .suggestibleAt!
                                                                      .isAfter(
                                                                    DateTime
                                                                        .now(),
                                                                  )
                                                              ? Colors.white70
                                                              : Colors.white,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                              if (!AuthUtils.isGuestUser()) ...[
                                                PopupMenuButton<String>(
                                                  icon: const Icon(Icons.more_vert, size: 20, color: Colors.white),
                                                  padding: EdgeInsets.zero,
                                                  onSelected: (value) {
                                                    switch (value) {
                                                      case 'edit':
                                                        _showEditPanel(_randomTask!);
                                                      case 'delete':
                                                        _deleteTaskFromList(_randomTask!);
                                                    }
                                                  },
                                                  itemBuilder: (_) => [
                                                    const PopupMenuItem<String>(
                                                      value: 'edit',
                                                      child: ListTile(
                                                        leading: Icon(Icons.edit),
                                                        title: Text('Edit'),
                                                        contentPadding: EdgeInsets.zero,
                                                      ),
                                                    ),
                                                    const PopupMenuItem<String>(
                                                      value: 'delete',
                                                      child: ListTile(
                                                        leading: Icon(Icons.delete, color: Colors.red),
                                                        title: Text('Delete', style: TextStyle(color: Colors.red)),
                                                        contentPadding: EdgeInsets.zero,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                          if (_randomTask!.finished) ...[
                                            const SizedBox(width: 8),
                                            const Icon(
                                              Icons.check_circle,
                                              color: Colors.green,
                                              size: 28,
                                            ),
                                          ],
                                          // Show notes if they exist (user-entered content)
                                          if (_randomTask!.notes != null &&
                                              _randomTask!
                                                  .notes!.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Html(
                                              data: _preprocessNotesForHtml(
                                                  _randomTask!.notes!),
                                              style: {
                                                "body": Style(
                                                  fontSize: FontSize(
                                                    Theme.of(context)
                                                            .textTheme
                                                            .bodyMedium
                                                            ?.fontSize ??
                                                        14,
                                                  ),
                                                  color: _randomTask!
                                                                  .suggestibleAt !=
                                                              null &&
                                                          _randomTask!
                                                              .suggestibleAt!
                                                              .isAfter(DateTime
                                                                  .now())
                                                      ? Colors.white70
                                                      : Colors.white,
                                                  margin: Margins.zero,
                                                  padding: HtmlPaddings.zero,
                                                ),
                                                "a": Style(
                                                  color: Colors.white,
                                                  textDecoration:
                                                      TextDecoration.underline,
                                                ),
                                              },
                                              onLinkTap: (url, htmlContext,
                                                  attributes) async {
                                                if (url != null) {
                                                  try {
                                                    final uri = Uri.parse(url);
                                                    if (await canLaunchUrl(
                                                        uri)) {
                                                      await launchUrl(uri,
                                                          mode: LaunchMode
                                                              .externalApplication);
                                                    }
                                                  } catch (e) {
                                                    // Error handling without verbose logging
                                                  }
                                                }
                                              },
                                            ),
                                          ],
                                          // Show synopsis if it exists (auto-fetched or stored)
                                          if ((_randomTask!.synopsis != null &&
                                                  _randomTask!
                                                      .synopsis!.isNotEmpty) ||
                                              (_fetchedSynopsis != null &&
                                                  _fetchedSynopsis!
                                                      .isNotEmpty)) ...[
                                            const SizedBox(height: 8),
                                            Html(
                                              data: _fetchedSynopsis ??
                                                  _randomTask!.synopsis ??
                                                  '',
                                              style: {
                                                "body": Style(
                                                  fontSize: FontSize(
                                                    Theme.of(context)
                                                            .textTheme
                                                            .bodyMedium
                                                            ?.fontSize ??
                                                        14,
                                                  ),
                                                  fontStyle: FontStyle.italic,
                                                  color: _randomTask!
                                                                  .suggestibleAt !=
                                                              null &&
                                                          _randomTask!
                                                              .suggestibleAt!
                                                              .isAfter(DateTime
                                                                  .now())
                                                      ? Colors.white70
                                                      : Colors.white,
                                                  margin: Margins.zero,
                                                  padding: HtmlPaddings.zero,
                                                ),
                                                "a": Style(
                                                  color: Colors.white,
                                                  textDecoration:
                                                      TextDecoration.underline,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              },
                                              onLinkTap: (url, htmlContext,
                                                  attributes) async {
                                                if (url != null) {
                                                  try {
                                                    final uri = Uri.parse(url);
                                                    if (await canLaunchUrl(
                                                        uri)) {
                                                      await launchUrl(uri,
                                                          mode: LaunchMode
                                                              .externalApplication);
                                                    }
                                                  } catch (e) {
                                                    // Error handling without verbose logging
                                                  }
                                                }
                                              },
                                            ),
                                          ],
                                          // Show loading indicator if fetching synopsis
                                          if (_isFetchingSynopsis) ...[
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'Fetching description...',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        fontStyle:
                                                            FontStyle.italic,
                                                        color: Colors.white70,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ],
                                          if (_randomTask!.links != null &&
                                              _randomTask!
                                                  .links!.isNotEmpty) ...[
                                            /* if (_randomTask!.notes != null)
                                            const SizedBox(height: 16)
                                          else
                                           */
                                            const SizedBox(height: 14),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: _randomTask!.links!
                                                  .map((link) => Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                                bottom: 4),
                                                        child:
                                                            LinkDisplayWidget(
                                                          linkText: link,
                                                          showIcon: true,
                                                          showTitle: true,
                                                        ),
                                                      ))
                                                  .toList(),
                                            ),
                                          ],
                                          if (_randomTask!.triggersAt !=
                                              null) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              'Triggers at: ${_randomTask!.triggersAt!.toLocal().toString().split('.')[0]}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Colors.white70,
                                                  ),
                                            ),
                                          ],
                                          if (_randomTask!.suggestibleAt !=
                                                  null &&
                                              _randomTask!.suggestibleAt!
                                                  .isAfter(
                                                DateTime.now(),
                                              )) ...[
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    _randomTask!
                                                        .getSuggestibleTimeDisplay()!,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: Colors
                                                              .lightBlueAccent,
                                                        ),
                                                  ),
                                                ),
                                                TextButton.icon(
                                                  onPressed: () async {
                                                    await _reviveCurrentTask();
                                                  },
                                                  icon: const Icon(
                                                    Icons.refresh,
                                                    size: 16,
                                                  ),
                                                  label: const Text('Revive'),
                                                  style: TextButton.styleFrom(
                                                    foregroundColor:
                                                        Colors.lightBlueAccent,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 8,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                          const SizedBox(height: 2),
                                          Center(
                                            child: TextButton.icon(
                                              onPressed: _finishCurrentTask,
                                              icon: const Icon(Icons.check),
                                              label: const Text(
                                                'Actually, I\'m done with this',
                                              ),
                                              style: TextButton.styleFrom(
                                                foregroundColor: Colors.white,
                                                padding: EdgeInsets.zero,
                                                visualDensity:
                                                    VisualDensity.compact,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (Task.currentTaskSet != null) ...[
                              Text(
                                '${Task.currentTaskSet!.length} more tasks in this category',
                                style: Theme.of(context).textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                            ],
                          ],
                        )
                      else
                        const Center(
                          child: Text(
                            'All out of ideas!',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                    ],
                  ],
                ),
              // Guest mode indicator
              if (AuthUtils.isGuestUser()) ...[
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.orange.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange[700],
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'You\'re in guest mode, so you can play with demo data. Sign up/in for full access to making your own ${NamingUtils.categoriesName()} and ${NamingUtils.tasksName()}.',
                              style: TextStyle(
                                color: Colors.orange[700],
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pushNamed(context, '/auth');
                          },
                          icon: const Icon(Icons.login, size: 18),
                          label: const Text('Sign Up / Sign In'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange[700],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_selectedCategory != null && !AuthUtils.isGuestUser()) ...[
              // Info and Share buttons commented out for simplified interface
              // FloatingActionButton(
              //   onPressed: () => _showCategoryInfo(_selectedCategory!),
              //   tooltip: 'Show category information',
              //   backgroundColor: Colors.orange[600],
              //   foregroundColor: Colors.white,
              //   child: const Icon(Icons.info_outline),
              // ),
              // const SizedBox(width: 16),
              // FloatingActionButton(
              //   onPressed: () => _shareCategory(_selectedCategory!),
              //   tooltip: 'Share category',
              //   backgroundColor: Colors.green[600],
              //   foregroundColor: Colors.white,
              //   child: const Icon(Icons.share),
              // ),
              // const SizedBox(width: 16),
            ],
          ],
        ),
      ),
    );
  }
}
