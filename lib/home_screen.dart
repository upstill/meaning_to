import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/widgets/link_display.dart';
import 'package:meaning_to/edit_category_screen.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/performance_monitor_screen.dart';
import 'dart:async';

import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/utils/app_buttons.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/deep_link_generator.dart';
import 'package:clipboard/clipboard.dart';

class HomeScreen extends StatefulWidget {
  static final ValueNotifier<bool> needsTaskReload = ValueNotifier<bool>(false);

  final String? initialCategoryId;

  const HomeScreen({super.key, this.initialCategoryId});

  @override
  HomeScreenState createState() => HomeScreenState();

  // Static variable to track if data has been modified
  static bool _dataModified = false;

  // Method to mark that data has been modified (call from other screens)
  static void markDataModified() {
    _dataModified = true;
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
  bool _isLoading = true;
  bool _isLoadingTask = false;
  String? _error;

  // CacheManager instance for managing current category and tasks
  final CacheManager _cacheManager = CacheManager();

  // Add getter for selected category
  Category? get selectedCategory => _selectedCategory;

  // Track if welcome dialog has been shown
  bool _welcomeDialogShown = false;

  @override
  void initState() {
    super.initState();
    print('HomeScreen: initState called');
    // Listen for task reload requests
    HomeScreen.needsTaskReload.addListener(_handleTaskReloadRequest);

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
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh cache when dependencies change (e.g., when returning from other screens)
    if (_selectedCategory != null) {
      // Check if data was modified by other screens
      final dataModified = HomeScreen.checkAndResetDataModified();
      _refreshCacheIfNeeded(forceDatabaseRefresh: dataModified);
    }
  }

  /// Smart refresh that can skip database calls when appropriate
  Future<void> _refreshCacheIfNeeded(
      {bool forceDatabaseRefresh = false}) async {
    final cacheManager = CacheManager();

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

      // Reload the random task with refreshed data
      await _loadRandomTask(_selectedCategory!);
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
        });
        print('HomeScreen: State updated with new task');
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

        // Select initial category if one was provided
        _selectInitialCategory();

