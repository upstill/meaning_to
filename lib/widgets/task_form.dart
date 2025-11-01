import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/utils/app_buttons.dart';
import 'package:meaning_to/add_tasks_screen.dart';
import 'package:meaning_to/shop_endeavors_screen.dart';
import 'package:meaning_to/justwatch_import_screen.dart';
import 'package:meaning_to/letterboxd_import_screen.dart';

class TaskForm extends StatefulWidget {
  final List<Category> categories;
  final Category? selectedCategory;
  final Function(Category)? onCategorySelected;
  final bool isLoading;
  final Function(
      String headline, String notes, List<String> links, bool isShared) onSave;
  final String? initialHeadline;
  final String? initialNotes;
  final List<String>? initialLinks;
  final bool categoryLocked; // If true, show category as fixed display

  const TaskForm({
    super.key,
    required this.categories,
    required this.selectedCategory,
    this.onCategorySelected,
    required this.isLoading,
    required this.onSave,
    this.initialHeadline,
    this.initialNotes,
    this.initialLinks,
    this.categoryLocked = false,
  });

  @override
  State<TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<TaskForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _headlineController;
  late TextEditingController _notesController;
  List<String> _links = [];
  bool _isShared = false;

  @override
  void initState() {
    super.initState();

    _headlineController =
        TextEditingController(text: widget.initialHeadline ?? '');
    _notesController = TextEditingController(text: widget.initialNotes ?? '');

    if (widget.initialLinks != null) {
      _links = List<String>.from(widget.initialLinks!);
    }

    // Initialize shared state based on category's tasksArePrivate setting
    // If tasksArePrivate is true, tasks start private (shared = false)
    // If tasksArePrivate is false, tasks start shared (shared = true)
    if (widget.selectedCategory != null) {
      _isShared = !widget.selectedCategory!.tasksArePrivate;
    }

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
    _notesController.dispose();
    super.dispose();
  }

  void _addLink() {
    showDialog(
      context: context,
      builder: (context) {
        final linkController = TextEditingController();
        return AlertDialog(
          title: const Text('Add Link'),
          content: TextFormField(
            controller: linkController,
            decoration: const InputDecoration(
              labelText: 'URL',
              hintText: 'https://example.com',
            ),
            keyboardType: TextInputType.url,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final link = linkController.text.trim();
                if (link.isNotEmpty) {
                  setState(() {
                    _links.add(link);
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _removeLink(int index) {
    setState(() {
      _links.removeAt(index);
    });
  }

  void _handleSave() {
    if (!_formKey.currentState!.validate()) return;

    widget.onSave(
      _headlineController.text.trim(),
      _notesController.text.trim(),
      _links,
      _isShared,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Task details
          Card(
            elevation: 10,
            color: Colors.grey[50],
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Colors.blue.withOpacity(0.2),
                width: 2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _headlineController,
                    decoration: InputDecoration(
                      labelText:
                          '${NamingUtils.tasksName(plural: false)} (required)',
                      hintText: 'What have you been meaning to do?',
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 3,
                    minLines: 1,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a ${NamingUtils.tasksName(capitalize: false, plural: false)}';
                      }
                      return null;
                    },
                    enabled: !widget.isLoading,
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      hintText: 'Additional details, thoughts, or context...',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 4,
                    minLines: 2,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    enabled: !widget.isLoading,
                  ),

                  const SizedBox(height: 16),

                  // Privacy/Sharing checkbox
                  CheckboxListTile(
                    title: Text(
                        'Share this ${NamingUtils.tasksName(capitalize: false, plural: false)}'),
                    subtitle: const Text('Make it available to others'),
                    value: _isShared,
                    onChanged: widget.isLoading
                        ? null
                        : (value) {
                            setState(() {
                              _isShared = value ?? false;
                            });
                          },
                    tristate: false,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),

                  // Links section
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Links',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: widget.isLoading ? null : _addLink,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Link'),
                      ),
                    ],
                  ),

                  if (_links.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...List.generate(_links.length, (index) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            _links[index],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _removeLink(index),
                          ),
                        ),
                      );
                    }),
                  ],

                  const SizedBox(height: 24),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_headlineController.text.trim().isNotEmpty &&
                              widget.selectedCategory != null &&
                              !widget.isLoading)
                          ? _handleSave
                          : null,
                      icon: widget.isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(widget.isLoading
                          ? 'Creating...'
                          : 'Create ${NamingUtils.tasksName(capitalize: false, plural: false)}'),
                      style: AppButtons.finalize().copyWith(
                        minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Alternative options section
          const SizedBox(height: 24),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Labeled divider to set off alternatives
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      'Alternative options',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),

