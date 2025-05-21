import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'dart:math';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:meaning_to/utils/link_processor.dart';

final supabase = Supabase.instance.client;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

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
    print('HomeScreen initState called');
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

  Future<void> _loadRandomTask(Category category) async {
    try {
      setState(() {
        _isLoadingTask = true;
        _error = null;
      });

      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('No user logged in');
      }

      final task = await Task.loadRandomTask(category, userId);
      
      setState(() {
        _randomTask = task;
        _isLoadingTask = false;
      });
    } catch (e) {
      print('Error loading random task: $e');
      setState(() {
        _error = e.toString();
        _isLoadingTask = false;
      });
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
    final result = await Navigator.pushNamed(
      context,
      '/edit-category',
      arguments: {'category': category},
    );

    if (result == true) {
      // Reload categories if changes were made
      _loadCategories();
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
                                            onPressed: () {
                                              Navigator.pushNamed(
                                                context,
                                                '/edit-task',
                                                arguments: {
                                                  'category': _selectedCategory!,
                                                  'task': _randomTask!,
                                                },
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                      if (_randomTask!.notes != null) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          _randomTask!.notes!,
                                          style: Theme.of(context).textTheme.bodyMedium,
                                        ),
                                      ],
                                      if (_randomTask!.links != null && _randomTask!.links!.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        LinkProcessor.processAndDisplayLinks(_randomTask!.links!),
                                      ],
                                      if (_randomTask!.triggersAt != null) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          'Triggers at: ${_randomTask!.triggersAt!.toLocal().toString().split('.')[0]}',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                      if (_randomTask!.suggestibleAt != null) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          'Available again in ${_randomTask!.suggestibleAt!.difference(DateTime.now()).inMinutes} minutes',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Colors.blue,
                                          ),
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
                              onPressed: () {
                                Navigator.pushNamed(
                                  context,
                                  '/edit-category',
                                  arguments: {
                                    'category': _selectedCategory,
                                    'tasksOnly': true,
                                  },
                                );
                              },
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
