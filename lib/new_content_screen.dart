import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/widgets/task_form.dart';
import 'package:meaning_to/widgets/category_form.dart';
import 'package:meaning_to/dialogs/category_picker_dialog.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/utils/app_buttons.dart';
import 'package:meaning_to/edit_category_screen.dart';
import 'package:meaning_to/utils/link_to_task_converter.dart';
import 'package:html/parser.dart' as html_parser;

enum ContentType { task, category }

class NewContentScreen extends StatefulWidget {
  final Category? selectedCategory;
  final List<String>? initialLinks;
  final String? initialHeadline;
  final String? initialNotes;
  final String? originalId; // ID of the original task to link to
  final bool
      categoryLocked; // If true, only show New Task mode with fixed category

  const NewContentScreen({
    super.key,
    this.selectedCategory,
    this.initialLinks,
    this.initialHeadline,
    this.initialNotes,
    this.originalId,
    this.categoryLocked = false,
  });

  @override
  State<NewContentScreen> createState() => _NewContentScreenState();
}

class _NewContentScreenState extends State<NewContentScreen> {
  ContentType _contentType = ContentType.task;
  bool _isLoading = false;
  List<Category> _categories = [];
  Category? _selectedCategoryForTask;
  List<String> _currentLinks = []; // Track current links from the task form

