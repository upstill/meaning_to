import 'package:flutter/material.dart';
import 'package:meaning_to/models/shop_item.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/widgets/link_display.dart';

class ShopEndeavorsScreen extends StatefulWidget {
  final Category?
      existingCategory; // If provided, we're adding tasks to this category

  const ShopEndeavorsScreen({
    super.key,
    this.existingCategory,
  });

  @override
  State<ShopEndeavorsScreen> createState() => _ShopEndeavorsScreenState();
}

class _ShopEndeavorsScreenState extends State<ShopEndeavorsScreen> {
  List<ShopItem> _shopItems = [];
  Map<String, bool> _taskImportSelections = {}; // Track task import selections
  bool _isLoading = true;
  String? _error;
  bool _hasShownPrompt = false; // Track if we've shown the prompt

  @override
  void initState() {
    super.initState();
    _loadPublicCategories();
  }

  Future<void> _loadPublicCategories() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Get current user ID
      final userId = AuthUtils.getCurrentUserId();
      if (userId == null) {
        throw Exception('No user logged in');
      }

      // Build the query based on mode
      var query = supabase
          .from('Categories')
          .select('id, headline, invitation, original_id')
          .eq('private', false)
          .neq('owner_id', userId);

      // If we have an existing category, only show categories with the same original_id
      if (widget.existingCategory != null &&
          widget.existingCategory!.originalId != null) {
        query = query.eq(
            'original_id', widget.existingCategory!.originalId.toString());
      }

      final response = await query.order('headline');

      if (response == null) {
        throw Exception('No response from database');
      }

      // Group categories by original_id
      final Map<String, List<Map<String, dynamic>>> groupedCategories = {};

      for (final json in response as List) {
        final categoryData = json as Map<String, dynamic>;
        final originalId = categoryData['original_id']?.toString() ?? '';
        final categoryId = categoryData['id'].toString();

        if (!groupedCategories.containsKey(originalId)) {
          groupedCategories[originalId] = [];
        }
        groupedCategories[originalId]!.add(categoryData);
      }

      // Create ShopItem objects from grouped categories
      final List<ShopItem> items = [];

      for (final entry in groupedCategories.entries) {
        final originalId = entry.key;
        final categories = entry.value;

        if (categories.isNotEmpty) {
          // Use the first category's data for headline and invitation
          final firstCategory = categories.first;
          final categoryIds =
              categories.map((c) => c['id'].toString()).toList();

          // If we have an existing category, automatically select this item
          final isSelected = widget.existingCategory != null;

          items.add(ShopItem(
            originalId: originalId,
            headline: firstCategory['headline'] as String,
            invitation: firstCategory['invitation'] as String?,
            categoryIds: categoryIds,
            isSelected: isSelected,
            isExpanded: isSelected, // Auto-expand if selected
          ));
        }
      }

      setState(() {
        _shopItems = items;
        _isLoading = false;
      });

      // If we have an existing category, load tasks for the pre-selected item
      if (widget.existingCategory != null && items.isNotEmpty) {
        await _loadTasksForItem(0); // Load tasks for the first (and only) item
      }

