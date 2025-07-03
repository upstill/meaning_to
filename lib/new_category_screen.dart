import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/edit_category_screen.dart';

class NewCategoryScreen extends StatefulWidget {
  const NewCategoryScreen({super.key});

  @override
  NewCategoryScreenState createState() => NewCategoryScreenState();
}

class NewCategoryScreenState extends State<NewCategoryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _headlineController = TextEditingController();
  final _invitationController = TextEditingController();
  bool _isLoading = false;
  bool _isPrivate = false; // Private flag for categories

  @override
  void initState() {
    super.initState();

    // Add listener to track headline changes for button state
    _headlineController.addListener(() {
      setState(() {
        // Trigger rebuild when headline changes to update button state
      });
    });
  }

  @override
  void dispose() {
    _headlineController.dispose();
    _invitationController.dispose();
    super.dispose();
  }

  Future<bool?> _createCategory() async {
    if (!_formKey.currentState!.validate()) return false;

    setState(() {
      _isLoading = true;
    });

    try {
      final userId = AuthUtils.getCurrentUserId();
      if (userId == null) throw Exception('No user logged in');

      final data = {
        'headline': _headlineController.text,
        'invitation': _invitationController.text.isEmpty
            ? null
            : _invitationController.text,
        'owner_id': userId,
        'original_id': null, // Custom categories should have null original_id
        'private': _isPrivate,
      };

      // Create new category
      print('Creating new category...');
      final response =
          await supabase.from('Categories').insert(data).select().single();

      final newCategory = Category.fromJson(response);
      print('Created new category: ${newCategory.headline}');

      // Navigate to Edit Category screen with the new category
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => EditCategoryScreen(category: newCategory),
          ),
        );
      }

      // Return true to indicate successful creation
      return true;
    } catch (e) {
      print('Error creating category: $e');
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating category: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Endeavor'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              controller: _headlineController,
              decoration: const InputDecoration(
                labelText: 'Endeavor (required)',
                hintText: 'What have you been meaning to do?',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
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
            CheckboxListTile(
              title: const Text('Private'),
              subtitle: const Text('I want to keep this endeavor to myself'),
              value: _isPrivate,
              onChanged: _isLoading
                  ? null
                  : (bool? value) {
                      setState(() {
                        _isPrivate = value ?? false;
                      });
                    },
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: (_isLoading || _headlineController.text.trim().isEmpty)
                  ? null
                  : () async {
                      final result = await _createCategory();
                      if (result == true && mounted) {
                        Navigator.pop(context, true);
                      }
                    },
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create Endeavor'),
            ),
          ],
        ),
      ),
    );
  }
}