              // Add A List of Ideas button
              Center(
                child: FractionallySizedBox(
                  widthFactor: 0.5,
                  child: ElevatedButton.icon(
                    onPressed: widget.isLoading
                        ? null
                        : () async {
                            if (widget.selectedCategory != null) {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AddTasksScreen(
                                    category: widget.selectedCategory!,
                                  ),
                                ),
                              );

                              // If tasks were added, close this screen to return to Edit Category
                              if (result == true && context.mounted) {
                                Navigator.pop(context, true);
                              }
                            }
                          },
                    icon: const Icon(Icons.add_task),
                    label: Text(
                        'Add a List of ${NamingUtils.tasksName(plural: true)}'),
                    style: AppButtons.goForth(),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Prompt about getting ideas from other people
              Center(
                child: Text(
                  '** You can also get ${NamingUtils.tasksName(plural: true)} from other people! **',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 16),

              // Shop for Suggestions button
              FutureBuilder<bool>(
                future: widget.selectedCategory != null
                    ? ShopEndeavorsScreen.hasAnyPublicSuggestionsForCategory(
                        widget.selectedCategory!)
                    : Future.value(false),
                builder: (context, snapshot) {
                  final hasSuggestions = snapshot.data == true;
                  return Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.5,
                      child: ElevatedButton.icon(
                        onPressed: (widget.isLoading ||
                                !hasSuggestions ||
                                widget.selectedCategory == null)
                            ? null
                            : () async {
                                final result = await Navigator.pushNamed(
                                  context,
                                  '/shop-endeavors',
                                  arguments: {
                                    'category': widget.selectedCategory,
                                  },
                                );

                                // If suggestions were added, close this screen to return to Edit Category
                                if (result == true && context.mounted) {
                                  Navigator.pop(context, true);
                                }
                              },
                        icon: const Icon(Icons.shopping_cart),
                        label: Text(hasSuggestions
                            ? 'Shop for Suggestions'
                            : 'No Suggestions Out There'),
                        style: hasSuggestions
                            ? AppButtons.goForth()
                            : ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey[300],
                                foregroundColor: Colors.grey[600],
                              ),
                      ),
                    ),
                  );
                },
              ),

              // JustWatch import for movie/TV categories
              if (widget.selectedCategory != null &&
                  (widget.selectedCategory!.originalId == 2 ||
                      widget.selectedCategory!.headline
                          .toLowerCase()
                          .contains('movie') ||
                      widget.selectedCategory!.headline
                          .toLowerCase()
                          .contains('tv') ||
                      widget.selectedCategory!.headline
                          .toLowerCase()
                          .contains('watch'))) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        '** OR...You can import your list from JustWatch. **',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),
                Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.5,
                    child: ElevatedButton.icon(
                      onPressed: widget.isLoading
                          ? null
                          : () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => JustWatchImportScreen(
                                    category: widget.selectedCategory!,
                                  ),
                                ),
                              );

                              // If content was imported, close this screen to return to Edit Category
                              if (result != null && context.mounted) {
                                Navigator.pop(context, true);
                              }
                            },
                      icon: const Icon(Icons.movie),
                      label: const Text('Import from JustWatch'),
                      style: AppButtons.goForth(),
                    ),
                  ),
                ),
              ],

              // Letterboxd import for movie categories
              if (widget.selectedCategory != null &&
                  (widget.selectedCategory!.originalId == 1 ||
                      widget.selectedCategory!.headline
                          .toLowerCase()
                          .contains('movie') ||
                      widget.selectedCategory!.headline
                          .toLowerCase()
                          .contains('film'))) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        '** OR...Import from Letterboxd **',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),
                Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.5,
                    child: ElevatedButton.icon(
                      onPressed: widget.isLoading
                          ? null
                          : () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => LetterboxdImportScreen(
                                    category: widget.selectedCategory!,
                                  ),
                                ),
                              );

                              // If content was imported, close this screen to return to Edit Category
                              if (result != null && context.mounted) {
                                Navigator.pop(context, true);
                              }
                            },
                      icon: const Icon(Icons.movie_outlined),
                      label: const Text('Import from Letterboxd'),
                      style: AppButtons.goForth(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
