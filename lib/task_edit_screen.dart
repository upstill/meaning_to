import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:flutter/services.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/link_edit_screen.dart';
import 'dart:convert';

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
  List<String> _links = [];

  @override
  void initState() {
    super.initState();
    _headlineController = TextEditingController(text: widget.task?.headline);
    _notesController = TextEditingController(text: widget.task?.notes);
    _links = widget.task?.links != null ? List<String>.from(widget.task!.links!) : [];
  }

  @override
  void dispose() {
    _headlineController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _addLink() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const LinkEditScreen(),
      ),
    );

    if (result != null) {
      setState(() {
        _links.add(result);
      });
    }
  }

  Future<void> _editLink(int index) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => LinkEditScreen(
          initialLink: _links[index],
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _links[index] = result;
      });
    }
  }

  void _removeLink(int index) {
    setState(() {
      _links.removeAt(index);
    });
  }

  Future<void> _pasteLinkFromClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData?.text == null) {
        setState(() {
          _error = 'No text found in clipboard';
        });
        return;
      }

      final text = clipboardData!.text!.trim();
      String linkText;

      // Check if it's an HTML link
      if (text.startsWith('<a href="')) {
        linkText = text;
      } else {
        // Try to parse as URL
        if (LinkProcessor.isValidUrl(text)) {
          // Create a simple HTML link with the URL as text
          linkText = '<a href="$text">$text</a>';
        } else {
          setState(() {
            _error = 'Clipboard text is not a valid URL or HTML link';
          });
          return;
        }
      }

      // Add the link to the list
      setState(() {
        _links.add(linkText);
        _error = null;
      });
    } catch (e) {
      print('Error pasting link: $e');
      setState(() {
        _error = 'Failed to paste link: ${e.toString()}';
      });
    }
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
        'links': _links.isEmpty ? null : (_links.length == 1 ? _links[0] : jsonEncode(_links)),
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

  Widget _buildLinksList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Links:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.content_paste),
                  tooltip: 'Paste link from clipboard',
                  onPressed: _isLoading ? null : _pasteLinkFromClipboard,
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add link',
                  onPressed: _isLoading ? null : _addLink,
                ),
              ],
            ),
          ],
        ),
        if (_links.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...List.generate(_links.length, (index) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: LinkDisplayWidget(
                        linkText: _links[index],
                        showIcon: true,
                        showTitle: true,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit link',
                      onPressed: _isLoading ? null : () => _editLink(index),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      tooltip: 'Delete link',
                      onPressed: _isLoading ? null : () => _removeLink(index),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.category.headline,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.task == null ? 'New Task' : 'Edit Task',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
            ),
          ],
        ),
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
            _buildLinksList(),
            if (_links.isEmpty) ...[
              const SizedBox(height: 16),
              Center(
                child: TextButton.icon(
                  onPressed: _isLoading ? null : _addLink,
                  icon: const Icon(Icons.add_link),
                  label: const Text('Add Link'),
                ),
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