  @override
  void initState() {
    super.initState();
    _selectedCategoryForTask = widget.selectedCategory;

    // Initialize links if provided
    if (widget.initialLinks != null) {
      _currentLinks = List<String>.from(widget.initialLinks!);
    }

    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final response = await supabase
          .from('Categories')
          .select()
          .eq('owner_id', AuthUtils.getCurrentUserId())
          .order('last_access', ascending: false);

      final categories =
          (response as List).map((json) => Category.fromJson(json)).toList();

      setState(() {
        _categories = categories;

        if (categories.isEmpty) {
          // No categories exist - show New Category variant
          _contentType = ContentType.category;
        } else {
          // Categories exist - show New Task variant
          _contentType = ContentType.task;
          // Set selected category to first one if none provided
          if (_selectedCategoryForTask == null) {
            _selectedCategoryForTask = categories.first;
          }
        }
      });
    } catch (e) {
      print('Error loading categories: $e');
    }
  }

  Future<void> _createTask(String headline, String notes, List<String> links,
      bool isShared, String? synopsis) async {
    if (_selectedCategoryForTask == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a category for the task'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final userId = AuthUtils.getCurrentUserId();
      final now = DateTime.now().toUtc();

      print(
          'NewContentScreen: Creating task with synopsis: ${synopsis != null ? "${synopsis.length} chars" : "null"}');

      final taskData = {
        'category_id': _selectedCategoryForTask!.id,
        'headline': headline,
        'notes': notes.isEmpty ? null : notes,
        'synopsis': synopsis, // Include synopsis from OMDb/link processing
        'owner_id': userId,
        'created_at': now.toIso8601String(),
        'suggestible_at': null,
        'triggers_at': null,
        'deferral': null,
        'links': links,
        'finished': false,
        'shared': isShared,
        'original_id': widget.originalId,
      };

      final response =
          await supabase.from('Tasks').insert(taskData).select().single();

      // Wait for database transaction to commit
      await Future.delayed(const Duration(milliseconds: 500));

      // Update the task cache using CacheManager
      final cacheManager = CacheManager();

      // Only update cache if it's on the same category
      if (cacheManager.currentCategory?.id == _selectedCategoryForTask!.id) {
        final createdTaskObj = Task.fromJson(response);
        await cacheManager.updateTask(createdTaskObj);
      }

      if (mounted) {
        // Create task object from response
        final createdTask = {
          'task': response,
          'category': _selectedCategoryForTask!.toJson(),
          'count': 1,
        };

        Navigator.pop(context, createdTask);
      }
    } catch (e) {
      print('Error creating task: $e');
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Error creating ${NamingUtils.tasksName(capitalize: false, plural: false)}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
        'original_id': null,
        'private': isPrivate,
        'tasks_are_private': tasksArePrivate,
      };

      final response =
          await supabase.from('Categories').insert(data).select().single();

      final newCategory = Category.fromJson(response);

      // Initialize cache with the new category
      final cacheManager = CacheManager();
      await cacheManager.initializeWithSavedCategory(newCategory, userId);

      if (mounted) {
        // Navigate to Edit Category screen with the new category
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
            content: Text(
                'Error creating ${NamingUtils.categoriesName(capitalize: false, plural: false)}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showCategoryPicker() {
    // Analyze current links to get suggested category IDs
    final suggestedIds = <int>{};

    print('NewContentScreen: _showCategoryPicker - analyzing ${_currentLinks.length} links');

    for (int i = 0; i < _currentLinks.length; i++) {
      final htmlLink = _currentLinks[i];
      print('NewContentScreen: Processing link $i: $htmlLink');

      try {
        // Extract URL from HTML link
        final document = html_parser.parse(htmlLink);
        final anchor = document.querySelector('a');
        final url = anchor?.attributes['href'];

        if (url != null) {
          print('NewContentScreen: Extracted URL: $url');

          // Get category suggestions for this URL
          final suggestions = LinkToTaskConverter.analyzeLinkForCategorySuggestions(url);
          print('NewContentScreen: Suggestions for this URL: $suggestions');

          suggestedIds.addAll(suggestions);
        } else {
          print('NewContentScreen: No URL found in HTML link');
        }
      } catch (e) {
        print('NewContentScreen: Error extracting URL from link: $e');
      }
    }

    print('NewContentScreen: Final suggested category IDs: ${suggestedIds.toList()}');

    CategoryPickerDialog.show(
      context,
      title:
          'Choose ${NamingUtils.categoriesName(capitalize: true, plural: false)}',
      defaultCategory: _selectedCategoryForTask,
      onCategorySelected: (category, {shouldMove, applyToAll}) {
        setState(() {
          _selectedCategoryForTask = category;
        });
      },
      showCreateNew: true,
      suggestedCategoryIds: suggestedIds.toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_contentType == ContentType.task
            ? (_selectedCategoryForTask != null
                ? 'New Idea to ${_selectedCategoryForTask!.headline}'
                : 'New Idea')
            : 'Define new ${NamingUtils.categoriesName(capitalize: true, plural: false)}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Action buttons row (only show if not category locked)
          if (!widget.categoryLocked) ...[
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Category change button (left side, only show for task mode and if user has multiple categories)
                  if (_contentType == ContentType.task && _categories.length > 1)
                    TextButton(
                      onPressed: () => _showCategoryPicker(),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.blue[800],
                        backgroundColor: Colors.blue[50],
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Add to different ${NamingUtils.categoriesName(plural: false, capitalize: true)}',
                      ),
                    )
                  else
                    const SizedBox.shrink(),

                  // "New Pursuit Instead" button (right side)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _contentType = _contentType == ContentType.task
                            ? ContentType.category
                            : ContentType.task;
                      });
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.green[800],
                      backgroundColor: Colors.green[50],
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      _contentType == ContentType.task
                          ? 'Make a New ${NamingUtils.categoriesName(capitalize: true, plural: false)} instead'
                          : 'Make a New ${NamingUtils.tasksName(capitalize: true, plural: false)} instead',
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Main content area
          Expanded(
            child: _contentType == ContentType.task || widget.categoryLocked
                ? TaskForm(
                    categories: _categories,
                    selectedCategory: _selectedCategoryForTask,
                    onCategorySelected: widget.categoryLocked
                        ? null // Disable category selection when locked
                        : (category) {
                            setState(() {
                              _selectedCategoryForTask = category;
                            });
                          },
                    isLoading: _isLoading,
                    onSave: _createTask,
                    initialHeadline: widget.initialHeadline,
                    initialNotes: widget.initialNotes,
                    initialLinks: widget.initialLinks,
                    categoryLocked: widget.categoryLocked,
                    onLinksChanged: (links) {
                      setState(() {
                        _currentLinks = links;
                      });
                      print('NewContentScreen: Links updated, count: ${links.length}');
                    },
                  )
                : ListView(
                    padding: const EdgeInsets.all(16.0),
                    children: [
                      CategoryForm(
                        category: null,
                        isEditing: true,
                        isLoading: _isLoading,
                        onSave: _createCategory,
                      ),
                      const SizedBox(height: 32),
                      Center(
                        child: Text(
                          '** You can adopt other people\'s ${NamingUtils.categoriesName(capitalize: true, plural: true)}. **',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: FractionallySizedBox(
                          widthFactor: 0.5,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading
                                ? null
                                : () async {
                                    try {
                                      final result = await Navigator.pushNamed(
                                          context, '/shop-endeavors');

                                      if (result != null && mounted) {
                                        // Check if result is 'home' (go to home screen) or true (multiple tasks/categories)
                                        if (result == 'home') {
                                          // User chose to go to home screen - pop this screen and all the way to home
                                          Navigator.of(context).popUntil(
                                              (route) => route.isFirst);
                                        } else if (result == true) {
                                          // Multiple tasks or category imported - close this screen
                                          Navigator.pop(context, true);
                                        }
                                        // If result is null, stay on this screen (user chose to add more)
                                      }
                                    } catch (e) {
                                      print(
                                          'NewContentScreen: Navigation error: $e');
                                    }
                                  },
                            icon: const Icon(Icons.shopping_cart),
                            label: Text(
                              'Shop for ${NamingUtils.categoriesName(capitalize: true)}',
                              style: const TextStyle(fontSize: 18),
                            ),
                            style: AppButtons.goForth().copyWith(
                              minimumSize: const WidgetStatePropertyAll(
                                  Size(double.infinity, 50)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
