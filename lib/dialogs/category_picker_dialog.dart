import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/new_category_screen.dart';

/// Dialog for selecting a category with smart defaults and recent category prioritization
class CategoryPickerDialog extends StatefulWidget {
  final String title;
  final Category? defaultCategory;
  final Function(Category) onCategorySelected;
  final bool showCreateNew;

  const CategoryPickerDialog({
    super.key,
    required this.title,
    this.defaultCategory,
    required this.onCategorySelected,
    this.showCreateNew = true,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    Category? defaultCategory,
    required Function(Category) onCategorySelected,
    bool showCreateNew = true,
  }) {
    return showDialog(
      context: context,
      builder: (context) => CategoryPickerDialog(
        title: title,
        defaultCategory: defaultCategory,
        onCategorySelected: onCategorySelected,
        showCreateNew: showCreateNew,
      ),
    );
  }

  @override
  State<CategoryPickerDialog> createState() => _CategoryPickerDialogState();
}

class _CategoryPickerDialogState extends State<CategoryPickerDialog> {
  List<Category> _categories = [];
  List<Category> _recentCategories = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final userId = AuthUtils.getCurrentUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      print('CategoryPickerDialog: Loading categories for user: $userId');

      // Load all categories
      final response = await supabase
          .from('Categories')
          .select()
          .eq('owner_id', userId)
          .order('headline');

      print('CategoryPickerDialog: Query completed successfully');

      final categoriesData = response as List<dynamic>;
      final categories = categoriesData
          .map((data) => Category.fromJson(data))
          .toList();

      // Get recent categories from cache
      final recentCategories = await _getRecentCategories(categories);

      setState(() {
        _categories = categories;
        _recentCategories = recentCategories;
        _isLoading = false;
      });
    } catch (e) {
      print('CategoryPickerDialog: Error loading categories: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<List<Category>> _getRecentCategories(List<Category> allCategories) async {
    try {
      // Get recently accessed category IDs from cache
      final recentIds = await CacheManager.getRecentCategoryIds();

      // Filter and sort categories by recent access
      final recent = <Category>[];
      for (final id in recentIds) {
        final category = allCategories.where((c) => c.id == id).firstOrNull;
        if (category != null) {
          recent.add(category);
        }
      }

      return recent;
    } catch (e) {
      print('CategoryPickerDialog: Error loading recent categories: $e');
      return [];
    }
  }

  List<Category> get _filteredCategories {
    if (_searchQuery.isEmpty) {
      return _categories;
    }

    return _categories
        .where((category) =>
            category.headline.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  List<Category> get _prioritizedCategories {
    final filtered = _filteredCategories;
    final prioritized = <Category>[];
    final remaining = <Category>[];

    // Add default category first if it exists and matches search
    if (widget.defaultCategory != null &&
        filtered.contains(widget.defaultCategory)) {
      prioritized.add(widget.defaultCategory!);
    }

    // Add recent categories (excluding default if already added)
    for (final recent in _recentCategories) {
      if (filtered.contains(recent) && !prioritized.contains(recent)) {
        prioritized.add(recent);
      }
    }

    // Add remaining categories
    for (final category in filtered) {
      if (!prioritized.contains(category)) {
        remaining.add(category);
      }
    }

    return [...prioritized, ...remaining];
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            // Search field
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search categories...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
            const SizedBox(height: 12),

            // Categories list
            Expanded(
              child: _buildCategoriesList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (widget.showCreateNew)
          TextButton.icon(
            onPressed: _createNewCategory,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Create New'),
          ),
      ],
    );
  }

  Widget _buildCategoriesList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              'Error loading categories',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadCategories,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final categories = _prioritizedCategories;

    if (categories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No categories match your search'
                  : 'No categories found',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        final isDefault = category == widget.defaultCategory;
        final isRecent = _recentCategories.contains(category) && !isDefault;

        return ListTile(
          leading: _buildCategoryIcon(category, isDefault, isRecent),
          title: Text(
            category.headline,
            style: TextStyle(
              fontWeight: isDefault ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: _buildCategorySubtitle(category, isDefault, isRecent),
          onTap: () => _selectCategory(category),
          dense: true,
        );
      },
    );
  }

  Widget _buildCategoryIcon(Category category, bool isDefault, bool isRecent) {
    if (isDefault) {
      return Icon(
        Icons.star,
        color: Theme.of(context).colorScheme.primary,
      );
    } else if (isRecent) {
      return Icon(
        Icons.history,
        color: Theme.of(context).colorScheme.secondary,
      );
    } else {
      return Icon(
        Icons.folder_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }
  }

  Widget? _buildCategorySubtitle(Category category, bool isDefault, bool isRecent) {
    final labels = <String>[];

    if (isDefault) {
      labels.add('Current');
    }
    if (isRecent) {
      labels.add('Recent');
    }

    if (labels.isEmpty) {
      return null;
    }

    return Text(
      labels.join(' • '),
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontSize: 12,
      ),
    );
  }

  void _selectCategory(Category category) async {
    // Update recent categories cache
    await CacheManager.addRecentCategory(category.id);

    Navigator.of(context).pop();
    widget.onCategorySelected(category);
  }

  void _createNewCategory() async {
    Navigator.of(context).pop();

    final result = await Navigator.of(context).push<Category>(
      MaterialPageRoute(
        builder: (context) => const NewCategoryScreen(),
      ),
    );

    if (result != null) {
      widget.onCategorySelected(result);
    }
  }
}