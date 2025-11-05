import 'package:flutter/material.dart';
import 'package:meaning_to/models/shop_item.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/api_client.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/app_buttons.dart';
import 'package:meaning_to/widgets/link_display.dart';

class ShopEndeavorsScreen extends StatefulWidget {
  final Category?
      existingCategory; // If provided, we're adding tasks to this category

  const ShopEndeavorsScreen({
    super.key,
    this.existingCategory,
  });

  /// Check if there are any public suggestions available
  /// This is a lightweight check used by callers to pre-toggle UI
  static Future<bool> hasAnyPublicSuggestions() async {
    try {
      // Check if there are any public categories with tasks
      final response = await supabase
          .from('Categories')
          .select('id, private')
          .eq('private', false)
          .limit(1);

      if (response.isNotEmpty) {
        // Check if any of these public categories have tasks
        final categoryIds = response.map((json) => json['id'] as int).toList();
        final tasksResponse = await supabase
            .from('Tasks')
            .select('id, original_id')
            .inFilter('category_id', categoryIds)
            .limit(10); // Get more tasks to check filtering

        if (tasksResponse.isNotEmpty) {
          // Filter to only show original tasks (where id equals original_id)
          final originalTasks = tasksResponse.where((task) {
            final taskId = task['id'] as int;
            final originalId = task['original_id'] as int?;
            return originalId != null && taskId == originalId;
          }).toList();

          return originalTasks.isNotEmpty;
        }
      }
      return false;
    } catch (e) {
      // On error, return true to avoid disabling UX unnecessarily
      print('Error checking for public suggestions: $e');
      return true;
    }
  }

  /// Check if there are any public suggestions available for a specific category
  /// This is used by Task Edit screen to check if suggestions exist for the current category
  static Future<bool> hasAnyPublicSuggestionsForCategory(
      Category category) async {
    try {
      if (category.originalId == null) {
        return false; // No original_id means no suggestions
      }

      // Get all categories with the same original_id
      final categoriesResponse = await supabase
          .from('Categories')
          .select('id')
          .eq('original_id', category.originalId!);

      if (categoriesResponse.isEmpty) {
        return false;
      }

      // If there's only one category with this original_id (the current one), no suggestions
      if (categoriesResponse.length == 1) {
        return false;
      }

      // Extract category IDs, excluding the current category
      final categoryIds = (categoriesResponse as List)
          .map((json) => json['id'] as int)
          .where((id) => id != category.id) // Exclude current category
          .toList();

      if (categoryIds.isEmpty) {
        return false; // No other categories with same original_id
      }

      // Get tasks from other categories with the same original_id
      final tasksResponse = await supabase
          .from('Tasks')
          .select('id, original_id')
          .inFilter('category_id', categoryIds)
          .limit(100); // Get more tasks to check filtering

      if (tasksResponse.isNotEmpty) {
        // Filter to only show original tasks (where id equals original_id)
        final originalTasks = tasksResponse.where((task) {
          final taskId = task['id'] as int;
          final originalId = task['original_id'] as int?;
          return originalId != null && taskId == originalId;
        }).toList();

        // If there are original tasks in other categories, we have suggestions
        return originalTasks.isNotEmpty;
      }
      return false;
    } catch (e) {
      // On error, return true to avoid disabling UX unnecessarily
      print('Error checking for public suggestions for category: $e');
      return true;
    }
  }

  @override
  State<ShopEndeavorsScreen> createState() => _ShopEndeavorsScreenState();
}

class _ShopEndeavorsScreenState extends State<ShopEndeavorsScreen> {
  List<ShopItem> _shopItems = [];
  final Map<String, bool> _taskImportSelections =
      {}; // Track task import selections
  bool _isLoading = true;
  String? _error;
  bool _hasShownPrompt = false; // Track if we've shown the prompt
  final Map<String, bool> _redundantTaskCache =
      {}; // Cache for redundant task checks
  final Set<int> _userTaskOriginalIds =
      {}; // Store user's task original_ids for redundancy checking
  final Map<String, bool> _expandedInvitations =
      {}; // Track which category invitations are expanded

  @override
  void initState() {
    super.initState();
    print('ShopEndeavorsScreen: initState called');
    print(
        'ShopEndeavorsScreen: existingCategory: ${widget.existingCategory?.headline}');
    _loadPublicCategories();
    // If we're in Shop Endeavors mode (not "Get Suggestions to..." mode), load user tasks for redundancy checking
    if (widget.existingCategory == null) {
      _loadUserTasksForRedundancyCheck();
    }
  }

