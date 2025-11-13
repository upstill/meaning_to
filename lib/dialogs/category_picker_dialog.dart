import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/new_category_screen.dart';

/// Dialog for selecting a category with smart defaults and recent category prioritization
class CategoryPickerDialog extends StatefulWidget {
  final String title;
  final String? subtitle; // Optional guidance text shown at the top
  final Category? defaultCategory;
  final Function(Category, {bool? shouldMove}) onCategorySelected;
  final bool showCreateNew;
  final Category? excludeCategory; // Category to exclude from the list
  final bool showMoveAndCopy; // Show move/copy buttons instead of create new
  final String? taskHeadline; // Optional task headline for custom title
  final List<int>?
      suggestedCategoryIds; // Suggested category IDs (e.g., from LinkToTask)

  const CategoryPickerDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.defaultCategory,
    required this.onCategorySelected,
    this.showCreateNew = true,
    this.excludeCategory,
    this.showMoveAndCopy = false,
    this.taskHeadline,
    this.suggestedCategoryIds,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    String? subtitle,
    Category? defaultCategory,
    required Function(Category, {bool? shouldMove}) onCategorySelected,
    bool showCreateNew = true,
    Category? excludeCategory,
    bool showMoveAndCopy = false,
    String? taskHeadline,
    List<int>? suggestedCategoryIds,
  }) {
    return showDialog(
      context: context,
      builder: (context) => CategoryPickerDialog(
        title: title,
        subtitle: subtitle,
        defaultCategory: defaultCategory,
        onCategorySelected: onCategorySelected,
        showCreateNew: showCreateNew,
        excludeCategory: excludeCategory,
        showMoveAndCopy: showMoveAndCopy,
        taskHeadline: taskHeadline,
        suggestedCategoryIds: suggestedCategoryIds,
      ),
    );
  }

  @override
  State<CategoryPickerDialog> createState() => _CategoryPickerDialogState();
}

class _CategoryPickerDialogState extends State<CategoryPickerDialog> {
  List<Category> _categories = [];
  List<Category> _recentCategories = [];
  List<Category> _suggestedCategories =
      []; // Categories suggested by LinkToTask
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  Category? _selectedCategory;
  bool _shouldMove = true; // true = move, false = copy

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

      print('CategoryPickerDialog: Loading categories for user: $userId');

      // Load all categories
      final response = await supabase
          .from('Categories')
          .select()
          .eq('owner_id', userId)
          .order('headline');

      print('CategoryPickerDialog: Query completed successfully');

      final categoriesData = response as List<dynamic>;
      final categories =
          categoriesData.map((data) => Category.fromJson(data)).toList();

      // Get recent categories from cache
      final recentCategories = await _getRecentCategories(categories);

      // Get suggested categories if IDs provided
      final suggestedCategories = _getSuggestedCategories(categories);

