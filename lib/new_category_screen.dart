import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/edit_category_screen.dart';
import 'package:meaning_to/widgets/category_form.dart';

class NewCategoryScreen extends StatefulWidget {
  const NewCategoryScreen({super.key});

  @override
  NewCategoryScreenState createState() => NewCategoryScreenState();
}

class NewCategoryScreenState extends State<NewCategoryScreen> {
  bool _isLoading = false;

  Future<void> _createCategory(
      String headline, String invitation, bool isPrivate) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userId = AuthUtils.getCurrentUserId();
      if (userId == null) throw Exception('No user logged in');

      final data = {
        'headline': headline,
        'invitation': invitation.isEmpty ? null : invitation,
        'owner_id': userId,
        'original_id': null, // Custom categories should have null original_id
        'private': isPrivate,
      };

      // Create new category
      print('Creating new category...');
      final response =
          await supabase.from('Categories').insert(data).select().single();

      final newCategory = Category.fromJson(response);
      print('Created new category: ${newCategory.headline}');

      // Initialize cache with the new category (and no tasks)
      final cacheManager = CacheManager();
      await cacheManager.initializeWithSavedCategory(newCategory, userId);
      print(
          'CacheManager initialized with new category: ${newCategory.headline}');

      // Navigate to Edit Category screen with the new category
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => EditCategoryScreen(category: newCategory),
          ),
        );
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
        title: const Text('Create New Endeavor'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
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
