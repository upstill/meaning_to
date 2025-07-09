import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/naming.dart';

class CategoryForm extends StatefulWidget {
  final Category? category;
  final bool isEditing;
  final bool isLoading;
  final Function(String headline, String invitation, bool isPrivate,
      bool tasksArePrivate) onSave;
  final VoidCallback? onEdit;
  final VoidCallback? onCancel;

  const CategoryForm({
    super.key,
    this.category,
    required this.isEditing,
    required this.isLoading,
    required this.onSave,
    this.onEdit,
    this.onCancel,
  });

  @override
  CategoryFormState createState() => CategoryFormState();
}

class CategoryFormState extends State<CategoryForm> {
  final _formKey = GlobalKey<FormState>();
  final _headlineController = TextEditingController();
  final _invitationController = TextEditingController();
  bool _isPrivate = false;
  bool _tasksArePrivate = true;

  @override
  void initState() {
    super.initState();
    _initializeControllers();

    // Add listener to track headline changes for button state
    _headlineController.addListener(() {
      setState(() {
        // Trigger rebuild when headline changes to update button state
      });
    });
  }

  @override
  void didUpdateWidget(CategoryForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category ||
        oldWidget.isEditing != widget.isEditing) {
      _initializeControllers();
    }
  }

  void _initializeControllers() {
    if (widget.category != null) {
      _headlineController.text = widget.category!.headline;
      _invitationController.text = widget.category!.invitation ?? '';
      _isPrivate = widget.category!.isPrivate;
      _tasksArePrivate = widget.category!.tasksArePrivate;
    } else {
      _headlineController.clear();
      _invitationController.clear();
      _isPrivate = false;
      _tasksArePrivate = true;
    }
  }

  @override
  void dispose() {
    _headlineController.dispose();
    _invitationController.dispose();
    super.dispose();
  }

  void _handleSave() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSave(
      _headlineController.text,
      _invitationController.text,
      _isPrivate,
      _tasksArePrivate,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with title and edit button

              // Form fields
              if (widget.isEditing || widget.category == null) ...[
                TextFormField(
                  controller: _headlineController,
                  decoration: InputDecoration(
                    labelText: 'Name (required)',
                    hintText: 'What have you been meaning to do?',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please name your ${NamingUtils.categoriesName(capitalize: false, plural: false)}';
                    }
                    return null;
                  },
                  enabled: !widget.isLoading,
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
                  enabled: !widget.isLoading,
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Private'),
                  subtitle: Text(
                      'I want to keep this ${NamingUtils.categoriesName(capitalize: false, plural: false)} to myself'),
                  value: _isPrivate,
                  onChanged: widget.isLoading
                      ? null
                      : (bool? value) {
                          setState(() {
                            _isPrivate = value ?? false;
                          });
                        },
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (!_isPrivate) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    title: Text(
                        '${NamingUtils.tasksName(plural: true)} are private'),
                    subtitle: Text(
                        'Share only the ${NamingUtils.categoriesName(capitalize: false, plural: false)}, not the ${NamingUtils.tasksName(plural: true)}'),
                    value: _tasksArePrivate,
                    onChanged: widget.isLoading
                        ? null
                        : (bool? value) {
                            setState(() {
                              _tasksArePrivate = value ?? true;
                            });
                          },
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (widget.category != null &&
                        widget.isEditing &&
                        widget.onCancel != null)
                      TextButton(
                        onPressed: widget.onCancel,
                        child: const Text('Cancel'),
                      ),
                    if (widget.category != null &&
                        widget.isEditing &&
                        widget.onCancel != null)
                      const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: (widget.isLoading ||
                              _headlineController.text.trim().isEmpty)
                          ? null
                          : _handleSave,
                      child: widget.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              widget.category == null
                                  ? 'Create ${NamingUtils.categoriesName()}'
                                  : 'Save Changes',
                            ),
                    ),
                  ],
                ),
              ] else ...[
                // Display mode for existing categories
                if (widget.category!.invitation != null &&
                    widget.category!.invitation!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.category!.invitation!,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                if (widget.category!.isPrivate) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.lock,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Private',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
