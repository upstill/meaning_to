import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/category_ordering.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/new_category_screen.dart';

/// Dialog for selecting a category with smart defaults and recent category prioritization
class CategoryPickerDialog extends StatefulWidget {
  final String title;
  final String? subtitle; // Optional guidance text shown at the top
  final Category? defaultCategory;
  final Function(Category, {bool? shouldMove, bool? applyToAll}) onCategorySelected;
  final bool showCreateNew;
  final Category? excludeCategory; // Category to exclude from the list
  final bool showMoveAndCopy; // Show move/copy buttons instead of create new
  final String? taskHeadline; // Optional task headline for custom title
  final List<int>?
      suggestedCategoryIds; // Suggested category IDs (e.g., from LinkToTask)
  final String? linkUrl; // Optional link URL for domain-based relevance scoring
  final bool showApplyToAllCheckbox; // Show "apply to all remaining" checkbox
  final bool hideShared; // Suppress the "Shared with you" section
  final String? topButtonLabel; // Prominent first-item button label
  final VoidCallback? topButtonOnPressed; // Action for the top button

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
    this.linkUrl,
    this.showApplyToAllCheckbox = false,
    this.hideShared = false,
    this.topButtonLabel,
    this.topButtonOnPressed,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    String? subtitle,
    Category? defaultCategory,
    required Function(Category, {bool? shouldMove, bool? applyToAll}) onCategorySelected,
    bool showCreateNew = true,
    Category? excludeCategory,
    bool showMoveAndCopy = false,
    String? taskHeadline,
    List<int>? suggestedCategoryIds,
    String? linkUrl,
    bool showApplyToAllCheckbox = false,
    bool hideShared = false,
    String? topButtonLabel,
    VoidCallback? topButtonOnPressed,
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
        linkUrl: linkUrl,
        showApplyToAllCheckbox: showApplyToAllCheckbox,
        hideShared: hideShared,
        topButtonLabel: topButtonLabel,
        topButtonOnPressed: topButtonOnPressed,
      ),
    );
  }

  @override
  State<CategoryPickerDialog> createState() => _CategoryPickerDialogState();
}

class _CategoryPickerDialogState extends State<CategoryPickerDialog> {
  List<Category> _categories = [];
  List<Category> _sharedCategories = []; // Categories shared with the user
  List<Category> _recentCategories = [];
  List<Category> _suggestedCategories =
      []; // Categories suggested by LinkToTask
  Map<int, int> _domainRelevanceScores = {}; // Category ID -> relevance count
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  Category? _selectedCategory;
  bool _shouldMove = true; // true = move, false = copy
  bool _applyToAll = false; // Apply category to all remaining links

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

      print('CategoryPickerDialog: Loading categories');

      // Use ApiClient which returns owned + shared categories (with isShared set)
      final allCategories = await ApiClient.getCategories();

      // Split into owned and shared
      final ownedCategories =
          allCategories.where((c) => !c.isShared).toList();
      final sharedCategories =
          allCategories.where((c) => c.isShared).toList();

      print('CategoryPickerDialog: ${ownedCategories.length} owned, '
          '${sharedCategories.length} shared');

      // Rank signals (recent/suggested/domain) via the shared utility so this
      // picker and the TaskEditScreen pursuit selector order pursuits identically.
      final ordering = await orderCategoriesBySensibility(
        ownedCategories,
        suggestedOriginalIds: widget.suggestedCategoryIds,
        linkUrl: widget.linkUrl,
      );

      setState(() {
        _categories = ownedCategories;
        _sharedCategories = sharedCategories;
        _recentCategories = ordering.recent;
        _suggestedCategories = ordering.suggested;
        _domainRelevanceScores = ordering.domainScores;
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

  /// Total list items available, ignoring the current search query.
  /// Used to decide whether to show the search box and list section.
  int get _baseListCount {
    int count = _categories.where((c) {
      if (widget.defaultCategory?.id == c.id) return false;
      if (widget.excludeCategory?.id == c.id) return false;
      if (_suggestedCategories.any((s) => s.id == c.id)) return false;
      return true;
    }).length;
    if (!widget.hideShared) count += _sharedCategories.length;
    return count;
  }

  /// Whether there is anything at all to pick — the default, any suggested, or
  /// any other pursuit. Guards the picker body so it isn't hidden when the only
  /// choices happen to be the default/suggested ones (which _baseListCount omits).
  bool get _hasAnyChoice =>
      widget.defaultCategory != null ||
      _suggestedCategories.isNotEmpty ||
      _baseListCount > 0;

  List<Category> get _filteredCategories {
    var filtered = _categories;

    // Exclude the default category since it's shown prominently at the top
    if (widget.defaultCategory != null) {
      filtered = filtered
          .where((category) => category.id != widget.defaultCategory!.id)
          .toList();
    }

    // Exclude suggested categories since they're shown prominently at the top
    if (_suggestedCategories.isNotEmpty) {
      final suggestedIds = _suggestedCategories.map((c) => c.id).toSet();
      filtered = filtered
          .where((category) => !suggestedIds.contains(category.id))
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

    // Sort remaining categories by domain relevance score (highest first)
    if (_domainRelevanceScores.isNotEmpty) {
      remaining.sort((a, b) {
        final scoreA = _domainRelevanceScores[a.id] ?? 0;
        final scoreB = _domainRelevanceScores[b.id] ?? 0;
        // Sort by score descending, then by headline ascending as tiebreaker
        if (scoreB != scoreA) {
          return scoreB.compareTo(scoreA);
        }
        return a.headline.compareTo(b.headline);
      });
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
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top quick-pick row: smart button + "A New Pursuit" side by side
            if (widget.topButtonLabel != null) ...[
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.topButtonOnPressed?.call();
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.green[100],
                    foregroundColor: Colors.green[800],
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 16),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    widget.topButtonLabel!,
                    style: const TextStyle(fontSize: 15.6),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _createNewCategory,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.blue[100],
                    foregroundColor: Colors.blue[800],
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 16),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'A New ${NamingUtils.categoriesName(capitalize: true, plural: false)}',
                    style: const TextStyle(fontSize: 15.6),
                  ),
                ),
              ),
            ],

