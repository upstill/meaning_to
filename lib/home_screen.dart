import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'dart:math';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/edit_category_screen.dart';
import 'package:meaning_to/task_edit_screen.dart';

final supabase = Supabase.instance.client;

class HomeScreen extends StatefulWidget {
  static final GlobalKey<_HomeScreenState> globalKey = GlobalKey<_HomeScreenState>();
  static final ValueNotifier<bool> needsTaskReload = ValueNotifier<bool>(false);
  
  HomeScreen() : super(key: globalKey);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Category> _categories = [];
  Category? _selectedCategory;
  Task? _randomTask;
  bool _isLoading = true;
  bool _isLoadingTask = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    print('HomeScreen: initState called');
    // Listen for task reload requests
    HomeScreen.needsTaskReload.addListener(_handleTaskReloadRequest);
    final session = supabase.auth.currentSession;
    print('Current session: ${session?.user.id}');
    if (session == null) {
      print('No session found, navigating to auth screen');
      Navigator.pushNamed(context, '/auth');
    } else {
      print('Session found, loading categories');
      _loadCategories();
    }
  }

  @override
  void dispose() {
    HomeScreen.needsTaskReload.removeListener(_handleTaskReloadRequest);
    super.dispose();
  }

  void _handleTaskReloadRequest() {
    print('HomeScreen: Task reload requested');
    if (HomeScreen.needsTaskReload.value && mounted) {
      print('HomeScreen: Handling task reload request');
      print('HomeScreen: Current category: ${_selectedCategory?.headline}');
      print('HomeScreen: Current task: ${_randomTask?.headline}');
      
      HomeScreen.needsTaskReload.value = false;  // Reset the flag
      _handleEditComplete();
    } else {
      print('HomeScreen: Task reload requested but widget not mounted or flag not set');
      print('HomeScreen: mounted: $mounted, needsTaskReload: ${HomeScreen.needsTaskReload.value}');
    }
  }

  Future<void> _loadRandomTask(Category category) async {
    print('HomeScreen: Starting to load random task for category: ${category.headline}');
    try {
      setState(() {
        _isLoadingTask = true;
        _error = null;
      });

      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('No user logged in');
      }

      print('HomeScreen: Calling Task.loadRandomTask...');
      final task = await Task.loadRandomTask(category, userId);
      print('HomeScreen: Task loaded: ${task?.headline}');
      
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

      await Task.rejectCurrentTask();
      
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

      await Task.finishCurrentTask();
      
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

  Future<void> _loadCategories() async {
    try {
      print('Starting to load categories...');
      final session = supabase.auth.currentSession;
      print('Session in _loadCategories: ${session?.user.id}');
      
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final userId = supabase.auth.currentUser?.id;
      print('Current user ID: $userId');
      if (userId == null) {
        throw Exception('No user logged in');
      }

      print('Fetching categories from Supabase...');
      final response = await supabase
          .from('Categories')
          .select()
          .eq('owner_id', userId)
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
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _navigateToEditCategory([Category? category]) async {
    print('HomeScreen: Starting navigation to edit category screen...');
    print('HomeScreen: Current category: ${_selectedCategory?.headline}');
    print('HomeScreen: Current task: ${_randomTask?.headline}');
    
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
    print('HomeScreen: Set static callback: ${EditCategoryScreen.onEditComplete != null}');

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
        MaterialPageRoute(
          builder: (context) => screen,
          fullscreenDialog: true,
        ),
      );
      print('HomeScreen: Returned from edit category screen with result: $result');
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
    print('HomeScreen: Set static callback for task edit: ${TaskEditScreen.onEditComplete != null}');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TaskEditScreen(
          category: _selectedCategory!,
          task: task,
        ),
      ),
    ).then((_) {
      // Clear the callback after navigation
      TaskEditScreen.onEditComplete = null;
      print('HomeScreen: Cleared static callback after task edit');
    });
  }

  void _navigateToEditTasks() {
    print('HomeScreen: Navigating to edit tasks for category: ${_selectedCategory?.headline}');
    if (!mounted || _selectedCategory == null) {
      print('HomeScreen: Not mounted or no category selected');
      return;
    }

    // Set up the static callback before navigation
    EditCategoryScreen.onEditComplete = () {
      print('HomeScreen: Tasks edit complete callback received');
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
    print('HomeScreen: Set static callback for tasks edit: ${EditCategoryScreen.onEditComplete != null}');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditCategoryScreen(
          category: _selectedCategory,
          tasksOnly: true,
        ),
      ),
    ).then((_) {
      // Clear the callback after navigation
      EditCategoryScreen.onEditComplete = null;
      print('HomeScreen: Cleared static callback after tasks edit');
    });
  }

  Future<void> _handleEditComplete() async {
    print('HomeScreen: Handling edit complete...');
    if (!mounted) {
      print('HomeScreen: Not mounted in handleEditComplete');
      return;
    }

    try {
      print('HomeScreen: Reloading categories...');
      await _loadCategories();
      print('HomeScreen: Categories reloaded');
      
      if (!mounted) {
        print('HomeScreen: Not mounted after loading categories');
        return;
      }

      if (_selectedCategory != null) {
        print('HomeScreen: Selected category: ${_selectedCategory!.headline}');
        print('HomeScreen: Current task before reload: ${_randomTask?.headline}');
        
        // Check if we have a current task in the cache
        if (Task.currentTask != null) {
          print('HomeScreen: Found current task in cache: ${Task.currentTask!.headline}');
          // If the current task is from the same category, use it
          if (Task.currentTask!.categoryId == _selectedCategory!.id) {
            print('HomeScreen: Using cached task from same category');
            setState(() {
              _randomTask = Task.currentTask;
              print('HomeScreen: Updated task from cache: ${_randomTask?.headline}');
            });
            return;
          }
        }
        
        // If we don't have a valid cached task, load a new one
        print('HomeScreen: No valid cached task, loading new random task...');
        if (mounted) {
          setState(() {
            _randomTask = null;  // Clear current task
            print('HomeScreen: Cleared current task');
          });
        }
        
        try {
          print('HomeScreen: Loading new random task...');
          await _loadRandomTask(_selectedCategory!);
          if (mounted) {
            print('HomeScreen: New task loaded: ${_randomTask?.headline}');
            print('HomeScreen: Task finished state: ${_randomTask?.finished}');
            print('HomeScreen: Task suggestible at: ${_randomTask?.suggestibleAt}');
          }
        } catch (e) {
          print('HomeScreen: Error loading new task: $e');
          rethrow;
        }
      } else {
        print('HomeScreen: No category selected, skipping task load');
      }
    } catch (e) {
      print('HomeScreen: Error handling edit complete: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(''),  // Blank header
        actions: [
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
                  children: [
                    Text(
                      'Error: $_error',
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        _loadCategories();
                        if (_selectedCategory != null) {
                          _loadRandomTask(_selectedCategory!);
                        }
                      },
                      child: const Text('Try Again'),
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
                        _randomTask = null;  // Clear the current task
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
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minHeight: 172,
                              ),
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            _randomTask!.headline,
                                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                              fontSize: (Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16) + 6,
                                              fontWeight: _randomTask!.suggestibleAt == null || !_randomTask!.suggestibleAt!.isAfter(DateTime.now())
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color: _randomTask!.suggestibleAt != null && _randomTask!.suggestibleAt!.isAfter(DateTime.now())
                                                  ? Colors.grey
                                                  : null,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          if (_randomTask!.finished) ...[
                                            const SizedBox(width: 8),
                                            Icon(Icons.check_circle, color: Colors.green, size: 28),
                                          ],
                                          IconButton(
                                            icon: const Icon(Icons.edit),
                                            tooltip: 'Edit this task',
                                            onPressed: () => _navigateToEditTask(_randomTask!),
                                          ),
                                        ],
                                      ),
                                      if (_randomTask!.notes != null) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          _randomTask!.notes!,
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: _randomTask!.suggestibleAt != null && _randomTask!.suggestibleAt!.isAfter(DateTime.now())
                                                ? Colors.grey
                                                : null,
                                          ),
                                        ),
                                      ],
                                      if (_randomTask!.links != null && _randomTask!.links!.isNotEmpty) ...[
                                        const SizedBox(height: 16),
                                        LinkProcessor.processAndDisplayLinks(_randomTask!.links!),
                                      ],
                                      if (_randomTask!.triggersAt != null) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          'Triggers at: ${_randomTask!.triggersAt!.toLocal().toString().split('.')[0]}',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                      if (_randomTask!.suggestibleAt != null && _randomTask!.suggestibleAt!.isAfter(DateTime.now())) ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _randomTask!.getSuggestibleTimeDisplay()!,
                                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: Colors.blue,
                                                ),
                                              ),
                                            ),
                                            TextButton.icon(
                                              onPressed: () async {
                                                final userId = supabase.auth.currentUser?.id;
                                                if (userId == null) return;
                                                try {
                                                  await Task.reviveTask(_randomTask!, userId);
                                                  setState(() {
                                                    // The task will be updated in the cache
                                                    // and the UI will refresh automatically
                                                  });
                                                } catch (e) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text('Error reviving task: $e'),
                                                      backgroundColor: Colors.red,
                                                    ),
                                                  );
                                                }
                                              },
                                              icon: const Icon(Icons.refresh, size: 16),
                                              label: const Text('Revive'),
                                              style: TextButton.styleFrom(
                                                foregroundColor: Colors.blue,
                                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
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
                                      await Task.rejectCurrentTask();
                                      
                                      // Then load a new random task
                                      if (_selectedCategory != null) {
                                        await _loadRandomTask(_selectedCategory!);
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
                                ElevatedButton.icon(
                                  onPressed: _finishCurrentTask,
                                  icon: const Icon(Icons.check),
                                  label: const Text('Actually, I\'m done with that'),
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
                              label: const Text('Edit the List of Tasks'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToEditCategory(),
        child: const Icon(Icons.add),
        tooltip: 'Create new endeavor',
      ),
    );
  }
}
