import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:flutter/services.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/link_edit_screen.dart';
import 'dart:convert';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/link_extractor.dart';
import 'package:meaning_to/widgets/link_display.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/supabase_client.dart';

class TaskEditScreen extends StatefulWidget {
  static VoidCallback? onEditComplete; // Static callback for edit completion

  final Category category;
  final Task? task; // null for new task, existing task for edit

  const TaskEditScreen({super.key, required this.category, this.task});

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
    _links = widget.task?.links != null
        ? List<String>.from(widget.task!.links!)
        : [];
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
      MaterialPageRoute(builder: (context) => const LinkEditScreen()),
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
        builder: (context) => LinkEditScreen(initialLink: _links[index]),
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
      setState(() {
        _isLoading = true;
        _error = null;
      });

      try {
        // Parse the text as HTML link
        final (url, linkText) = LinkProcessor.parseHtmlLink(text);

        // If it's not an HTML link, treat it as a plain URL
        if (url == text) {
          if (LinkProcessor.isValidUrl(text)) {
            // Validate the URL
            final processedLink = await LinkProcessor.validateAndProcessLink(
              text,
            );

            // Create an HTML link with the fetched title
            final htmlLink =
                '<a href="$text">${processedLink.title ?? text}</a>';
            setState(() {
              _links.add(htmlLink);
              _error = null;
            });
          } else {
            // Open link edit screen with the text pre-filled
            final result = await Navigator.push<String>(
              context,
              MaterialPageRoute(
                builder: (context) => LinkEditScreen(
                  initialLink: text,
                  errorMessage:
                      'Clipboard text is not a valid URL or HTML link',
                ),
              ),
            );
            if (result != null) {
              setState(() {
                _links.add(result);
                _error = null;
              });
            }
          }
        } else {
          // It was an HTML link, validate the extracted URL
          final processedLink = await LinkProcessor.validateAndProcessLink(
            url,
            linkText: linkText,
          );

          // Create a new HTML link with the validated data
          final htmlLink =
              '<a href="$url">${linkText ?? processedLink.title ?? url}</a>';
          setState(() {
            _links.add(htmlLink);
            _error = null;
          });
        }
      } catch (e) {
        print('Error processing pasted link: $e');
        // Open link edit screen with error message
        final result = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (context) =>
                LinkEditScreen(initialLink: text, errorMessage: e.toString()),
          ),
        );
        if (result != null) {
          setState(() {
            _links.add(result);
            _error = null;
          });
        }
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error pasting link: $e');
      setState(() {
        _error = 'Failed to paste link: ${e.toString()}';
        _isLoading = false;
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
      final userId = AuthUtils.getCurrentUserId();
      if (userId == null) throw Exception('No user logged in');

      final data = {
        'headline': _headlineController.text,
        'notes': _notesController.text.isEmpty ? null : _notesController.text,
        'category_id': widget.category.id,
        'owner_id': userId,
        'finished': widget.task?.finished ?? false,
        'links': _links.isEmpty
            ? null
            : (_links.length == 1 ? _links[0] : jsonEncode(_links)),
      };

      Task? updatedTask;
      if (widget.task == null) {
        // Create new task
        print('TaskEditScreen: Creating new task...');
        final response =
            await supabase.from('Tasks').insert(data).select().single();

        updatedTask = Task.fromJson(response);
        print('TaskEditScreen: Created new task: ${updatedTask.headline}');
      } else {
        // Update existing task
        print('TaskEditScreen: Updating existing task...');
        final response = await supabase
            .from('Tasks')
            .update(data)
            .eq('id', widget.task!.id)
            .eq('owner_id', userId)
            .select()
            .single();

        updatedTask = Task.fromJson(response);
        print('TaskEditScreen: Updated task: ${updatedTask.headline}');
      }

      // Update the task cache
      print('TaskEditScreen: Updating task cache...');
      if (Task.currentCategory?.id == widget.category.id) {
        print('TaskEditScreen: Reloading task set for current category...');
        await Task.loadTaskSet(widget.category, userId);

        // If this was the current task, update it in the cache
        if (widget.task != null && Task.currentTask?.id == widget.task!.id) {
          print('TaskEditScreen: Updating current task in cache...');
          Task.updateCurrentTask(updatedTask);
        }
      }

      print(
        'TaskEditScreen: Task saved successfully, calling edit complete callback...',
      );
      // Call the edit complete callback before popping
      if (TaskEditScreen.onEditComplete != null) {
        print('TaskEditScreen: Static callback available, calling it...');
        try {
          TaskEditScreen.onEditComplete!();
          print('TaskEditScreen: Static callback executed successfully');
        } catch (e) {
          print('TaskEditScreen: Error executing static callback: $e');
        }
      } else {
        print('TaskEditScreen: No static callback available');
      }

      if (mounted) {
        print('TaskEditScreen: Popping screen with true result...');
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      print('TaskEditScreen: Error saving task: $e');
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
      final userId = AuthUtils.getCurrentUserId();
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
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      print('Error deleting task: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _handleBack() {
    print('TaskEditScreen: Back button pressed');
    print('TaskEditScreen: Current task: ${widget.task?.headline}');
    print(
      'TaskEditScreen: Static callback available: ${TaskEditScreen.onEditComplete != null}',
    );

    // Call the static callback before popping
    if (TaskEditScreen.onEditComplete != null) {
      print('TaskEditScreen: Calling static callback');
      try {
        TaskEditScreen.onEditComplete!();
        print('TaskEditScreen: Static callback executed successfully');
      } catch (e) {
        print('TaskEditScreen: Error executing static callback: $e');
      }
    } else {
      print('TaskEditScreen: No static callback available');
    }

    // Pop after executing the callback
    if (mounted) {
      Navigator.of(
        context,
      ).pop(true); // Always return true to indicate completion
      print('TaskEditScreen: Popped screen with true result');
    } else {
      print('TaskEditScreen: Widget not mounted, cannot pop');
    }
  }

  Widget _buildLinksList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Links:', style: TextStyle(fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add link',
              onPressed: _isLoading ? null : _addLink,
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
                    // Only show delete button for authenticated users
                    if (!AuthUtils.isGuestUser())
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
    return WillPopScope(
      onWillPop: () async {
        print('TaskEditScreen: WillPopScope triggered');
        _handleBack();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              print('TaskEditScreen: Back button pressed in app bar');
              _handleBack();
            },
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.category.headline,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (widget.task != null)
                Text(
                  'Edit Task',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                  ),
                ),
            ],
          ),
          actions: [
            // Only show delete button for authenticated users
            if (widget.task != null && !AuthUtils.isGuestUser())
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
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Container(
                    width:
                        80, // Fixed width container - enough for two 32px icons plus gap
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.content_paste),
                          tooltip: 'Paste link from clipboard',
                          onPressed:
                              _isLoading ? null : _pasteLinkFromClipboard,
                          iconSize: 32,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const Icon(Icons.arrow_forward, size: 32),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isLoading ? null : _saveTask,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        widget.task == null ? 'Create Task' : 'Save Changes',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
