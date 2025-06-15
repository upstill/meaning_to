import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:file_selector/file_selector.dart';
import 'dart:convert';
import 'package:meaning_to/widgets/link_display.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:meaning_to/utils/link_processor.dart';
import 'package:http/http.dart' as http;
import 'package:meaning_to/utils/link_extractor.dart';
import 'package:meaning_to/import_justwatch_screen.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/widgets/task_display.dart';

final supabase = Supabase.instance.client;

class EditCategoryScreen extends StatefulWidget {
  static VoidCallback? onEditComplete; // Static callback for edit completion

  final Category? category; // null for new category, existing category for edit
  final bool tasksOnly;

  // Remove onComplete from constructor since we'll use static callback
  EditCategoryScreen({
    super.key,
    this.category,
    this.tasksOnly = false,
  });

  // Add a factory constructor to handle arguments from Navigator
  static Route routeFromArgs(RouteSettings settings) {
    final args = settings.arguments as Map<String, dynamic>?;
    print('EditCategoryScreen: routeFromArgs called');
    return MaterialPageRoute(
      builder: (_) => EditCategoryScreen(
        category: args?['category'] as Category?,
        tasksOnly: args?['tasksOnly'] == true,
      ),
      settings: settings,
    );
  }

  @override
  State<EditCategoryScreen> createState() => _EditCategoryScreenState();
}