  Future<void> _loadPublicCategories() async {
    print('ShopEndeavorsScreen: _loadPublicCategories called');
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // If we have an existing category, only show that category
      if (widget.existingCategory != null) {
        print(
            'ShopEndeavorsScreen: Loading only existing category: ${widget.existingCategory!.headline}');

        // Create a single shop item for the existing category
        final items = [
          ShopItem(
            originalId: widget.existingCategory!.originalId?.toString() ?? '',
            headline: widget.existingCategory!.headline,
            invitation: widget.existingCategory!.invitation,
            categoryIds: [widget.existingCategory!.id.toString()],
            isSelected: true,
            isExpanded: true, // Auto-expand since this is the only category
          ),
        ];

        setState(() {
          _shopItems = items;
          _isLoading = false;
        });

        // Load tasks for the existing category
        if (items.isNotEmpty) {
          await _loadTasksForItem(0);
        }

        print('Loaded 1 category for existing category mode');
        return;
      }

      // Get current user ID
      final userId = AuthUtils.getCurrentUserId();
      final isGuest = AuthUtils.isGuestUser();

      print('ShopEndeavorsScreen: Loading public categories');
      print('ShopEndeavorsScreen: User ID: $userId');
      print('ShopEndeavorsScreen: Is guest: $isGuest');

      // Use API client to get all categories and filter for public ones
      print('ShopEndeavorsScreen: Using API client to get all categories');

      try {
        // Get all categories from Supabase directly
        print(
            'ShopEndeavorsScreen: About to query Supabase for all categories');
        print(
            'ShopEndeavorsScreen: Supabase client auth state: ${supabase.auth.currentUser?.id ?? 'no user'}');

        // Try to get all categories (this will be blocked by RLS if policies are restrictive)
        final allCategories = await supabase.from('Categories').select('*');
        print(
            'ShopEndeavorsScreen: Raw API returned ${allCategories.length} categories');

        // Let's also try a simple query to see if we can access the table at all
        try {
          final testResult =
              await supabase.from('Categories').select('id').limit(1);
          print(
              'ShopEndeavorsScreen: Test query result: ${testResult.length} rows');
        } catch (e) {
          print('ShopEndeavorsScreen: Test query failed: $e');
        }

        // Convert to Category objects
        final categories = (allCategories as List)
            .map((json) => Category.fromJson(json as Map<String, dynamic>))
            .toList();

        print(
            'ShopEndeavorsScreen: Converted to ${categories.length} Category objects');

        // Get user's existing categories to check for original_id conflicts
        final userCategories = await ApiClient.getCategories();
        final userOriginalIds = userCategories
            .where((cat) => cat.originalId != null)
            .map((cat) => cat.originalId!)
            .toSet();

        // Filter to only show public categories that don't belong to the current user
        // AND don't have an original_id that the user already has
        final publicCategories = categories.where((category) {
          final isPublic = !category.isPrivate;
          final isNotOwnedByUser = category.ownerId != userId;
          final userDoesntHaveOriginalId = category.originalId == null ||
              !userOriginalIds.contains(category.originalId);

          print(
              'ShopEndeavorsScreen: Category ${category.headline} - isPublic: $isPublic, isNotOwnedByUser: $isNotOwnedByUser, userDoesntHaveOriginalId: $userDoesntHaveOriginalId (owner: ${category.ownerId}, user: $userId, original_id: ${category.originalId})');

          return isPublic &&
              (isGuest || isNotOwnedByUser) &&
              userDoesntHaveOriginalId;
        }).toList();

        print(
            'ShopEndeavorsScreen: Filtered to ${publicCategories.length} public categories');
        for (final category in publicCategories) {
          print(
              'ShopEndeavorsScreen: Public category: ${category.headline} (owner: ${category.ownerId})');
        }

        // Group categories by original_id
        final Map<String, List<Category>> groupedCategories = {};

        for (final category in publicCategories) {
          final originalId = category.originalId?.toString() ?? '';
          if (!groupedCategories.containsKey(originalId)) {
            groupedCategories[originalId] = [];
          }
          groupedCategories[originalId]!.add(category);
        }

        // Create ShopItem objects from grouped categories
        final List<ShopItem> items = [];

        for (final entry in groupedCategories.entries) {
          final originalId = entry.key;
          final categories = entry.value;

          if (categories.isNotEmpty) {
            // Use the first category's data for headline and invitation
            final firstCategory = categories.first;
            final categoryIds = categories.map((c) => c.id.toString()).toList();

            items.add(ShopItem(
              originalId: originalId,
              headline: firstCategory.headline,
              invitation: firstCategory.invitation,
              categoryIds: categoryIds,
              isSelected: false,
              isExpanded: false,
              tasksLoaded:
                  true, // Tasks are loaded on-demand when expanded, not preloaded
            ));
          }
        }

        setState(() {
          _shopItems = items;
          _isLoading = false;
        });

        // Check which categories have tasks available
        _checkTaskAvailability();

        print('Loaded ${items.length} public categories for shop');
      } catch (e) {
        print('ShopEndeavorsScreen: Error getting categories from API: $e');
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading public categories: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _checkTaskAvailability() async {
    print('ShopEndeavorsScreen: Checking task availability for categories');

    for (int i = 0; i < _shopItems.length; i++) {
      final item = _shopItems[i];

      try {
        if (widget.existingCategory != null) {
          // In "Get Suggestions to..." mode
          final originalId = widget.existingCategory!.originalId;

          if (originalId == null) {
            setState(() {
              _shopItems[i].hasTasksAvailable = false;
            });
            continue;
          }

          // Get all categories with the same original_id
          final categoriesResponse = await supabase
              .from('Categories')
              .select('id')
              .eq('original_id', originalId);

          if (categoriesResponse.isEmpty) {
            setState(() {
              _shopItems[i].hasTasksAvailable = false;
            });
            continue;
          }

          final categoryIds = (categoriesResponse as List)
              .map((json) => json['id'] as int)
              .toList();

          // Count tasks - just check if any exist
          final tasksResponse = await supabase
              .from('Tasks')
              .select('id')
              .inFilter('category_id', categoryIds)
              .limit(1);

          final count = (tasksResponse as List).length;

          setState(() {
            _shopItems[i].hasTasksAvailable = count > 0;
          });

          print(
              'ShopEndeavorsScreen: Category ${item.headline} has $count tasks');
        } else {
          // In "Shop Endeavors" mode - just check if any tasks exist
          final tasksResponse = await supabase
              .from('Tasks')
              .select('id')
              .inFilter('category_id', item.categoryIds)
              .limit(1);

          final count = (tasksResponse as List).length;

          setState(() {
            _shopItems[i].hasTasksAvailable = count > 0;
          });

          print(
              'ShopEndeavorsScreen: Category ${item.headline} has $count tasks');
        }
      } catch (e) {
        print(
            'ShopEndeavorsScreen: Error checking task availability for item $i: $e');
        // Leave hasTasksAvailable as null to show expand icon (fail-safe)
      }
    }
  }

  Future<void> _toggleSelection(int index) async {
    final wasSelected = _shopItems[index].isSelected;
    final willBeSelected = !wasSelected;

    setState(() {
      _shopItems[index].isSelected = willBeSelected;
    });

    // Update task selections based on category selection
    if (_shopItems[index].tasks.isNotEmpty) {
      for (final task in _shopItems[index].tasks) {
        _taskImportSelections[task.id.toString()] = willBeSelected;
      }
    }

    // If category is being selected and not already expanded, expand it
    if (willBeSelected && !_shopItems[index].isExpanded) {
      await _toggleExpansion(index);

      // Show prompt if this is the first time selecting a category
      if (!_hasShownPrompt) {
        _hasShownPrompt = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Now select some suggestions to include.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _toggleExpansion(int index) async {
    final item = _shopItems[index];

    if (!item.isExpanded && item.tasks.isEmpty) {
      // Load tasks when expanding for the first time
      await _loadTasksForItem(index);
    }

    setState(() {
      _shopItems[index].isExpanded = !_shopItems[index].isExpanded;
    });
  }

  Future<void> _loadTasksForItem(int index) async {
    try {
      final item = _shopItems[index];

      // Use direct Supabase query to get tasks
      if (widget.existingCategory != null) {
        // In "Get Suggestions to..." mode, get tasks from all categories with the same original_id
        final originalId = widget.existingCategory!.originalId;
        print(
            'ShopEndeavorsScreen: Loading tasks for categories with original_id: $originalId');

        if (originalId == null) {
          print('ShopEndeavorsScreen: No original_id for existing category');
          setState(() {
            _shopItems[index].tasks = [];
            _shopItems[index].tasksLoaded = true;
            _shopItems[index].isExpanded = false;
          });
          return;
        }

        // First, get all categories with the same original_id
        final categoriesResponse = await supabase
            .from('Categories')
            .select('id')
            .eq('original_id', originalId);

        print(
            'ShopEndeavorsScreen: Found ${categoriesResponse.length} categories with same original_id');

        if (categoriesResponse.isEmpty) {
          print(
              'ShopEndeavorsScreen: No categories found with same original_id');
          setState(() {
            _shopItems[index].tasks = [];
            _shopItems[index].tasksLoaded = true;
            _shopItems[index].isExpanded = false;
          });
          return;
        }

        // Extract category IDs
        final categoryIds = (categoriesResponse as List)
            .map((json) => json['id'] as int)
            .toList();

        print('ShopEndeavorsScreen: Category IDs: $categoryIds');

        // Get tasks from all these categories
        final tasksResponse = await supabase
            .from('Tasks')
            .select('*')
            .inFilter('category_id', categoryIds);

        print(
            'ShopEndeavorsScreen: Raw tasks response: ${tasksResponse.length} tasks');

        // Convert to Task objects
        final List<Task> allTasks = (tasksResponse as List)
            .map((json) => Task.fromJson(json as Map<String, dynamic>))
            .toList();

        // Filter to only show original tasks (where id equals original_id)
        final List<Task> allOriginalTasks =
            allTasks.where((task) => task.id == task.originalId).toList();

        print(
            'ShopEndeavorsScreen: Original tasks: ${allOriginalTasks.length}');

        // Filter out redundant tasks (tasks that already exist in the current category)
        final List<Task> filteredTasks =
            allOriginalTasks.where((task) => !_isTaskRedundant(task)).toList();

        print('ShopEndeavorsScreen: Filtered tasks: ${filteredTasks.length}');

        setState(() {
          _shopItems[index].tasks = filteredTasks;
          _shopItems[index].tasksLoaded = true;
          // If no tasks found, collapse the item
          if (filteredTasks.isEmpty) {
            _shopItems[index].isExpanded = false;
          }
          // Initialize import selections for new tasks
          // If the category is selected, select all tasks by default
          final shouldSelectAll = _shopItems[index].isSelected;
          for (final task in filteredTasks) {
            _taskImportSelections[task.id.toString()] = shouldSelectAll;
          }
          // Clear redundant task cache when tasks are reloaded
          _redundantTaskCache.clear();
        });

        print(
            'Loaded ${filteredTasks.length} tasks for original_id: $originalId');
        return;
      } else {
        // In "Shop Endeavors" mode, get tasks from all categories with this original_id
        print(
            'ShopEndeavorsScreen: Loading tasks for categories: ${item.categoryIds}');

        final tasksResponse = await supabase
            .from('Tasks')
            .select('*')
            .inFilter('category_id', item.categoryIds);

        print(
            'ShopEndeavorsScreen: Raw tasks response: ${tasksResponse.length} tasks');

        // Convert to Task objects
        final List<Task> allTasks = (tasksResponse as List)
            .map((json) => Task.fromJson(json as Map<String, dynamic>))
            .toList();

        // Filter to only show original tasks (where id equals original_id)
        final List<Task> allOriginalTasks =
            allTasks.where((task) => task.id == task.originalId).toList();

        print(
            'ShopEndeavorsScreen: Original tasks: ${allOriginalTasks.length}');

        // Filter out redundant tasks (only in Shop Endeavors mode)
        final List<Task> filteredTasks =
            allOriginalTasks.where((task) => !_isTaskRedundant(task)).toList();

        print('ShopEndeavorsScreen: Filtered tasks: ${filteredTasks.length}');

        setState(() {
          _shopItems[index].tasks = filteredTasks;
          _shopItems[index].tasksLoaded = true;
          // If no tasks found, collapse the item
          if (filteredTasks.isEmpty) {
            _shopItems[index].isExpanded = false;
          }
          // Initialize import selections for new tasks
          // If the category is selected, select all tasks by default
          final shouldSelectAll = _shopItems[index].isSelected;
          for (final task in filteredTasks) {
            _taskImportSelections[task.id.toString()] = shouldSelectAll;
          }
          // Clear redundant task cache when tasks are reloaded
          _redundantTaskCache.clear();
        });

        print(
            'Loaded ${filteredTasks.length} tasks for original_id: ${item.originalId}');
      }
    } catch (e) {
      print('Error loading tasks for item $index: $e');
      // Don't show error to user, just log it
    }
  }

  void _toggleTaskImportSelection(String taskId) {
    setState(() {
      _taskImportSelections[taskId] = !(_taskImportSelections[taskId] ?? false);

      // If a task is being selected, automatically select its category
      if (_taskImportSelections[taskId] == true) {
        // Find the category that contains this task
        for (int i = 0; i < _shopItems.length; i++) {
          final item = _shopItems[i];
          if (item.tasks.any((task) => task.id.toString() == taskId)) {
            _shopItems[i].isSelected = true;
            break;
          }
        }
      }
    });
  }

  void _toggleSelectAllTasks(int itemIndex) {
    final item = _shopItems[itemIndex];
    final bool allTasksSelected = _areAllTasksSelected(itemIndex);

    // If all tasks are selected, deselect all. Otherwise, select all.
    final bool shouldSelectAll = !allTasksSelected;

    setState(() {
      for (final task in item.tasks) {
        _taskImportSelections[task.id.toString()] = shouldSelectAll;
      }
      // If selecting tasks, ensure category is selected
      // If deselecting tasks, keep category selected (user can manually deselect category if desired)
      if (shouldSelectAll) {
        _shopItems[itemIndex].isSelected = true;
      }
      // Note: We don't automatically deselect the category when deselecting all tasks
    });
  }

  bool _areAllTasksSelected(int itemIndex) {
    final item = _shopItems[itemIndex];
    if (item.tasks.isEmpty) return false;

    return item.tasks
        .every((task) => _taskImportSelections[task.id.toString()] == true);
  }

  bool _areSomeTasksSelected(int itemIndex) {
    final item = _shopItems[itemIndex];
    if (item.tasks.isEmpty) return false;

    return item.tasks
        .any((task) => _taskImportSelections[task.id.toString()] == true);
  }

  void _toggleInvitationExpansion(String itemId) {
    setState(() {
      _expandedInvitations[itemId] = !(_expandedInvitations[itemId] ?? false);
    });
  }

  Widget? _buildInvitationWidget(ShopItem item) {
    if (item.invitation == null || item.invitation!.isEmpty) {
      return null;
    }

    const int maxLength = 200;
    final bool isExpanded = _expandedInvitations[item.originalId] ?? false;
    final bool needsTruncation = item.invitation!.length > maxLength;

    final String displayText = needsTruncation && !isExpanded
        ? '${item.invitation!.substring(0, maxLength)}...'
        : item.invitation!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 0.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
          ),
          if (needsTruncation)
            TextButton(
              onPressed: () => _toggleInvitationExpansion(item.originalId),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                isExpanded ? '(Less)' : '(More)',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Check if a task is redundant (has same original_id as existing task)
  bool _isTaskRedundant(Task task) {
    if (task.originalId == null) return false;

    final cacheKey =
        '${task.originalId}_${widget.existingCategory?.id ?? 'all'}';

    // Check cache first
    if (_redundantTaskCache.containsKey(cacheKey)) {
      return _redundantTaskCache[cacheKey]!;
    }

    bool isRedundant = false;

    if (widget.existingCategory != null) {
      // "Get Suggestions to..." mode - check only within current category
      final cacheManager = CacheManager();
      final existingTasks = cacheManager.currentTasks ?? [];

      isRedundant = existingTasks.any((existingTask) =>
          existingTask.originalId != null &&
          existingTask.originalId == task.originalId);
    } else {
      // "Shop Endeavors" mode - check against pre-loaded user tasks
      // This should have been populated by _loadUserTasksForRedundancyCheck
      isRedundant = _userTaskOriginalIds.contains(task.originalId);
    }

    // Cache the result
    _redundantTaskCache[cacheKey] = isRedundant;

    return isRedundant;
  }

  /// Check if we should show the "Nothing Found!" alert
  bool _shouldShowNoSuggestionsAlert() {
    // Only show this alert in "Get Suggestions to..." mode when there are no tasks
    if (widget.existingCategory == null) return false;

    // Check if any shop item has tasks
    for (final item in _shopItems) {
      if (item.tasks.isNotEmpty) {
        return false; // Found tasks, don't show alert
      }
      // Don't show alert if tasks haven't been loaded yet
      if (!item.tasksLoaded) {
        return false; // Still loading tasks, don't show alert yet
      }
    }

    return true; // No tasks found and all tasks loaded, show alert
  }

  /// Get filtered tasks for a given original_id and owner_id
  /// This method encapsulates the query logic used by _loadTasksForItem
  static Future<List<Task>> getFilteredTasksForOriginalId(
    int originalId,
    String ownerId,
  ) async {
    try {
      // First, get all categories with the same original_id
      final categoriesResponse = await supabase
          .from('Categories')
          .select('id')
          .eq('original_id', originalId);

      if (categoriesResponse.isEmpty) {
        return [];
      }

      // Extract category IDs
      final categoryIds = (categoriesResponse as List)
          .map((json) => json['id'] as int)
          .toList();

      // Get tasks from all these categories
      final tasksResponse = await supabase
          .from('Tasks')
          .select('*')
          .inFilter('category_id', categoryIds);

      // Convert to Task objects
      final List<Task> allTasks = (tasksResponse as List)
          .map((json) => Task.fromJson(json as Map<String, dynamic>))
          .toList();

      // Filter to only show original tasks (where id equals original_id)
      final List<Task> allOriginalTasks =
          allTasks.where((task) => task.id == task.originalId).toList();

      // Filter out tasks that belong to the current owner (to avoid showing their own tasks)
      final List<Task> filteredTasks =
          allOriginalTasks.where((task) => task.ownerId != ownerId).toList();

      return filteredTasks;
    } catch (e) {
      print('Error getting filtered tasks for original_id $originalId: $e');
      return [];
    }
  }

  /// Load user's task original_ids for redundancy checking in Shop Endeavors mode
  Future<void> _loadUserTasksForRedundancyCheck() async {
    try {
      final userId = AuthUtils.getCurrentUserId();

      // Use API client to get all tasks owned by the current user
      final tasks = await ApiClient.getTasks();

      // Extract original_ids from tasks
      final originalIds = tasks
          .where((task) => task.originalId != null)
          .map((task) => task.originalId!)
          .toSet();

      setState(() {
        _userTaskOriginalIds.clear();
        _userTaskOriginalIds.addAll(originalIds);
      });

      print(
          'Loaded ${_userTaskOriginalIds.length} user task original_ids for redundancy checking');
    } catch (e) {
      print('Error loading user tasks for redundancy check: $e');
    }
  }

  Future<void> _addSelectedTasksToCategory() async {
    try {
      final userId = AuthUtils.getCurrentUserId();

      if (widget.existingCategory == null) {
        throw Exception('No existing category provided');
      }

      // Get all selected tasks from all shop items
      final selectedTasks = <Task>[];
      for (final item in _shopItems) {
        final itemSelectedTasks = item.tasks
            .where((task) => _taskImportSelections[task.id.toString()] == true)
            .toList();
        selectedTasks.addAll(itemSelectedTasks);
      }

      if (selectedTasks.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No tasks selected for import'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

      int importedTasks = 0;
      int skippedTasks = 0;
      Task? lastAddedTask; // Track the last task we actually added

      // Initialize cache manager for the current category only if not already loaded
      final cacheManager = CacheManager();
      if (cacheManager.currentCategory?.id != widget.existingCategory!.id) {
        await cacheManager.initializeWithSavedCategory(
            widget.existingCategory!, userId);
      }

      for (final task in selectedTasks) {
        // Check for redundancy - find existing task with same original_id
        final existingTasks = cacheManager.currentTasks ?? [];
        final existingTask = existingTasks
            .where((existingTask) =>
                existingTask.originalId != null &&
                task.originalId != null &&
                existingTask.originalId == task.originalId)
            .firstOrNull;

        if (existingTask != null) {
          print(
              'ShopEndeavorsScreen: Found duplicate task "${task.headline}" with original_id ${task.originalId}');
          print(
              'ShopEndeavorsScreen: Copying links from redundant task to existing task "${existingTask.headline}"');

          // Copy links from redundant task to existing task using ensureLink
          if (task.links != null && task.links!.isNotEmpty) {
            for (final link in task.links!) {
              final error = existingTask.ensureLink(link);
              if (error != null) {
                print(
                    'ShopEndeavorsScreen: Link already exists in existing task: $error');
              } else {
                print(
                    'ShopEndeavorsScreen: Successfully copied link from redundant task to existing task');
              }
            }

            // Update the existing task in the cache after adding links
            await cacheManager.updateTask(existingTask);
          }

          skippedTasks++;
          continue;
        }

        // Create new task object with the existing category's ID
        final newTask = Task(
          id: DateTime.now().millisecondsSinceEpoch, // Temporary ID
          categoryId: widget.existingCategory!.id,
          headline: task.headline,
          notes: task.notes,
          ownerId: userId,
          createdAt: DateTime.now(),
          suggestibleAt: task.suggestibleAt,
          triggersAt: task.triggersAt,
          deferral: task.deferral,
          links: task.links,
          processedLinks: task.processedLinks,
          finished: false, // Start as unfinished
          originalId:
              task.originalId, // Copy the original_id from the source task
        );

        // Store the task we're about to add
        lastAddedTask = newTask;
        
        // Use CacheManager to add the task (saves to database and updates cache)
        await cacheManager.addTask(newTask);
        importedTasks++;
      }

      setState(() {
        _isLoading = false;
      });

      print(
          'ShopEndeavorsScreen: Added $importedTasks tasks to cache and database (skipped $skippedTasks duplicates)');

      // Navigate back with appropriate result based on number of tasks added
      if (mounted) {
        if (importedTasks == 1 && lastAddedTask != null) {
          // Single task - show dialog with the task we just added
          print(
              'ShopEndeavorsScreen: Showing dialog for added task: "${lastAddedTask!.headline}"');

          // Show popup dialog
          final shouldGoHome = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext dialogContext) {
              return AlertDialog(
                title: Text(
                  '${NamingUtils.tasksName(capitalize: true, plural: false)} Added!',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Successfully added:',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      lastAddedTask!.headline,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'What would you like to do?',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                actions: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    style: AppButtons.goForthOutlined(),
                    child: Text(
                        'Add More ${NamingUtils.tasksName(capitalize: true)}'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    style: AppButtons.finalize(),
                    child: const Text('Go to Home Screen'),
                  ),
                ],
              );
            },
          );

          // Navigate based on user choice
          if (shouldGoHome == true && mounted) {
            // Pop all the way back to home screen (first route)
            Navigator.of(context).popUntil((route) => route.isFirst);
          } else if (mounted) {
            // Just pop this screen to go back to New Content screen
            Navigator.pop(context);
          }
        } else {
          // Multiple tasks - show SnackBar with success message
          String message;
          if (skippedTasks > 0) {
            message =
                'Added $importedTasks tasks to ${widget.existingCategory!.headline}! (Skipped $skippedTasks duplicates, copied links)';
          } else {
            message =
                'Successfully added $importedTasks tasks to ${widget.existingCategory!.headline}!';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );

          // Return simple true for multiple tasks
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      print('Error adding tasks to category: $e');
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding tasks: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _importSelectedCategories() async {
    try {
      final userId = AuthUtils.getCurrentUserId();

      final selectedItems =
          _shopItems.where((item) => item.isSelected).toList();
      if (selectedItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No categories selected for import'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

      int importedCategories = 0;
      int importedTasks = 0;

      for (final item in selectedItems) {
        // Create new category (since we filtered out existing ones)
        final newCategoryData = {
          'headline': item.headline,
          'invitation': item.invitation,
          'owner_id': userId,
          'original_id': item.originalId,
          'private': false, // Default to public
        };

        final newCategory = await ApiClient.createCategory(newCategoryData);
        final categoryId = newCategory.id.toString();
        importedCategories++;
        print(
            'Created new category $categoryId for original_id ${item.originalId}');

        // Import selected tasks for this category
        final selectedTaskIds = item.tasks
            .where((task) => _taskImportSelections[task.id.toString()] == true)
            .map((task) => task.id.toString())
            .toList();

        if (selectedTaskIds.isNotEmpty) {
          // Get the specific tasks by ID (they belong to other users, so can't use getTasks())
          final originalTasks = <Task>[];
          for (final taskId in selectedTaskIds) {
            try {
              final task = await ApiClient.getTask(taskId);
              if (task != null) {
                originalTasks.add(task);
              } else {
                print('ShopEndeavorsScreen: Task $taskId not found');
              }
            } catch (e) {
              print('ShopEndeavorsScreen: Error fetching task $taskId: $e');
            }
          }

          // Track original_ids to prevent duplicates within this import
          final importedOriginalIds = <int>{};

          for (final originalTask in originalTasks) {
            // Check for duplicate original_id within this import
            if (originalTask.originalId != null &&
                importedOriginalIds.contains(originalTask.originalId)) {
              print(
                  'ShopEndeavorsScreen: Skipping duplicate task "${originalTask.headline}" with original_id ${originalTask.originalId} in category import');
              continue;
            }

            // Create new task with user's category_id
            final newTaskData = {
              'headline': originalTask.headline,
              'notes': originalTask.notes,
              'links': originalTask.links,
              'triggers_at': originalTask.triggersAt?.toIso8601String(),
              'suggestible_at': originalTask.suggestibleAt?.toIso8601String(),
              'finished': false, // Start as unfinished
              'category_id': categoryId,
              'owner_id': userId,
              'original_id': originalTask
                  .originalId, // Copy the original_id from the source task
            };

            await ApiClient.createTask(newTaskData);

            // Track this original_id to prevent future duplicates
            if (originalTask.originalId != null) {
              importedOriginalIds.add(originalTask.originalId!);
            }

            importedTasks++;
          }
        }
      }

      setState(() {
        _isLoading = false;
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully imported $importedCategories categories and $importedTasks tasks!',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );

        // Navigate back to home screen with result indicating categories were imported
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      print('Error importing categories: $e');
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing categories: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Widget _buildTaskCard(Task task) {
    final isSelected = _taskImportSelections[task.id.toString()] ?? false;
    final hasLinks = task.links != null &&
        task.links!.isNotEmpty &&
        task.links!.first.contains('href="');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    task.headline,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Checkbox(
                  value: isSelected,
                  onChanged: (_) =>
                      _toggleTaskImportSelection(task.id.toString()),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (task.notes != null && task.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                task.notes!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ],
            if (hasLinks) ...[
              const SizedBox(height: 8),
              ...task.links!.map((link) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: LinkDisplay(
                      linkText: link,
                      showIcon: true,
                      showTitle: true,
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingCategory != null
            ? 'Get Suggestions to...'
            : 'Shop ${NamingUtils.categoriesName(plural: true)}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading categories',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadPublicCategories,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _shopItems.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.shopping_cart_outlined,
                                size: 64,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No public ${NamingUtils.categoriesName(plural: true)} available',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Check back later for new ${NamingUtils.categoriesName(plural: true)}!',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _shopItems.any((item) => !item.tasksLoaded)
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 16),
                                  Text('Loading available tasks...'),
                                ],
                              ),
                            )
                          : _shouldShowNoSuggestionsAlert()
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.search_off,
                                        size: 64,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Nothing Found!',
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'You\'ve already taken on all the suggestions there are.',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 24),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(context),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 24,
                                            vertical: 12,
                                          ),
                                        ),
                                        child: const Text(
                                          'Return',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      16.0, 16.0, 16.0, 80.0),
                                  itemCount: _shopItems.length,
                                  itemBuilder: (context, index) {
                                    final item = _shopItems[index];
                                    return Card(
                                      margin:
                                          const EdgeInsets.only(bottom: 8.0),
                                      child: Column(
                                        children: [
                                          ListTile(
                                            title: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                // Headline row with checkbox and expand functionality
                                                widget.existingCategory != null
                                                    ? Row(
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              item.headline,
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 20,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Colors
                                                                    .black,
                                                              ),
                                                            ),
                                                          ),
                                                          if (item.hasTasksAvailable ==
                                                                  null ||
                                                              item.hasTasksAvailable ==
                                                                  true)
                                                            GestureDetector(
                                                              onTap: () =>
                                                                  _toggleExpansion(
                                                                      index),
                                                              child: Icon(
                                                                item.isExpanded
                                                                    ? Icons
                                                                        .expand_less
                                                                    : Icons
                                                                        .expand_more,
                                                                color:
                                                                    Colors.grey,
                                                              ),
                                                            ),
                                                        ],
                                                      )
                                                    : Row(
                                                        children: [
                                                          Checkbox(
                                                            value:
                                                                item.isSelected,
                                                            onChanged: (_) =>
                                                                _toggleSelection(
                                                                    index),
                                                            materialTapTargetSize:
                                                                MaterialTapTargetSize
                                                                    .shrinkWrap,
                                                            visualDensity:
                                                                VisualDensity
                                                                    .compact,
                                                          ),
                                                          const SizedBox(
                                                              width: 8),
                                                          Expanded(
                                                            child: Text(
                                                              item.headline,
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 20,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Colors
                                                                    .black,
                                                              ),
                                                            ),
                                                          ),
                                                          if (item.hasTasksAvailable ==
                                                                  null ||
                                                              item.hasTasksAvailable ==
                                                                  true)
                                                            GestureDetector(
                                                              onTap: () =>
                                                                  _toggleExpansion(
                                                                      index),
                                                              child: Icon(
                                                                item.isExpanded
                                                                    ? Icons
                                                                        .expand_less
                                                                    : Icons
                                                                        .expand_more,
                                                                color:
                                                                    Colors.grey,
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                // Add invitation below headline
                                                if (_buildInvitationWidget(
                                                        item) !=
                                                    null)
                                                  _buildInvitationWidget(item)!,
                                                // Show "No suggestions" text immediately if no tasks available
                                                if (item.hasTasksAvailable ==
                                                    false)
                                                  Padding(
                                                    padding: const EdgeInsets
                                                        .fromLTRB(
                                                        16.0, 8.0, 16.0, 0.0),
                                                    child: Text(
                                                      '(Your ${NamingUtils.tasksName()} here)',
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                        color: Colors.grey,
                                                        fontStyle:
                                                            FontStyle.italic,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          if (widget.existingCategory != null ||
                                              item.isExpanded) ...[
                                            if (item.tasks.isNotEmpty) ...[
                                              Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                        16.0, 0.0, 16.0, 16.0),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    widget.existingCategory ==
                                                            null
                                                        ? Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        20.0),
                                                            child: Row(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .spaceBetween,
                                                              children: [
                                                                Text(
                                                                  'Suggestions:',
                                                                  style: Theme.of(
                                                                          context)
                                                                      .textTheme
                                                                      .bodySmall
                                                                      ?.copyWith(
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                        fontStyle:
                                                                            FontStyle.italic,
                                                                        color: Colors
                                                                            .grey[700],
                                                                        fontSize:
                                                                            (Theme.of(context).textTheme.bodySmall?.fontSize ?? 12) +
                                                                                4,
                                                                      ),
                                                                ),
                                                                Checkbox(
                                                                  value: _areAllTasksSelected(
                                                                          index)
                                                                      ? true
                                                                      : _areSomeTasksSelected(
                                                                              index)
                                                                          ? null
                                                                          : false,
                                                                  tristate:
                                                                      true,
                                                                  onChanged: (_) =>
                                                                      _toggleSelectAllTasks(
                                                                          index),
                                                                  materialTapTargetSize:
                                                                      MaterialTapTargetSize
                                                                          .shrinkWrap,
                                                                  visualDensity:
                                                                      VisualDensity
                                                                          .compact,
                                                                ),
                                                              ],
                                                            ),
                                                          )
                                                        : Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        20.0),
                                                            child: Row(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .end,
                                                              children: [
                                                                Checkbox(
                                                                  value: _areAllTasksSelected(
                                                                          index)
                                                                      ? true
                                                                      : _areSomeTasksSelected(
                                                                              index)
                                                                          ? null
                                                                          : false,
                                                                  tristate:
                                                                      true,
                                                                  onChanged: (_) =>
                                                                      _toggleSelectAllTasks(
                                                                          index),
                                                                  materialTapTargetSize:
                                                                      MaterialTapTargetSize
                                                                          .shrinkWrap,
                                                                  visualDensity:
                                                                      VisualDensity
                                                                          .compact,
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                    const SizedBox(height: 8),
                                                    ...item.tasks
                                                        .map((task) =>
                                                            _buildTaskCard(
                                                                task))
                                                        .toList(),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                ),
      floatingActionButton: _shopItems.isNotEmpty &&
              !_shouldShowNoSuggestionsAlert() &&
              _shopItems.any((item) => item.isSelected)
          ? SizedBox(
              height: 40, // Reduced from default 56 to 44 (12 points shorter)
              child: FloatingActionButton.extended(
                heroTag: 'importButton',
                onPressed: _isLoading
                    ? null
                    : (widget.existingCategory != null
                        ? _addSelectedTasksToCategory
                        : _importSelectedCategories),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                icon: Icon(
                  widget.existingCategory != null
                      ? Icons.add_task
                      : Icons.download,
                  size: 24,
                ),
                label: Text(
                  widget.existingCategory != null
                      ? 'Add Selected Tasks'
                      : 'Import Selected',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