            // Everything below the divider only when there are pursuits to offer
            if (!_isLoading && _hasAnyChoice) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
            ],

            // Guidance text (if provided)
            if (!_isLoading && _hasAnyChoice && widget.subtitle != null) ...[
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
            if (!_isLoading &&
                (widget.defaultCategory != null ||
                    _suggestedCategories.isNotEmpty)) ...[
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
            if (!_isLoading && _baseListCount > 0 &&
                widget.excludeCategory != null) ...[
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

            // Search field — only when more than 4 choices are available
            if (!_isLoading && _baseListCount > 4) ...[
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
            ],

            // Categories list — only when there are choices to show
            if (!_isLoading && _baseListCount > 0)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: _buildCategoriesList(),
              ),

            // "Apply to all remaining links" checkbox (show if enabled)
            if (widget.showApplyToAllCheckbox) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                title: const Text(
                  'Same category for remaining links',
                  style: TextStyle(fontSize: 14),
                ),
                value: _applyToAll,
                onChanged: (value) {
                  setState(() {
                    _applyToAll = value ?? false;
                  });
                },
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],

            // Create new category option at the bottom (show if enabled and
            // not already shown in the top quick-pick row)
            if (widget.showCreateNew &&
                !widget.showMoveAndCopy &&
                widget.topButtonLabel == null) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '...alternatively, ',
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  TextButton(
                    onPressed: _createNewCategory,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.green[100],
                      foregroundColor: Colors.green[800],
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
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

    // Filter shared categories by search query (suppressed when hideShared is set)
    final filteredShared = widget.hideShared
        ? <Category>[]
        : _searchQuery.isEmpty
            ? _sharedCategories
            : _sharedCategories
                .where((c) => c.headline
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase()))
                .toList();

    if (categories.isEmpty && filteredShared.isEmpty) {
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
                  ? 'No ${NamingUtils.categoriesName(plural: true)} match your search'
                  : 'No ${NamingUtils.categoriesName(plural: true)} found',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final ownedItemCount = categories.length;
    final sharedHeaderIndex =
        filteredShared.isNotEmpty ? ownedItemCount : -1;
    final totalCount = ownedItemCount +
        (filteredShared.isNotEmpty ? 1 + filteredShared.length : 0);

    return ListView.builder(
      itemCount: totalCount,
      itemBuilder: (context, index) {
        // "Shared with you" header
        if (index == sharedHeaderIndex) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(Icons.people,
                    size: 16,
                    color: Theme.of(context).colorScheme.secondary),
                const SizedBox(width: 6),
                Text(
                  'Shared with you',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ],
            ),
          );
        }

        // Shared category items
        if (filteredShared.isNotEmpty && index > sharedHeaderIndex) {
          final sharedCategory = filteredShared[index - sharedHeaderIndex - 1];
          return ListTile(
            leading: Icon(Icons.people,
                color: Theme.of(context).colorScheme.secondary),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(sharedCategory.headline),
                Text(
                  'from ${sharedCategory.ownerName}',
                  style: TextStyle(
                    fontSize: (Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14) * 0.7,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            onTap: () => widget.showMoveAndCopy
                ? _selectCategoryForMoveOrCopy(sharedCategory)
                : _selectCategory(sharedCategory),
            selected: widget.showMoveAndCopy &&
                _selectedCategory?.id == sharedCategory.id,
            dense: true,
          );
        }

        // Owned category items
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

    // Add relevance score if available and greater than 0
    final score = _domainRelevanceScores[category.id];
    if (score != null && score > 0) {
      labels.add('$score match${score == 1 ? '' : 'es'}');
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
    widget.onCategorySelected(category, applyToAll: _applyToAll);
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
      widget.onCategorySelected(result, applyToAll: _applyToAll);
    }
  }
}
