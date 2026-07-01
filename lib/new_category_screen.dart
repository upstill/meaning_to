import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/widgets/home_button.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/widgets/category_form.dart';

class NewCategoryScreen extends StatefulWidget {
  const NewCategoryScreen({super.key});

  @override
  NewCategoryScreenState createState() => NewCategoryScreenState();
}

class NewCategoryScreenState extends State<NewCategoryScreen> {
  bool _isLoading = false;
  bool _hasCategories = true; // Assume true until we check
  bool _isCheckingCategories = true;

  @override
  void initState() {
    super.initState();
    print('NewCategoryScreen: initState called');
    _checkExistingCategories();
  }

  Future<void> _checkExistingCategories() async {
    try {
      final categories = await ApiClient.getCategories();
      setState(() {
        _hasCategories = categories.isNotEmpty;
        _isCheckingCategories = false;
      });
    } catch (e) {
      print('Error checking categories: $e');
      setState(() {
        _isCheckingCategories = false;
      });
    }
  }

  Future<void> _createCategory(
    String headline,
    String invitation,
    bool _unusedIsPrivate,
    bool _unusedTasksArePrivate,
  ) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userId = AuthUtils.getCurrentUserId();

      final data = {
        'headline': headline,
        'invitation': invitation.isEmpty ? null : invitation,
        'owner_id': userId,
        'original_id': null, // Custom categories should have null original_id
        'private': true,
        'tasks_are_private': true,
      };

      // Create new category
      print('Creating new category...');
      final response =
          await supabase.from('Categories').insert(data).select().single();

      final newCategory = Category.fromJson(response);
      print('Created new category: ${newCategory.headline}');

      // Return the created category to the caller
      if (mounted) {
        Navigator.pop(context, newCategory);
      }
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text('Define a New ${NamingUtils.categoriesName(plural: false)}'),
        leading: const HomeButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          if (!_isCheckingCategories && !_hasCategories) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Text(
                'A \'${NamingUtils.categoriesName(plural: false, capitalize: false)}\' is a category of activities like \'Watch a Movie\' or \'Tackle a Project\'.',
                style: const TextStyle(
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.left,
              ),
            ),
          ],
          CategoryForm(
            category: null, // New category
            isEditing: true, // Always in editing mode for new categories
            isLoading: _isLoading,
            onSave: _createCategory,
          ),
        ],
      ),
    );
  }
}
