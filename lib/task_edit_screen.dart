import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';

final supabase = Supabase.instance.client;

class TaskEditScreen extends StatefulWidget {
  final Category category;
  final Task? task;  // null for new task, existing task for edit

  const TaskEditScreen({
    super.key, 
    required this.category,
    this.task,
  });

  @override
  State<TaskEditScreen> createState() => _TaskEditScreenState();
}

class _TaskEditScreenState extends State<TaskEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _headlineController;
  late TextEditingController _notesController;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _headlineController = TextEditingController(text: widget.task?.headline);
    _notesController = TextEditingController(text: widget.task?.notes);
  }

  @override
  void dispose() {
    _headlineController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveTask() async {
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
        'notes': _notesController.text.isEmpty ? null : _notesController.text,
        'category_id': widget.category.id,
        'owner_id': userId,
        'finished': widget.task?.finished ?? false,
      };

      if (widget.task == null) {
        // Create new task
        final response = await supabase
            .from('Tasks')
            .insert(data)
            .select()
            .single();
        
        final newTask = Task.fromJson(response);
        print('Created new task: ${newTask.headline}');
        
        // Update the task cache
        if (Task.currentCategory?.id == widget.category.id) {
          await Task.loadTaskSet(widget.category, userId);
        }
      } else {
        // Update existing task
        await supabase
            .from('Tasks')
            .update(data)
            .eq('id', widget.task!.id)
            .eq('owner_id', userId);
        
        print('Updated task: ${widget.task!.headline}');
        
        // Update the task cache
        if (Task.currentCategory?.id == widget.category.id) {
          await Task.loadTaskSet(widget.category, userId);
        }
      }

      if (mounted) {
        Navigator.pop(context, true);  // Return true to indicate success
      }
    } catch (e) {
      print('Error saving task: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteTask() async {
    if (widget.task == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('No user logged in');

      await supabase
          .from('Tasks')
          .delete()
          .eq('id', widget.task!.id)
          .eq('owner_id', userId);
      
      print('Deleted task: ${widget.task!.headline}');
      
      // Update the task cache
      if (Task.currentCategory?.id == widget.category.id) {
        await Task.loadTaskSet(widget.category, userId);
      }

      if (mounted) {
        Navigator.pop(context, true);  // Return true to indicate success
      }
    } catch (e) {
      print('Error deleting task: $e');
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
        title: Text(widget.task == null ? 'New Task' : 'Edit Task'),
        actions: [
          if (widget.task != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _isLoading ? null : _deleteTask,
              tooltip: 'Delete task',
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
                labelText: 'Task',
                hintText: 'What have you been meaning to do?',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a task';
                }
                return null;
              },
              enabled: !_isLoading,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'Add any additional details...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              enabled: !_isLoading,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                'Error: $_error',
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _saveTask,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(widget.task == null ? 'Create Task' : 'Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
} 