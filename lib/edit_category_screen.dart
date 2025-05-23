import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';

final supabase = Supabase.instance.client;

class EditCategoryScreen extends StatefulWidget {
  static VoidCallback? onEditComplete;  // Static callback for edit completion
  
  final Category? category;  // null for new category, existing category for edit
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

  @override
  void initState() {
    super.initState();
    print('EditCategoryScreen: initState called');
    print('EditCategoryScreen: Static callback available: ${EditCategoryScreen.onEditComplete != null}');
    print('EditCategoryScreen: Current category: ${widget.category?.headline}');
    
    _headlineController = TextEditingController(text: widget.category?.headline);
    _invitationController = TextEditingController(text: widget.category?.invitation);
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
        'invitation': _invitationController.text.isEmpty ? null : _invitationController.text,
        'owner_id': userId,
      };

      if (widget.category == null) {
        // Create new category
        final response = await supabase
            .from('Categories')
            .insert(data)
            .select()
            .single();
        
        final newCategory = Category.fromJson(response);
        print('Created new endeavor: ${newCategory.headline}');
      } else {
        // Update existing category
        await supabase
            .from('Categories')
            .update(data)
            .eq('id', widget.category!.id)
            .eq('owner_id', userId);
        
        print('Updated category: ${widget.category!.headline}');
      }

      if (mounted) {
        Navigator.pop(context, true);  // Return true to indicate success
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
    final result = await Navigator.pushNamed(
      context,
      '/edit-task',
      arguments: {
        'category': widget.category!,
        'task': task,
      },
    );

    if (result == true) {
      _loadTasks();  // Reload tasks if changes were made
    }
  }

  Future<void> _createTask() async {
    final result = await Navigator.pushNamed(
      context,
      '/edit-task',
      arguments: {
        'category': widget.category!,
        'task': null,
      },
    );

    if (result == true) {
      _loadTasks();  // Reload tasks if a new task was created
    }
  }

  void _handleBack() {
    print('EditCategoryScreen: Back button pressed');
    print('EditCategoryScreen: Current category: ${widget.category?.headline}');
    print('EditCategoryScreen: Static callback available: ${EditCategoryScreen.onEditComplete != null}');
    
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
      Navigator.of(context).pop(true);  // Always return true to indicate completion
      print('EditCategoryScreen: Popped screen with true result');
    } else {
      print('EditCategoryScreen: Widget not mounted, cannot pop');
    }
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
          title: Text(widget.category == null ? 'New Endeavor' : 'Edit Endeavor'),
          actions: [
            if (widget.category != null && !_editTasksLocal)
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: _isLoading ? null : () {
                  // TODO: Implement category deletion
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete Endeavor?'),
                      content: const Text('This will also delete all tasks in this category. This action cannot be undone.'),
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
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit details',
                      onPressed: () {
                        setState(() {
                          // Exit editTasks mode to allow editing
                          // This assumes editTasks is not final in the State
                          // We'll need to track local editTasks state
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
                    style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
                  ),
                const SizedBox(height: 16),
              ] else ...[
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
                const SizedBox(height: 16),
              ],
              if (widget.category != null) ...[
                const SizedBox(height: 24),
                const Text(
                  'Tasks for this endeavor:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
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
                else if (_tasks.isEmpty)
                  const Center(
                    child: Text(
                      'No tasks yet. Add some tasks to get started!',
                      style: TextStyle(fontSize: 16),
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Container()), // For alignment with the task title
                          SizedBox(
                            width: 40,
                            child: Center(
                              child: Text(
                                'Done',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          SizedBox(width: 40), // Space for the edit icon
                        ],
                      ),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _tasks.length,
                        itemBuilder: (context, index) {
                          final task = _tasks[index];
                          return Card(
                            child: Row(
                              children: [
                                // Headline and notes take remaining space
                                Expanded(
                                  child: ListTile(
                                    title: Text(
                                      task.headline,
                                      style: TextStyle(
                                        fontWeight: task.suggestibleAt == null || !task.suggestibleAt!.isAfter(DateTime.now())
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: task.suggestibleAt != null && task.suggestibleAt!.isAfter(DateTime.now())
                                            ? Colors.grey
                                            : null,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (task.notes != null)
                                          Text(
                                            task.notes!,
                                            style: TextStyle(
                                              color: task.suggestibleAt != null && task.suggestibleAt!.isAfter(DateTime.now())
                                                  ? Colors.grey
                                                  : null,
                                            ),
                                          ),
                                        if (task.suggestibleAt != null && task.suggestibleAt!.isAfter(DateTime.now()) && !task.finished)
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  task.getSuggestibleTimeDisplay() ?? 'Available now',
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
                                                    await Task.reviveTask(task, userId);
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
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                // Checkbox in fixed-width area
                                SizedBox(
                                  width: 40,
                                  child: Center(
                                    child: Checkbox(
                                      value: task.finished,
                                      onChanged: (val) async {
                                        setState(() {
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
                                            finished: val ?? false,
                                          );
                                        });
                                        final userId = supabase.auth.currentUser?.id;
                                        if (userId == null) return;
                                        print('Updating task \\${task.id} to finished: \\${val ?? false} by user \\${userId}');
                                        final response = await supabase
                                            .from('Tasks')
                                            .update({'finished': val ?? false})
                                            .eq('id', task.id)
                                            .eq('owner_id', userId);
                                        print('Supabase update response: \\${response.toString()}');
                                      },
                                    ),
                                  ),
                                ),
                                // Edit button in fixed-width area
                                SizedBox(
                                  width: 40,
                                  child: IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _editTask(task),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Error: $_error',
                  style: const TextStyle(color: Colors.red),
                ),
              ],
              if (!_editTasksLocal) ...[
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveCategory,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(widget.category == null ? 'Create Endeavor' : 'Save Changes'),
                ),
              ],
            ],
          ),
        ),
        floatingActionButton: widget.category != null
            ? FloatingActionButton(
                onPressed: _createTask,
                child: const Icon(Icons.add),
                tooltip: 'Add task',
              )
            : null,
      ),
    );
  }
} 