import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';

final supabase = Supabase.instance.client;

class EditCategoryScreen extends StatefulWidget {
  final Category? category;  // null for new category, existing category for edit

  const EditCategoryScreen({super.key, this.category});

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

  @override
  void initState() {
    super.initState();
    _headlineController = TextEditingController(text: widget.category?.headline);
    _invitationController = TextEditingController(text: widget.category?.invitation);
    if (widget.category != null) {
      _loadTasks();
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category == null ? 'New Endeavor' : 'Edit Endeavor'),
        actions: [
          if (widget.category != null)
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
            if (widget.category != null) ...[
              const SizedBox(height: 24),
              const Text(
                'Tasks in this category:',
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
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _tasks.length,
                  itemBuilder: (context, index) {
                    final task = _tasks[index];
                    return Card(
                      child: ListTile(
                        title: Text(task.headline),
                        subtitle: task.notes != null ? Text(task.notes!) : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _editTask(task),
                        ),
                      ),
                    );
                  },
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                'Error: $_error',
                style: const TextStyle(color: Colors.red),
              ),
            ],
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
        ),
      ),
      floatingActionButton: widget.category != null
          ? FloatingActionButton(
              onPressed: _createTask,
              child: const Icon(Icons.add),
              tooltip: 'Add task',
            )
          : null,
    );
  }
} 