      print('Loaded ${items.length} public categories for shop');
    } catch (e) {
      print('Error loading public categories: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleSelection(int index) async {
    final wasSelected = _shopItems[index].isSelected;

    setState(() {
      _shopItems[index].isSelected = !wasSelected;
    });

    // If category is being selected and not already expanded, expand it
    if (!wasSelected && !_shopItems[index].isExpanded) {
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

      // Fetch tasks for all categories with this original_id
      final response = await supabase
          .from('Tasks')
          .select('*')
          .inFilter('category_id', item.categoryIds);

      if (response != null) {
        final List<Task> tasks = (response as List)
            .map((json) => Task.fromJson(json as Map<String, dynamic>))
            .toList();

        setState(() {
          _shopItems[index].tasks = tasks;
          // Initialize import selections for new tasks
          for (final task in tasks) {
            _taskImportSelections[task.id.toString()] = false;
          }
        });

        print(
            'Loaded ${tasks.length} tasks for original_id: ${item.originalId}');
      }
    } catch (e) {
      print('Error loading tasks for item $index: $e');
      // Don't show error to user, just log it
    }
  }

  void _toggleTaskImportSelection(String taskId) {
    setState(() {
      _taskImportSelections[taskId] = !(_taskImportSelections[taskId] ?? false);
    });
  }

  Future<void> _addSelectedTasksToCategory() async {
    try {
      final userId = AuthUtils.getCurrentUserId();
      if (userId == null) {
        throw Exception('No user logged in');
      }

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

      for (final task in selectedTasks) {
        // Create new task with the existing category's ID
        final newTaskData = {
          'headline': task.headline,
          'notes': task.notes,
          'links': task.links,
          'triggers_at': task.triggersAt?.toIso8601String(),
          'suggestible_at': task.suggestibleAt?.toIso8601String(),
          'finished': false, // Start as unfinished
          'category_id': widget.existingCategory!.id,
          'owner_id': userId,
        };

        await supabase.from('Tasks').insert(newTaskData);
        importedTasks++;
      }

      setState(() {
        _isLoading = false;
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Successfully added $importedTasks tasks to ${widget.existingCategory!.headline}!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );

        // Navigate back
        Navigator.pop(context);
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
      if (userId == null) {
        throw Exception('No user logged in');
      }

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
        // Check if user already has a category with this original_id
        final existingCategoryResponse = await supabase
            .from('Categories')
            .select('id')
            .eq('owner_id', userId)
            .eq('original_id', item.originalId)
            .maybeSingle();

        String categoryId;

        if (existingCategoryResponse != null) {
          // Use existing category
          categoryId = existingCategoryResponse['id'].toString();
          print(
              'Using existing category $categoryId for original_id ${item.originalId}');
        } else {
          // Create new category
          final newCategoryData = {
            'headline': item.headline,
            'invitation': item.invitation,
            'owner_id': userId,
            'original_id': item.originalId,
            'private': false, // Default to public
          };

          final newCategoryResponse = await supabase
              .from('Categories')
              .insert(newCategoryData)
              .select()
              .single();

          categoryId = newCategoryResponse['id'].toString();
          importedCategories++;
          print(
              'Created new category $categoryId for original_id ${item.originalId}');
        }

        // Import selected tasks for this category
        final selectedTaskIds = item.tasks
            .where((task) => _taskImportSelections[task.id.toString()] == true)
            .map((task) => task.id.toString())
            .toList();

        if (selectedTaskIds.isNotEmpty) {
          // Fetch the original tasks
          final originalTasksResponse = await supabase
              .from('Tasks')
              .select('*')
              .inFilter('id', selectedTaskIds);

          if (originalTasksResponse != null) {
            for (final taskData in originalTasksResponse as List) {
              final originalTask =
                  Task.fromJson(taskData as Map<String, dynamic>);

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
              };

              await supabase.from('Tasks').insert(newTaskData);

              importedTasks++;
            }
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

        // Navigate back to home screen
        Navigator.pop(context);
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
                      color: Theme.of(context).textTheme.bodySmall?.color,
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
            : 'Shop Endeavors'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_shopItems.isNotEmpty)
            TextButton(
              onPressed: widget.existingCategory != null
                  ? _addSelectedTasksToCategory
                  : _importSelectedCategories,
              child: Text(widget.existingCategory != null
                  ? 'Add Tasks'
                  : 'Import Selected'),
            ),
        ],
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
              : _shopItems.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shopping_cart_outlined,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No public categories available',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Check back later for new endeavors!',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16.0),
                      itemCount: _shopItems.length,
                      itemBuilder: (context, index) {
                        final item = _shopItems[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8.0),
                          child: Column(
                            children: [
                              ListTile(
                                leading: widget.existingCategory == null
                                    ? Checkbox(
                                        value: item.isSelected,
                                        onChanged: (_) =>
                                            _toggleSelection(index),
                                      )
                                    : null,
                                title: GestureDetector(
                                  onTap: () => _toggleExpansion(index),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          widget.existingCategory != null
                                              ? "...${item.headline}"
                                              : item.headline,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                      if (widget.existingCategory == null)
                                        Icon(
                                          item.isExpanded
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                          color: Colors.grey,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              if (item.isExpanded) ...[
                                if (widget.existingCategory == null) ...[
                                  if (item.invitation != null)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          16.0, 0.0, 16.0, 8.0),
                                      child: Text(
                                        item.invitation!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: Colors.grey[600],
                                              fontStyle: FontStyle.italic,
                                            ),
                                      ),
                                    ),
                                ],
                                if (item.tasks.isNotEmpty) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16.0, 0.0, 16.0, 16.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (widget.existingCategory == null)
                                          Text(
                                            'Suggestions',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.grey[700],
                                                ),
                                          ),
                                        if (widget.existingCategory == null)
                                          const SizedBox(height: 8),
                                        ...item.tasks
                                            .map((task) => _buildTaskCard(task))
                                            .toList(),
                                      ],
                                    ),
                                  ),
                                ] else if (item.isExpanded)
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(
                                        16.0, 0.0, 16.0, 16.0),
                                    child: Text(
                                      'No suggestions',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
