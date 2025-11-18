import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/widgets/category_form.dart';
import 'package:meaning_to/utils/app_buttons.dart';

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

  Future<void> _createCategory(String headline, String invitation,
      bool isPrivate, bool tasksArePrivate) async {
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
        'private': isPrivate,
        'tasks_are_private': tasksArePrivate,
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          if (!_isCheckingCategories && !_hasCategories) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Text(
                'A \'${NamingUtils.categoriesName(plural: false, capitalize: false)}\' is a category of activities like \'Watch a Movie\' or \'Tackle a Project\'. If you\'d like to see what ${NamingUtils.categoriesName(plural: true, capitalize: false)} others have filed, hit the \'Shop For ${NamingUtils.categoriesName(capitalize: true)}\' button below.',
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
          const SizedBox(height: 32),
          const Center(
            child: Text(
              '** You can grab ideas from other people. **',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () async {
              print('NewCategoryScreen: Shop for Ideas button pressed');
              try {
                final dynamic result =
                    await Navigator.pushNamed(context, '/shop-endeavors');
                print(
                    'NewCategoryScreen: Navigation returned with result: $result (type: ${result.runtimeType})');
                // ShopEndeavorsScreen returns true when categories/tasks are imported
                if (result == true && mounted) {
                  // Categories were imported successfully, navigate back to Home
                  // Pass true so HomeScreen knows to refresh
                  print(
                      'NewCategoryScreen: Categories were imported successfully, returning to Home');
                  Navigator.pop(context, true);
                }
              } catch (e) {
                print('NewCategoryScreen: Navigation error: $e');
              }
            },
            icon: const Icon(Icons.shopping_cart),
            label: Text(
              'Shop for ${NamingUtils.categoriesName(capitalize: true)}',
              style: const TextStyle(fontSize: 18),
            ),
            style: AppButtons.goForth().copyWith(
              minimumSize:
                  const WidgetStatePropertyAll(Size(double.infinity, 50)),
            ),
          ),
        ],
      ),
    );
  }
}
