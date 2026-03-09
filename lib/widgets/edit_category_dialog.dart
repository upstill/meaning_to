import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/utils/supabase_client.dart';

/// A dialog for editing a category's fields (name, description, privacy).
/// Returns the updated [Category] on save, or null on cancel.
class EditCategoryDialog extends StatefulWidget {
  final Category category;

  const EditCategoryDialog({super.key, required this.category});

  @override
  State<EditCategoryDialog> createState() => _EditCategoryDialogState();
}

class _EditCategoryDialogState extends State<EditCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _headlineController;
  late final TextEditingController _invitationController;
  late bool _isPrivate;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _headlineController =
        TextEditingController(text: widget.category.headline);
    _invitationController =
        TextEditingController(text: widget.category.invitation ?? '');
    _isPrivate = widget.category.isPrivate;
  }

  @override
  void dispose() {
    _headlineController.dispose();
    _invitationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final invitation = _invitationController.text.trim();
      final response = await supabase
          .from('Categories')
          .update({
            'headline': _headlineController.text.trim(),
            'invitation': invitation.isEmpty ? null : invitation,
            'private': _isPrivate,
          })
          .eq('id', widget.category.id)
          .select()
          .single();
      final updated = Category.fromJson(response);
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Error saving ${NamingUtils.categoriesName(capitalize: false, plural: false)}: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Edit ${NamingUtils.categoriesName(capitalize: true, plural: false)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _headlineController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '${NamingUtils.categoriesName(capitalize: true, plural: false)} Name',
                  border: const OutlineInputBorder(),
                  suffixIcon: Tooltip(
                    message: _isPrivate ? 'Make Public' : 'Make Private',
                    child: IconButton(
                      icon: Icon(_isPrivate ? Icons.lock : Icons.lock_open),
                      onPressed: _isLoading
                          ? null
                          : () => setState(() => _isPrivate = !_isPrivate),
                    ),
                  ),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? 'Please enter a ${NamingUtils.categoriesName(capitalize: false, plural: false)} name'
                        : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _invitationController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  hintText: 'Add a description or invitation...',
                ),
                minLines: 3,
                maxLines: 10,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[300],
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