        // Show welcome dialog for new authenticated users with no categories
        if (!AuthUtils.isGuestUser() &&
            categories.isEmpty &&
            !_welcomeDialogShown) {
          _showWelcomeDialog();
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

  void _navigateToNewCategory() {
    print('HomeScreen: Starting navigation to new category screen...');

    if (!mounted) {
      print('HomeScreen: Not mounted before navigation');
      return;
    }

    Navigator.pushNamed(context, '/new-category').then((result) {
      // If we got a result (true), reload categories
      if (result == true) {
        print('HomeScreen: Category was created, reloading categories');
        _loadCategories();
      }
    });
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
            print('HomeScreen: Directly calling _handleEditComplete');
            _handleEditComplete();
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

  void _navigateToEditTask(Task task) {
    print('HomeScreen: Navigating to edit task: ${task.headline}');
    if (!mounted || _selectedCategory == null) {
      print('HomeScreen: Not mounted or no category selected');
      return;
    }

    // Set up the static callback before navigation
    TaskEditScreen.onEditComplete = () {
      print('HomeScreen: Task edit complete callback received');
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
            print('HomeScreen: Directly calling _handleEditComplete');
            _handleEditComplete();
          } else {
            print('HomeScreen: Widget not mounted in post frame callback');
          }
        });
      } else {
        print('HomeScreen: Widget not mounted, cannot trigger task reload');
      }
    };
    print(
      'HomeScreen: Set static callback for task edit: ${TaskEditScreen.onEditComplete != null}',
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            TaskEditScreen(category: _selectedCategory!, task: task),
      ),
    ).then((_) {
      // Clear the callback after navigation
      TaskEditScreen.onEditComplete = null;
      print('HomeScreen: Cleared static callback after task edit');
    });
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
            print('HomeScreen: Directly calling _handleCategoryEditComplete');
            _handleCategoryEditComplete();
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
        ),
      ),
    ).then((_) {
      // Clear the callback after navigation
      EditCategoryScreen.onEditComplete = null;
      print('HomeScreen: Cleared static callback after category edit');
    });
  }

  void _showWelcomeDialog() {
    if (_welcomeDialogShown) return;

    _welcomeDialogShown = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text(
                'Welcome to \'I\'ve Been Meaning To\'!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: const Text(
                'It\'ll be a pretty empty experience in the beginning, so the first thing you\'ll want is to define some Pursuits.',
                style: TextStyle(fontSize: 16),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Navigate to create new category
                    _navigateToNewCategory();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    'Create Your First Pursuit',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
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
    try {
      // Store the current selected category before reloading
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

      // Then reload task if we have a selected category
      if (_selectedCategory != null) {
        print('HomeScreen: Loading new random task after category edit...');

        // Force a cache refresh by reinitializing with the current category
        final userId = AuthUtils.getCurrentUserId();
        await _cacheManager.initializeWithSavedCategory(
          _selectedCategory!,
          userId,
        );

        // Also force refresh from API to ensure we have the latest data
        await _cacheManager.refreshFromApi();

        // Always load a new random task when returning from Edit Category screen
        // since the category or its tasks might have been modified
        await _loadRandomTask(_selectedCategory!);

        if (mounted) {
          print(
            'HomeScreen: New random task loaded: \'${_randomTask?.headline}\'',
          );
          print('HomeScreen: Task finished state: ${_randomTask?.finished}');
          print(
            'HomeScreen: Task suggestible at: ${_randomTask?.suggestibleAt}',
          );
        }
      } else {
        print('HomeScreen: No category selected, skipping task load');
      }
    } catch (e) {
      print('HomeScreen: Error handling edit complete: $e');
    }
  }

  void _handleCategoryEditComplete() async {
    print('HomeScreen: Handling category edit complete');
    try {
      // Store the current selected category before reloading
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

      // Then load a new random task if we have a selected category
      if (_selectedCategory != null) {
        print('HomeScreen: Loading new random task after category edit...');

        // Force a cache refresh by reinitializing with the current category
        final userId = AuthUtils.getCurrentUserId();
        await _cacheManager.initializeWithSavedCategory(
          _selectedCategory!,
          userId,
        );

        // Also force refresh from API to ensure we have the latest data
        await _cacheManager.refreshFromApi();

        // Always load a new random task when returning from Edit Category screen
        // since the category or its tasks might have been modified
        await _loadRandomTask(_selectedCategory!);

        if (mounted) {
          print(
            'HomeScreen: New random task loaded: \'${_randomTask?.headline}\'',
          );
          print('HomeScreen: Task finished state: ${_randomTask?.finished}');
          print(
            'HomeScreen: Task suggestible at: ${_randomTask?.suggestibleAt}',
          );
        }
      } else {
        print('HomeScreen: No category selected, skipping task load');
      }
    } catch (e) {
      print('HomeScreen: Error handling category edit complete: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('I\'ve Been Meaning To...'),
        automaticallyImplyLeading: false,
        actions: [
          // Debug button - only show in debug mode
          if (foundation.kDebugMode)
            IconButton(
              icon: const Icon(Icons.analytics),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PerformanceMonitorScreen(),
                  ),
                );
              },
              tooltip: 'Performance Monitor',
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthUtils.signOut();
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/');
              }
            },
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
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
                    const Icon(Icons.info_outline,
                        size: 48, color: Colors.grey),
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
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
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
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<Category>(
                          value: _selectedCategory,
                          // Must be >= kMinInteractiveDimension (48)
                          itemHeight: 48.0,
                          isExpanded: true,
                          style: const TextStyle(
                              fontSize:
                                  20), // Increased by 8 points from default 12
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            hintText:
                                'Choose ${NamingUtils.categoriesName(capitalize: false, plural: false, withArticle: true)}',
                            isDense: false,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 12,
                            ),
                          ),
                          selectedItemBuilder: (context) => _categories
                              .map((category) => Text(
                                    '...${category.headline}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      height: 1.0,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1A237E),
                                    ),
                                  ))
                              .toList(),
                          items: _categories.map((category) {
                            return DropdownMenuItem(
                              value: category,
                              child: Text(
                                '...${category.headline}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  height: 0.95,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A237E),
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (Category? newValue) async {
                            setState(() {
                              _selectedCategory = newValue;
                              _randomTask = null; // Clear the current task
                            });
                            if (newValue != null) {
                              // Update last_access timestamp when category is selected
                              await _updateCategoryLastAccess(newValue);
                              _loadRandomTask(newValue);
                            }
                          },
                        ),
                      ),
                      // Info, Share, and Edit buttons moved to bottom right
                    ],
                  ),
                  if (_selectedCategory != null) ...[
                    const SizedBox(height: 12),
                    // Debug info (commented out)
                    // Text('Selected Category: ${_selectedCategory!.headline}'),
                    // Text('Loading Task: $_isLoadingTask'),
                    // Text('Random Task: ${_randomTask?.headline ?? "null"}'),
                    // Text('Error: ${_error ?? "none"}'),
                    if (_isLoadingTask)
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
                                                    _navigateToEditTask(
                                                  _randomTask!,
                                                ),
                                                child: Text(
                                                  _randomTask!.headline,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyLarge
                                                      ?.copyWith(
                                                        fontSize: (Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .bodyLarge
                                                                    ?.fontSize ??
                                                                16) +
                                                            10,
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
                                                            : FontWeight.normal,
                                                        color: _randomTask!
                                                                        .suggestibleAt !=
                                                                    null &&
                                                                _randomTask!
                                                                    .suggestibleAt!
                                                                    .isAfter(
                                                                  DateTime
                                                                      .now(),
                                                                )
                                                            ? Colors.grey
                                                            : null,
                                                      ),
                                                ),
                                              ),
                                            ),
                                            if (!AuthUtils.isGuestUser()) ...[
                                              const SizedBox(width: 8),
                                              GestureDetector(
                                                onTap: () =>
                                                    _navigateToEditTask(
                                                  _randomTask!,
                                                ),
                                                child: Icon(
                                                  Icons.edit,
                                                  size: 20,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                ),
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
                                        if (_randomTask!.notes != null &&
                                            _randomTask!.notes!.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text.rich(
                                            textAlign: TextAlign.left,
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: _randomTask!.notes!,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        color: _randomTask!
                                                                        .suggestibleAt !=
                                                                    null &&
                                                                _randomTask!
                                                                    .suggestibleAt!
                                                                    .isAfter(
                                                                  DateTime
                                                                      .now(),
                                                                )
                                                            ? Colors.grey
                                                            : null,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        if (_randomTask!.links != null &&
                                            _randomTask!.links!.isNotEmpty) ...[
                                          /* if (_randomTask!.notes != null)
                                            const SizedBox(height: 16)
                                          else
                                           */
                                          const SizedBox(height: 14),
                                          LinkListDisplay(
                                            links: _randomTask!.links!,
                                            showIcon: true,
                                            showTitle: true,
                                          ),
                                        ],
                                        if (_randomTask!.triggersAt !=
                                            null) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            'Triggers at: ${_randomTask!.triggersAt!.toLocal().toString().split('.')[0]}',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ],
                                        if (_randomTask!.suggestibleAt !=
                                                null &&
                                            _randomTask!.suggestibleAt!.isAfter(
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
                                                        color: Colors.blue,
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
                                                  foregroundColor: Colors.blue,
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
                                              foregroundColor: Theme.of(
                                                context,
                                              ).colorScheme.primary,
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
                          const SizedBox(height: 20),
                          Center(
                            child: Column(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    try {
                                      setState(() {
                                        _isLoadingTask = true;
                                        _error = null;
                                      });

                                      // First reject the current task
                                      await _rejectCurrentTask();

                                      // Then load a new random task
                                      if (_selectedCategory != null) {
                                        await _loadRandomTask(
                                          _selectedCategory!,
                                        );
                                      }
                                    } catch (e) {
                                      print('Error in Hit Me Again: $e');
                                      setState(() {
                                        _error = e.toString();
                                        _isLoadingTask = false;
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text(
                                    'Hit Me Again',
                                    style: TextStyle(fontSize: 18),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(
                                        0, 48), // 12 points taller than default
                                  ),
                                ),
                                const SizedBox(height: 20),
                                // Removed "Manage Choices..." button since we now have a persistent Edit button above
                              ],
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
                      Center(
                        child: Column(
                          children: [
                            const Text(
                              'All out of ideas!',
                              style: TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _navigateToEditTasks,
                              icon: const Icon(Icons.edit),
                              label: Text(
                                  'Manage Choices/Edit ${NamingUtils.categoriesName(plural: false)}'),
                              style: AppButtons.goForth(),
                            ),
                          ],
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
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.orange[700],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'You\'re in guest mode. You can view and modify demo data. Sign up/in to create your own ${NamingUtils.categoriesName()} and ${NamingUtils.tasksName()}.',
                        style: TextStyle(
                          color: Colors.orange[700],
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
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
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_selectedCategory != null) ...[
            FloatingActionButton(
              onPressed: () => _showCategoryInfo(_selectedCategory!),
              tooltip: 'Show category information',
              backgroundColor: Colors.orange[600],
              foregroundColor: Colors.white,
              child: const Icon(Icons.info_outline),
            ),
            const SizedBox(width: 16),
            FloatingActionButton(
              onPressed: () => _shareCategory(_selectedCategory!),
              tooltip: 'Share category',
              backgroundColor: Colors.green[600],
              foregroundColor: Colors.white,
              child: const Icon(Icons.share),
            ),
            const SizedBox(width: 16),
            FloatingActionButton(
              onPressed: () => _navigateToEditTasks(),
              tooltip: 'Edit category',
              backgroundColor: Colors.blue[600],
              foregroundColor: Colors.white,
              child: const Icon(Icons.edit),
            ),
            const SizedBox(width: 16),
          ],
          FloatingActionButton(
            onPressed: () {
              if (AuthUtils.isGuestUser()) {
                _showGuestSignupDialog(
                    content:
                        'Here\'s where you can add a new ${NamingUtils.categoriesName(plural: false)} once you\'re logged in. Sign up to add your own ${NamingUtils.categoriesName()} and ${NamingUtils.tasksName()}!');
              } else {
                _navigateToNewCategory();
              }
            },
            tooltip:
                'Define a New ${NamingUtils.categoriesName(capitalize: false, plural: false)}',
            backgroundColor: AppButtons.goForthBg,
            foregroundColor: AppButtons.goForthFg,
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
