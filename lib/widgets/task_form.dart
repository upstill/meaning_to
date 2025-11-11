import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/utils/app_buttons.dart';
import 'package:meaning_to/add_tasks_screen.dart';
import 'package:meaning_to/shop_endeavors_screen.dart';
import 'package:meaning_to/justwatch_import_screen.dart';
import 'package:meaning_to/letterboxd_import_screen.dart';
import 'package:meaning_to/utils/link_to_task_converter.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/widgets/link_display.dart';
import 'package:meaning_to/link_edit_screen.dart';
import 'package:meaning_to/utils/auth.dart';

class TaskForm extends StatefulWidget {
  final List<Category> categories;
  final Category? selectedCategory;
  final Function(Category)? onCategorySelected;
  final bool isLoading;
  final Function(String headline, String notes, List<String> links,
      bool isShared, String? synopsis) onSave;
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
  bool _isProcessingUrl = false;
  String? _lastProcessedUrl;
  bool _isProgrammaticUpdate = false;
  String? _synopsis; // Store synopsis from link processing (e.g., OMDb API)

  @override
  void initState() {
    super.initState();

    print('TaskForm: ============ initState CALLED ============');
    print('TaskForm: selectedCategory: ${widget.selectedCategory?.headline}');
    print(
        'TaskForm: Category original_id: ${widget.selectedCategory?.originalId}');

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

    // Add listener to track headline changes and detect pasted URLs
    print('TaskForm: Adding listener to _headlineController');
    _headlineController.addListener(_onHeadlineChanged);
    print('TaskForm: Listener added successfully');
    print('TaskForm: ============ initState COMPLETE ============');
  }