class _EditCategoryScreenState extends State<EditCategoryScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _headlineController;
  late TextEditingController _invitationController;
  bool _isLoading = false;
  String? _error;
  List<Task> _tasks = [];
  bool _isLoadingTasks = false;
  late bool _editTasksLocal;
  bool _isEditing = false; // New state to track edit mode
  List<Task> _newTasks = []; // Temporary list for tasks in new categories

  @override
  void initState() {
    super.initState();
    print('EditCategoryScreen: initState called');
    print(
        'EditCategoryScreen: Static callback available: ${EditCategoryScreen.onEditComplete != null}');
    print('EditCategoryScreen: Current category: ${widget.category?.headline}');

    _headlineController =
        TextEditingController(text: widget.category?.headline);
    _invitationController =
        TextEditingController(text: widget.category?.invitation);
    if (widget.category != null) {
      _loadTasks();
    }
    _editTasksLocal = widget.tasksOnly;
  }

  @override
  void dispose() {
    _headlineController.dispose();
    _invitationController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    if (widget.category == null) return;

    setState(() {
      _isLoadingTasks = true;
      _error = null;
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('No user logged in');

      // Load tasks into cache
      await Task.loadTaskSet(widget.category!, userId);
      setState(() {
        _tasks = Task.currentTaskSet ?? [];
        _isLoadingTasks = false;
      });
    } catch (e) {
      print('Error loading tasks: $e');
      setState(() {
        _error = e.toString();
        _isLoadingTasks = false;
      });
    }
  }

  Future<void> _saveCategory() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('No user logged in');

      final data = {
        'headline': _headlineController.text,
        'invitation': _invitationController.text.isEmpty
            ? null
            : _invitationController.text,
        'owner_id': userId,
        'original_id': 1, // Default to movies (1) for now
      };

      if (widget.category == null) {
        // Create new category
        print('Creating new category...');
        final response =
            await supabase.from('Categories').insert(data).select().single();

        final newCategory = Category.fromJson(response);
        print('Created new category: ${newCategory.headline}');

        // Save any tasks that were created
        if (_newTasks.isNotEmpty) {
          print('Saving ${_newTasks.length} tasks for new category...');
          for (final task in _newTasks) {
            final taskData = {
              'headline': task.headline,
              'notes': task.notes,
              'category_id': newCategory.id,
              'owner_id': userId,
              'links': task.links,
            };
            await supabase.from('Tasks').insert(taskData);
          }
        }

        // For new categories, pop back to home screen
        if (mounted) {
          Navigator.pop(context, true);
        }
      } else {
        // Update existing category
        print('Updating existing category...');
        final response = await supabase
            .from('Categories')
            .update(data)
            .eq('id', widget.category!.id)
            .eq('owner_id', userId)
            .select()
            .single();

        // Update the category in memory with the response data
        final updatedCategory = Category.fromJson(response);
        widget.category!.headline = updatedCategory.headline;
        widget.category!.invitation = updatedCategory.invitation;
        print('Updated category: ${widget.category!.headline}');

        // Call the edit complete callback to update home screen
        if (EditCategoryScreen.onEditComplete != null) {
          print('EditCategoryScreen: Calling edit complete callback');
          try {
            EditCategoryScreen.onEditComplete!();
            print(
                'EditCategoryScreen: Edit complete callback executed successfully');
          } catch (e) {
            print(
                'EditCategoryScreen: Error executing edit complete callback: $e');
          }
        } else {
          print('EditCategoryScreen: No edit complete callback available');
        }

        // Stay on the screen, just update the state
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isEditing = false; // Return to view mode
          });
        }
      }
    } catch (e) {
      print('Error saving category: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _editTask(Task task) async {
    if (widget.category == null) {
      // For new categories, edit the task in _newTasks
      final index = _newTasks.indexWhere((t) => t.headline == task.headline);
      if (index == -1) return;

      final result = await Navigator.pushNamed(
        context,
        '/edit-task',
        arguments: {
          'category': null, // No category yet
          'task': task,
          'isNewCategory': true,
        },
      );

      if (result is Task) {
        setState(() {
          _newTasks[index] = result;
        });
      }
    } else {
      // For existing categories, use the normal flow
      final result = await Navigator.pushNamed(
        context,
        '/edit-task',
        arguments: {
          'category': widget.category!,
          'task': task,
        },
      );

      if (result == true) {
        _loadTasks(); // Reload tasks if changes were made
      }
    }
  }

  Future<void> _createTask() async {
    if (widget.category == null) {
      // For new categories, add to _newTasks
      final result = await Navigator.pushNamed(
        context,
        '/edit-task',
        arguments: {
          'category': null, // No category yet
          'task': null,
          'isNewCategory': true,
        },
      );

      if (result is Task) {
        setState(() {
          _newTasks.add(result);
        });
      }
    } else {
      // For existing categories, use the normal flow
      final result = await Navigator.pushNamed(
        context,
        '/edit-task',
        arguments: {
          'category': widget.category!,
          'task': null,
        },
      );

      if (result == true) {
        _loadTasks(); // Reload tasks if a new task was created
      }
    }
  }

  Future<String?> _getJustWatchTitle(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        print('Error fetching JustWatch page: ${response.statusCode}');
        return null;
      }

      final document = html_parser.parse(response.body);
      final titleElement =
          document.querySelector('h1.title-detail-hero__details__title');
      if (titleElement != null) {
        // Get only the direct text nodes, ignoring text from child elements
        final directText = titleElement.nodes
            .where((node) => node.nodeType == 3) // 3 is the value for TEXT_NODE
            .map((node) => node.text?.trim())
            .where((text) => text != null && text.isNotEmpty)
            .join(' ')
            .trim();

        return directText.isEmpty ? null : directText;
      }
      return null;
    } catch (e) {
      print('Error fetching JustWatch title: $e');
      return null;
    }
  }

  Future<void> _handleClipboardContent() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData?.text == null) {
        throw Exception('Clipboard is empty');
      }

      final extractedLink =
          await LinkExtractor.extractLinkFromString(clipboardData!.text!);
      if (extractedLink == null) {
        throw Exception(
            'Clipboard content must be either a URL or an HTML <a> tag');
      }

      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('No user logged in');
      }

      // Create a new task with this link
      final task = Task(
        id: -1, // Temporary ID for new task
        categoryId: widget.category?.id ?? -1,
        headline: extractedLink.title,
        notes: null,
        ownerId: userId,
        createdAt: DateTime.now(),
        suggestibleAt: null,
        triggersAt: null,
        deferral: null,
        links: [extractedLink.html], // Store as HTML <a> tag
        finished: false,
      );

      setState(() {
        if (widget.category == null) {
          _newTasks.add(task);
        } else {
          _tasks.add(task);
        }
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task created from link'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleBack() {
    print('EditCategoryScreen: Back button pressed');
    print('EditCategoryScreen: Current category: ${widget.category?.headline}');
    print(
        'EditCategoryScreen: Static callback available: ${EditCategoryScreen.onEditComplete != null}');

    // Call the static callback before popping
    if (EditCategoryScreen.onEditComplete != null) {
      print('EditCategoryScreen: Calling static callback');
      try {
        EditCategoryScreen.onEditComplete!();
        print('EditCategoryScreen: Static callback executed successfully');
      } catch (e) {
        print('EditCategoryScreen: Error executing static callback: $e');
      }
    } else {
      print('EditCategoryScreen: No static callback available');
    }

    // Pop after executing the callback
    if (mounted) {
      Navigator.of(context)
          .pop(true); // Always return true to indicate completion
      print('EditCategoryScreen: Popped screen with true result');
    } else {
      print('EditCategoryScreen: Widget not mounted, cannot pop');
    }
  }

  Future<void> _deleteTask(Task task) async {
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

    if (confirmed != true) return;

    setState(() {
      _tasks.remove(task);
    });

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase
          .from('Tasks')
          .delete()
          .eq('id', task.id)
          .eq('owner_id', userId);
    } catch (e) {
      print('Error deleting task: $e');
      setState(() {
        _error = 'Error deleting task: $e';
      });
    }
  }

  Future<void> _toggleTaskCompletion(Task task) async {
    final newFinishedState = !task.finished;

    setState(() {
      final index = _tasks.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        _tasks[index] = Task(
          id: task.id,
          categoryId: task.categoryId,
          headline: task.headline,
          notes: task.notes,
          ownerId: task.ownerId,
          createdAt: task.createdAt,
          suggestibleAt: task.suggestibleAt,
          triggersAt: task.triggersAt,
          deferral: task.deferral,
          links: task.links,
          finished: newFinishedState,
        );
      }
    });

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase
          .from('Tasks')
          .update({'finished': newFinishedState})
          .eq('id', task.id)
          .eq('owner_id', userId);
    } catch (e) {
      print('Error updating task completion: $e');
      setState(() {
        _error = 'Error updating task: $e';
      });
    }
  }

  Widget _buildTaskList() {
    if (_tasks.isEmpty) {
      print('EditCategoryScreen: No tasks to display');
      return const Center(
        child: Text('No tasks yet. Add one to get started!'),
      );
    }

    // Debug log to check task links
    print(
        '\n=== EditCategoryScreen: Building task list with ${_tasks.length} tasks ===');
    for (final task in _tasks) {
      print(
          'Task "${task.headline}" has ${task.links?.length ?? 0} links: ${task.links}');
    }

    print('EditCategoryScreen: Creating ListView.builder...');
    return ListView.builder(
      shrinkWrap: true, // Add this to ensure ListView takes minimum space
      physics:
          const NeverScrollableScrollPhysics(), // Disable scrolling since we're in a ListView
      itemCount: _tasks.length,
      itemBuilder: (context, index) {
        final task = _tasks[index];
        print(
            '\n=== EditCategoryScreen: Building TaskDisplay for "${task.headline}" at index $index ===');
        print('Task links: ${task.links}');
        print('Task links type: ${task.links?.runtimeType}');
        print('Task links length: ${task.links?.length ?? 0}');
        print('About to create TaskDisplay widget...');

        final taskDisplay = TaskDisplay(
          key: ValueKey(
              'task-${task.id}'), // Add a key to help Flutter track the widget
          task: task,
          withControls: true,
          onEdit: () => _editTask(task),
          onDelete: () => _deleteTask(task),
          onTap: () => _toggleTaskCompletion(task),
        );

        print('TaskDisplay widget created successfully for "${task.headline}"');
        print('=== End TaskDisplay creation ===\n');

        return taskDisplay;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        print('EditCategoryScreen: WillPopScope triggered');
        _handleBack();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              print('EditCategoryScreen: Back button pressed in app bar');
              _handleBack();
            },
          ),
          title:
              Text(widget.category == null ? 'New Endeavor' : 'Edit Endeavor'),
          actions: [
            if (widget.category != null && !_editTasksLocal && _isEditing)
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  // Reset controllers to current values
                  _headlineController.text = widget.category!.headline;
                  _invitationController.text =
                      widget.category!.invitation ?? '';
                  setState(() {
                    _isEditing = false;
                  });
                },
                tooltip: 'Cancel edit',
              ),
            if (widget.category != null && !_editTasksLocal)
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: _isLoading
                    ? null
                    : () {
                        // TODO: Implement category deletion
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Endeavor?'),
                            content: const Text(
                                'This will also delete all tasks in this category. This action cannot be undone.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () {
                                  // TODO: Implement deletion
                                  Navigator.pop(context);
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                      },
                tooltip: 'Delete endeavor',
              ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              if (_editTasksLocal && widget.category != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.category!.headline,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit details',
                      onPressed: () {
                        setState(() {
                          _editTasksLocal = false;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (widget.category!.invitation != null)
                  Text(
                    widget.category!.invitation!,
                    style: const TextStyle(
                        fontSize: 16, fontStyle: FontStyle.italic),
                  ),
                const SizedBox(height: 16),
              ] else if (widget.category != null && !_isEditing) ...[
                // View mode - show category details in a card
                Card(
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.category!.headline,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (widget.category!.invitation != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                widget.category!.invitation!,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                            if (widget.category!.originalId == 1 ||
                                widget.category!.originalId == 2) ...[
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () {
                                  print('Import JustWatch button pressed');
                                  print(
                                      'Category: ${widget.category?.headline}');

                                  // Navigate to Import JustWatch screen, replacing the current screen
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          ImportJustWatchScreen(
                                        category: widget.category!,
                                      ),
                                    ),
                                  ).then((result) {
                                    if (result is Category) {
                                      setState(() {
                                        widget.category!.headline =
                                            result.headline;
                                        widget.category!.invitation =
                                            result.invitation;
                                        _loadTasks();
                                      });
                                    }
                                  });
                                },
                                icon: const Icon(Icons.movie),
                                label: const Text('Import JustWatch list'),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {
                              setState(() {
                                _isEditing = true;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.edit,
                                size: 20,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                // Edit mode - show form fields
                TextFormField(
                  controller: _headlineController,
                  decoration: const InputDecoration(
                    labelText: 'Endeavor',
                    hintText: 'What have you been meaning to do?',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please name your endeavor';
                    }
                    return null;
                  },
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _invitationController,
                  decoration: const InputDecoration(
                    labelText: 'Invitation (optional)',
                    hintText: 'What would you like to say to yourself?',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (widget.category != null && _isEditing)
                      TextButton(
                        onPressed: () {
                          // Reset controllers to current values
                          _headlineController.text = widget.category!.headline;
                          _invitationController.text =
                              widget.category!.invitation ?? '';
                          setState(() {
                            _isEditing = false;
                          });
                        },
                        child: const Text('Cancel'),
                      ),
                    if (widget.category != null && _isEditing)
                      const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : () async {
                              if (!_formKey.currentState!.validate()) return;
                              await _saveCategory();
                              if (widget.category != null) {
                                setState(() {
                                  _isEditing = false;
                                });
                              }
                            },
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(widget.category == null
                              ? 'Create Endeavor'
                              : 'Save Changes'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              // Show tasks section for both new and existing categories
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Tasks for this endeavor:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _handleClipboardContent,
                    icon: const Icon(Icons.content_paste),
                    label: const Text('Add from Clipboard'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_isLoadingTasks)
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
                        onPressed: _loadTasks,
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                )
              else if (widget.category == null
                  ? _newTasks.isEmpty
                  : _tasks.isEmpty)
                const Center(
                  child: Text(
                    'No tasks yet. Add some tasks to get started!',
                    style: TextStyle(fontSize: 16),
                  ),
                )
              else
                _buildTaskList(), // Remove Expanded since we're in a ListView
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Error: $_error',
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _createTask,
          child: const Icon(Icons.add),
          tooltip: 'Add task',
        ),
      ),
    );
  }
}