      setState(() {
        _categories = categories;
        _recentCategories = recentCategories;
        _suggestedCategories = suggestedCategories;
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

  Future<List<Category>> _getRecentCategories(
      List<Category> allCategories) async {
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

  List<Category> _getSuggestedCategories(List<Category> allCategories) {
    if (widget.suggestedCategoryIds == null ||
        widget.suggestedCategoryIds!.isEmpty) {
      return [];
    }

    // Find categories matching the suggested IDs (by original_id)
    final suggested = <Category>[];
    for (final suggestedId in widget.suggestedCategoryIds!) {
      final category =
          allCategories.where((c) => c.originalId == suggestedId).firstOrNull;
      if (category != null) {
        suggested.add(category);
      }
    }

    return suggested;
  }

  List<Category> get _filteredCategories {
    var filtered = _categories;

    // Exclude the default category since it's shown prominently at the top
    if (widget.defaultCategory != null) {
      filtered = filtered
          .where((category) => category.id != widget.defaultCategory!.id)
          .toList();
    }

    // Exclude the specified category if provided
    if (widget.excludeCategory != null) {
      filtered = filtered
          .where((category) => category.id != widget.excludeCategory!.id)
          .toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where((category) => category.headline
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()))
          .toList();
    }

    return filtered;
  }

  List<Category> get _prioritizedCategories {
    final filtered = _filteredCategories;
    final prioritized = <Category>[];
    final remaining = <Category>[];

    // Note: Default category is excluded from filtered list and shown at top,
    // so we don't add it here

    // Add suggested categories (excluding default which is filtered out)
    for (final suggested in _suggestedCategories) {
      if (filtered.contains(suggested) && !prioritized.contains(suggested)) {
        prioritized.add(suggested);
      }
    }

    // Add recent categories (excluding default and suggested if already added)
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
      title: Row(
        children: [
          Expanded(
            child: Text(
              widget.taskHeadline != null
                  ? 'Reassign "${widget.taskHeadline}"'
                  : widget.title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: Column(
          children: [
            // Guidance text (if provided)
            if (widget.subtitle != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  widget.subtitle!,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            // Combined default and suggested categories section
            if (widget.defaultCategory != null ||
                _suggestedCategories.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Current category section
                    if (widget.defaultCategory != null) ...[
                      Text(
                        'Currently:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () => widget.showMoveAndCopy
                            ? _selectCategoryForMoveOrCopy(
                                widget.defaultCategory!)
                            : _selectCategory(widget.defaultCategory!),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star,
                                size: 14,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.defaultCategory!.headline,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    // Recommended categories section
                    if (_suggestedCategories
                        .where((cat) => cat.id != widget.defaultCategory?.id)
                        .isNotEmpty) ...[
                      if (widget.defaultCategory != null)
                        const SizedBox(height: 8),
                      Text(
                        'Suggested:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _suggestedCategories
                            .where(
                                (cat) => cat.id != widget.defaultCategory?.id)
                            .map((category) {
                          return InkWell(
                            onTap: () => widget.showMoveAndCopy
                                ? _selectCategoryForMoveOrCopy(category)
                                : _selectCategory(category),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withOpacity(0.5),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              child: Text(
                                category.headline,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Current category display (if excluding one - for move/copy operations)
            if (widget.excludeCategory != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Currently assigned to:',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.excludeCategory!.headline,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Search field
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText:
                    'Search ${NamingUtils.categoriesName(plural: true)}...',
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

            // Create new category option at the bottom (show if enabled)
            if (widget.showCreateNew && !widget.showMoveAndCopy) ...[
              const SizedBox(height: 6),
              const Divider(height: 1),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '...alternatively ',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  TextButton(
                    onPressed: _createNewCategory,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.green[100],
                      foregroundColor: Colors.green[800],
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Create New ${NamingUtils.categoriesName(plural: false)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.showMoveAndCopy) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Move/Copy toggle
              Row(
                children: [
                  Radio<bool>(
                    value: true,
                    groupValue: _shouldMove,
                    onChanged: (value) {
                      setState(() {
                        _shouldMove = value ?? true;
                      });
                    },
                  ),
                  const Text('Move'),
                  const SizedBox(width: 8),
                  Radio<bool>(
                    value: false,
                    groupValue: _shouldMove,
                    onChanged: (value) {
                      setState(() {
                        _shouldMove = value ?? false;
                      });
                    },
                  ),
                  const Text('Copy'),
                ],
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _selectedCategory != null
                    ? () {
                        Navigator.of(context).pop();
                        // Pass both the category and the action type
                        widget.onCategorySelected(_selectedCategory!,
                            shouldMove: _shouldMove);
                      }
                    : null,
                child: Text(_shouldMove ? 'Move' : 'Copy'),
              ),
            ],
          ),
        ],
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
        final isSuggested =
            _suggestedCategories.contains(category) && !isDefault;
        final isRecent =
            _recentCategories.contains(category) && !isDefault && !isSuggested;

        return ListTile(
          leading:
              _buildCategoryIcon(category, isDefault, isSuggested, isRecent),
          title: Text(
            category.headline,
            style: TextStyle(
              fontWeight: isDefault ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: _buildCategorySubtitle(
              category, isDefault, isSuggested, isRecent),
          onTap: () => widget.showMoveAndCopy
              ? _selectCategoryForMoveOrCopy(category)
              : _selectCategory(category),
          selected:
              widget.showMoveAndCopy && _selectedCategory?.id == category.id,
          dense: true,
        );
      },
    );
  }

  Widget _buildCategoryIcon(
      Category category, bool isDefault, bool isSuggested, bool isRecent) {
    if (isDefault) {
      return Icon(
        Icons.star,
        color: Theme.of(context).colorScheme.primary,
      );
    } else if (isSuggested) {
      return Icon(
        Icons.lightbulb_outline,
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

  Widget? _buildCategorySubtitle(
      Category category, bool isDefault, bool isSuggested, bool isRecent) {
    final labels = <String>[];

    if (isDefault) {
      labels.add('Current');
    }
    if (isSuggested) {
      labels.add('Suggested');
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

  void _selectCategoryForMoveOrCopy(Category category) {
    setState(() {
      _selectedCategory = category;
    });
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