  @override
  void dispose() {
    _headlineController.removeListener(_onHeadlineChanged);
    _headlineController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Handle headline changes to detect and process pasted URLs
  void _onHeadlineChanged() {
    print('TaskForm: _onHeadlineChanged called');
    print('TaskForm: _isProgrammaticUpdate = $_isProgrammaticUpdate');
    print('TaskForm: headline text = "${_headlineController.text}"');

    // Skip if we're programmatically updating the field
    if (_isProgrammaticUpdate) {
      print('TaskForm: Skipping - programmatic update');
      return;
    }

    // Trigger rebuild for button state
    setState(() {});

    // Check if headline contains a URL
    final headlineText = _headlineController.text.trim();
    print('TaskForm: Checking for URL in: "$headlineText"');

    final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(headlineText);
    print('TaskForm: URL match found: ${urlMatch != null}');

    if (urlMatch != null && !_isProcessingUrl) {
      final url = urlMatch.group(0)!;
      print('TaskForm: Matched URL: $url');

      // Remove trailing punctuation
      final cleanUrl = url.replaceAll(RegExp(r'[.,;:!?]+$'), '');
      print('TaskForm: Clean URL: $cleanUrl');
      print('TaskForm: Last processed URL: $_lastProcessedUrl');

      // Only process if this is a new URL we haven't processed yet
      if (_lastProcessedUrl != cleanUrl) {
        print('TaskForm: New URL detected, processing...');
        _lastProcessedUrl = cleanUrl;
        _processUrlInHeadline(cleanUrl);
      } else {
        print('TaskForm: URL already processed, skipping');
      }
    } else if (urlMatch == null) {
      print('TaskForm: No URL found in headline');
    } else if (_isProcessingUrl) {
      print('TaskForm: Already processing a URL, skipping');
    }
  }

  /// Process a URL found in the headline field
  Future<void> _processUrlInHeadline(String url) async {
    if (_isProcessingUrl) {
      print('TaskForm: Already processing, returning');
      return;
    }

    print('TaskForm: === STARTING URL PROCESSING ===');
    print('TaskForm: URL: $url');

    setState(() {
      _isProcessingUrl = true;
    });

    try {
      print('TaskForm: Fetching task data using LinkToTaskConverter...');

      // Use the centralized task converter to properly extract task data
      // This handles IMDb (with OMDb API), streaming media, and other links
      final userId = AuthUtils.getCurrentUserId();
      final proposedTask = await LinkToTaskConverter.createProposedTaskFromLink(
        url,
        userId,
        currentCategory: widget.selectedCategory,
      );

      print('TaskForm: Fetch complete');
      print('TaskForm: Headline: ${proposedTask.headline}');
      print('TaskForm: Notes: ${proposedTask.notes}');
      print(
          'TaskForm: Synopsis: ${proposedTask.synopsis != null ? "${proposedTask.synopsis!.length} chars" : "null"}');

      if (proposedTask.headline.isEmpty) {
        print('TaskForm: ERROR - Could not extract headline from URL');
        return;
      }

      // Update the fields (mark as programmatic to avoid triggering listener)
      _isProgrammaticUpdate = true;

      setState(() {
        _headlineController.text = proposedTask.headline;

        // Set notes if available (for streaming media, this is the work/album title)
        if (proposedTask.notes != null && proposedTask.notes!.isNotEmpty) {
          _notesController.text = proposedTask.notes!;
        }

        // Store synopsis (invisible field for OMDb data, etc.)
        _synopsis = proposedTask.synopsis;
        if (_synopsis != null) {
          print(
              'TaskForm: Stored synopsis for saving: ${_synopsis!.length} characters');
        }

        // Add the HTML link from proposedTask (it's already formatted)
        if (proposedTask.links.isNotEmpty) {
          _links.add(proposedTask.links.first);
        }
      });

      _isProgrammaticUpdate = false;

      print('TaskForm: Successfully updated fields from proposed task');
      print('TaskForm: === URL PROCESSING COMPLETE ===');
    } catch (e, stackTrace) {
      print('TaskForm: === ERROR PROCESSING URL ===');
      print('TaskForm: Error: $e');
      print('TaskForm: Stack trace: $stackTrace');
    } finally {
      print('TaskForm: Cleaning up - resetting flags');
      _isProgrammaticUpdate = false; // Ensure flag is reset
      setState(() {
        _isProcessingUrl = false;
      });
      print('TaskForm: === END URL PROCESSING ===');
    }
  }

  Future<void> _addLink() async {
    final result = await Navigator.push<ProposedTask?>(
      context,
      MaterialPageRoute(
        builder: (context) => LinkEditScreen(
          currentTask: null, // No current task when creating new
          currentCategory: widget.selectedCategory,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        // Add the link
        if (result.links.isNotEmpty) {
          _links.add(result.links.first);
        }

        // If headline is empty, use the link's title
        if (_headlineController.text.trim().isEmpty) {
          _headlineController.text = result.headline;
        }

        // If synopsis is available and current synopsis is empty, use it
        if (result.synopsis != null &&
            result.synopsis!.isNotEmpty &&
            (_synopsis == null || _synopsis!.isEmpty)) {
          _synopsis = result.synopsis;
        }
      });
    }
  }

  void _removeLink(int index) {
    setState(() {
      _links.removeAt(index);
    });
  }

  void _handleSave() {
    if (!_formKey.currentState!.validate()) return;

    print(
        'TaskForm: Saving task with synopsis: ${_synopsis != null ? "${_synopsis!.length} chars" : "null"}');

    widget.onSave(
      _headlineController.text.trim(),
      _notesController.text.trim(),
      _links,
      _isShared,
      _synopsis, // Pass synopsis to be saved to database
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
                      suffixIcon: _isProcessingUrl
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
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
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: FutureBuilder<ProcessedLink>(
                                  future: LinkProcessor.processLinkForDisplay(
                                      _links[index]),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Row(
                                        children: [
                                          SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          ),
                                          SizedBox(width: 8),
                                          Text('Processing link...'),
                                        ],
                                      );
                                    }

                                    if (snapshot.hasError ||
                                        !snapshot.hasData) {
                                      // Fallback to raw text display
                                      return Text(
                                        _links[index],
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      );
                                    }

                                    // Use LinkDisplay.buildLinkWidget for proper display
                                    return LinkDisplay.buildLinkWidget(
                                        snapshot.data!, context);
                                  },
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () => _removeLink(index),
                              ),
                            ],
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
