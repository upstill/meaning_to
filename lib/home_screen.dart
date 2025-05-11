import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'dart:math';

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

      final task = await Task.nextTask(category, userId);
      
      setState(() {
        _randomTask = task;
        _isLoadingTask = false;
      });
    } catch (e, stackTrace) {
      print('Error loading random task: $e');
      print('Stack trace: $stackTrace');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('I\'ve been meaning to...'),
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
                  const Text(
                    'Select a Category',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<Category>(
                    value: _selectedCategory,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    hint: const Text('Choose a category'),
                    items: _categories.map((category) {
                      return DropdownMenuItem(
                        value: category,
                        child: Text(category.headline),
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
                          Text(
                            _selectedCategory!.headline,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          if (_selectedCategory!.invitation != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _selectedCategory!.invitation!,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                          const SizedBox(height: 24),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Here\'s something you\'ve been meaning to do:',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _randomTask!.headline,  // Changed from description to headline
                                    style: Theme.of(context).textTheme.bodyLarge,
                                  ),
                                  if (_randomTask!.notes != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      _randomTask!.notes!,
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                  ],
                                  if (_randomTask!.triggersAt != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Triggers at: ${_randomTask!.triggersAt!.toLocal().toString().split('.')[0]}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: ElevatedButton.icon(
                              onPressed: () => _loadRandomTask(_selectedCategory!),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Show Another Task'),
                            ),
                          ),
                        ],
                      )
                    else
                      Center(
                        child: Column(
                          children: [
                            const Text(
                              'No tasks found for this category.',
                              style: TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                // TODO: Implement task creation
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Add a Task'),
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
        onPressed: () {
          // TODO: Implement category creation
        },
        child: const Icon(Icons.add),
        tooltip: 'Create new category',
      ),
    );
  }
}
