import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/auth.dart';
import 'dart:math';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/edit_category_screen.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/widgets/link_display.dart';
import 'package:meaning_to/app.dart';
import 'package:meaning_to/utils/supabase_client.dart';

class HomeScreen extends StatefulWidget {
  static final ValueNotifier<bool> needsTaskReload = ValueNotifier<bool>(false);

  const HomeScreen({super.key});

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
        await cacheManager.refreshFromDatabase();
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
  bool _shouldRefreshFromDatabase() {
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

  Future<void> _loadCategories() async {
    try {
      print('Starting to load categories...');
      final session = supabase.auth.currentSession;
      print('Session in _loadCategories: ${session?.user.id}');

      // Check if user is authenticated or is a guest
      final currentUser = AuthUtils.getCurrentUser();
      final isGuest = AuthUtils.isGuestUser();

      print('Current user: ${currentUser?.id ?? 'null'}');
      print('Is guest: $isGuest');

      if (session == null && !isGuest) {
        print('No session found and not guest, redirecting to auth');
        if (mounted) {
          Navigator.pushNamed(context, '/auth');
        }
        return;
      }

      // For guest users, we'll load categories using the guest user ID
      if (isGuest) {
        print('Guest user detected, loading categories for guest user');
        final guestUserId = AuthUtils.getCurrentUserId();
        print('Guest user ID: $guestUserId');

        try {
          final response = await supabase
              .from('Categories')
              .select()
              .eq('owner_id', guestUserId)
              .order('created_at', ascending: false);
          print('Guest categories response: $response');

          if (response == null) {
            print('Guest categories response is null');
            setState(() {
              _categories = [];
              _isLoading = false;
            });
            return;
          }

          if (response is! List) {
            print(
                'Guest categories response is not a List: ${response.runtimeType}');
            setState(() {
              _categories = [];
              _isLoading = false;
            });
            return;
          }

          final categories = response
              .map((json) => Category.fromJson(json as Map<String, dynamic>))
              .toList();
          print('Parsed ${categories.length} guest categories');

          setState(() {
            _categories = categories;
            _isLoading = false;
          });
          print('Guest categories loaded successfully');
        } catch (e) {
          print('Error loading guest categories: $e');
          setState(() {
            _categories = [];
            _isLoading = false;
          });
        }
        return;
      }

      print('Fetching categories from Supabase...');
      // At this point, we know we have a session (not a guest user)
      final response = await supabase
          .from('Categories')
          .select()
          .eq('owner_id', session!.user.id)
          .order('created_at', ascending: false);
      print('Supabase response: $response');

      if (response == null) {
        print('Response is null');
        setState(() {
          _categories = [];
          _isLoading = false;
        });
        return;
      }

      if (response is! List) {
        print('Response is not a List: ${response.runtimeType}');
        throw Exception('Invalid response format from Supabase');
      }

      final categories = response
          .map((json) => Category.fromJson(json as Map<String, dynamic>))
          .toList();
      print('Parsed ${categories.length} categories');

      setState(() {
        _categories = categories;
        _isLoading = false;
      });
      print('Categories loaded successfully');
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

  void _handleEditComplete() async {
    print('HomeScreen: Handling edit complete');
    try {
      // Reload categories first
      print('HomeScreen: Reloading categories...');
      await _loadCategories();
      print('HomeScreen: Categories reloaded');

      // Then reload task if we have a selected category
      if (_selectedCategory != null) {
        print('HomeScreen: Loading new random task after category edit...');

        // Force a cache refresh by reinitializing with the current category
        final userId = AuthUtils.getCurrentUserId();
        if (userId != null) {
          await _cacheManager.initializeWithSavedCategory(
            _selectedCategory!,
            userId,
          );

          // Also force refresh from database to ensure we have the latest data
          await _cacheManager.refreshFromDatabase();
        }

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
      // Reload categories first
      print('HomeScreen: Reloading categories...');
      await _loadCategories();
      print('HomeScreen: Categories reloaded');

      // Then load a new random task if we have a selected category
      if (_selectedCategory != null) {
        print('HomeScreen: Loading new random task after category edit...');

        // Force a cache refresh by reinitializing with the current category
        final userId = AuthUtils.getCurrentUserId();
        if (userId != null) {
          await _cacheManager.initializeWithSavedCategory(
            _selectedCategory!,
            userId,
          );

          // Also force refresh from database to ensure we have the latest data
          await _cacheManager.refreshFromDatabase();
        }

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
        title: const Text(''), // Blank header
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () {
              _forceRefreshAndVerify();
            },
            tooltip: 'Debug: Force Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadCategories();
              if (_selectedCategory != null) {
                _loadRandomTask(_selectedCategory!);
              }
            },
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await supabase.auth.signOut();
              if (mounted) {
                Navigator.pushNamed(context, '/auth');
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
              const Center(
                child: Text(
                  'No categories yet. Create one to get started!',
                  style: TextStyle(fontSize: 16),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Text(
                      'I\'ve been meaning to...?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A237E),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<Category>(
                    value: _selectedCategory,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    hint: const Text(
                      'Choose an endeavor',
                      style: TextStyle(fontSize: 20),
                    ),
                    items: _categories.map((category) {
                      return DropdownMenuItem(
                        value: category,
                        child: Text(
                          category.headline,
                          style: const TextStyle(fontSize: 20),
                        ),
                      );
                    }).toList(),
                    onChanged: (Category? newValue) {
                      setState(() {
                        _selectedCategory = newValue;
                        _randomTask = null; // Clear the current task
                      });
                      if (newValue != null) {
                        _loadRandomTask(newValue);
                      }
                    },
                  ),
                  if (_selectedCategory != null) ...[
                    const SizedBox(height: 24),
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
                                                            6,
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
                                            const SizedBox(width: 8),
                                            GestureDetector(
                                              onTap: () => _navigateToEditTask(
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
                                        ),
                                        if (_randomTask!.finished) ...[
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.check_circle,
                                            color: Colors.green,
                                            size: 28,
                                          ),
                                        ],
                                        if (_randomTask!.notes != null) ...[
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
                                          const SizedBox(height: 16),
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
                          const SizedBox(height: 16),
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
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: _navigateToEditTasks,
                                  child: const Text('Manage Choices'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
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
                              label: const Text('Manage Choices'),
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
                        'You\'re in guest mode to check out the app. Changes you make might not be persistent.',
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
      floatingActionButton: !AuthUtils.isGuestUser()
          ? FloatingActionButton(
              onPressed: () => _navigateToNewCategory(),
              child: const Icon(Icons.add),
              tooltip: 'Create new endeavor',
            )
          : null,
    );
  }
}
