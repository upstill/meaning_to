import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/utils/link_to_task_converter.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/link_edit_screen.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/supabase_client.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/add_tasks_screen.dart';
import 'package:meaning_to/shop_endeavors_screen.dart';
import 'package:meaning_to/utils/app_buttons.dart';
import 'package:meaning_to/justwatch_import_screen.dart';
import 'package:meaning_to/letterboxd_import_screen.dart';
import 'package:meaning_to/models/icon.dart';
import 'package:meaning_to/dialogs/category_picker_dialog.dart';
import 'package:meaning_to/utils/streaming_media_constants.dart';
import 'package:meaning_to/utils/incoming_link_processor.dart';
import 'package:meaning_to/utils/synopsis_fetcher.dart';

// Widget to display favicon for a domain
class DomainFaviconWidget extends StatelessWidget {
  final String domain;
  final double size;
  final Widget fallbackIcon;

  const DomainFaviconWidget({
    super.key,
    required this.domain,
    this.size = 24,
    required this.fallbackIcon,
  });

  /// Map certain domains to their canonical domains for icon fetching
  String _getCanonicalDomain(String domain) {
    // Handle Letterboxd short URLs
    if (domain == 'boxd.it') {
      return 'letterboxd.com';
    }

    // Add other domain mappings here as needed
    return domain;
  }

  @override
  Widget build(BuildContext context) {
    final canonicalDomain = _getCanonicalDomain(domain);

    return FutureBuilder<DomainIcon?>(
      future: DomainIcon.getIconForDomain(canonicalDomain),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data?.iconUrl != null) {
          return Image.network(
            snapshot.data!.iconUrl,
            width: size,
            height: size,
            errorBuilder: (context, error, stackTrace) => fallbackIcon,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return SizedBox(
                width: size,
                height: size,
                child: Center(
                  child: SizedBox(
                    width: size * 0.6,
                    height: size * 0.6,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
          );
        }
        return fallbackIcon;
      },
    );
  }
}

class TaskEditScreen extends StatefulWidget {
  static VoidCallback? onEditComplete; // Static callback for edit completion

  final Category category;
  final Task? task; // null for new task, existing task for edit
  final List<String>? initialLinks; // Links to pre-populate for new tasks
  final String? initialHeadline; // Headline to pre-populate for new tasks
  final String? initialNotes; // Notes to pre-populate for new tasks
  final bool showAlternativeOptions; // Whether to show bulk import options
  final String? infoMessage; // Optional informational message to display at top
  final bool isPanel; // true when displayed as modal bottom sheet
  final void Function(Category)? onCategoryChange; // called when panel wants category change

  const TaskEditScreen({
    super.key,
    required this.category,
    this.task,
    this.initialLinks,
    this.initialHeadline,
    this.initialNotes,
    this.showAlternativeOptions = true,
    this.infoMessage,
    this.isPanel = false,
    this.onCategoryChange,
  });

  @override
  State<TaskEditScreen> createState() => _TaskEditScreenState();
}

class _TaskEditScreenState extends State<TaskEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _headlineController;
  late TextEditingController _notesController;
  bool _isLoading = false;
  String? _error;
  List<String> _links = [];
  bool _isProcessingUrl = false;
  String? _lastProcessedUrl;
  bool _isProgrammaticUpdate = false;
  bool _isShared = false;

  // Local copy of the task for editing
  Task? _localTask;

  @override
  void initState() {
    super.initState();

    print('TaskEditScreen: ============ initState CALLED ============');
    print('TaskEditScreen: Category: ${widget.category.headline}');
    print(
        'TaskEditScreen: Category original_id: ${widget.category.originalId}');
    print('TaskEditScreen: Is new task: ${widget.task == null}');
    print('TaskEditScreen: widget.initialHeadline: ${widget.initialHeadline}');
    print('TaskEditScreen: widget.initialNotes: ${widget.initialNotes}');
    print('TaskEditScreen: widget.initialLinks: ${widget.initialLinks}');

    // Get the current task state from cache if available, otherwise use the passed task
    if (widget.task != null) {
      final cacheManager = CacheManager();
      final currentTasks = cacheManager.currentTasks;

      if (currentTasks != null) {
        // Try to find the task in the cache
        final cachedTask = currentTasks.firstWhere(
          (task) => task.id == widget.task!.id,
          orElse: () => widget.task!,
        );

        // Use the cached task if found, otherwise use the passed task
        _localTask = cachedTask;
      } else {
        // No cache available, use the passed task
        _localTask = widget.task!;
      }
    }

    // Initialize controllers with task data or initial values
    // If initialHeadline/initialNotes are provided, they take precedence (e.g., when adding to existing task)
    _headlineController = TextEditingController(
        text: widget.initialHeadline ?? _localTask?.headline ?? '');
    _notesController = TextEditingController(
        text: widget.initialNotes ?? _localTask?.notes ?? '');

    // Initialize links - if initialLinks are provided, use those (e.g., when adding new link to existing task)
    // Otherwise use the task's existing links
    if (widget.initialLinks != null) {
      _links = List<String>.from(widget.initialLinks!);
      print('TaskEditScreen: Using initialLinks: ${_links.length} links');
      for (int i = 0; i < _links.length; i++) {
        print('TaskEditScreen:   Link $i: ${_links[i]}');
      }
    } else if (_localTask?.links != null) {
      _links = List<String>.from(_localTask!.links!);
      print('TaskEditScreen: Using task links: ${_links.length} links');
      for (int i = 0; i < _links.length; i++) {
        print('TaskEditScreen:   Link $i: ${_links[i]}');
      }
    } else {
      _links = [];
      print('TaskEditScreen: No links to initialize');
    }

    print(
        'TaskEditScreen: Final _headlineController.text: "${_headlineController.text}"');
    print(
        'TaskEditScreen: Final _notesController.text: "${_notesController.text}"');
    print('TaskEditScreen: Final _links.length: ${_links.length}');

    // For existing tasks, use their current shared state
    // For new tasks, use the category's tasksArePrivate setting
    if (_localTask != null) {
      _isShared = _localTask!.shared;
    } else {
      // New task: use category's tasksArePrivate setting
      // If tasksArePrivate is true, tasks start private (shared = false)
      // If tasksArePrivate is false, tasks start shared (shared = true)
      _isShared = !widget.category.tasksArePrivate;
    }

    // Add listener to track headline changes and detect pasted URLs
    print('TaskEditScreen: Adding listener to _headlineController');
    _headlineController.addListener(_onHeadlineChanged);
    print('TaskEditScreen: Listener added successfully');
    print('TaskEditScreen: ============ initState COMPLETE ============');
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
    print('TaskEditScreen: _onHeadlineChanged called');
    print('TaskEditScreen: _isProgrammaticUpdate = $_isProgrammaticUpdate');
    print('TaskEditScreen: headline text = "${_headlineController.text}"');

    // Skip if we're programmatically updating the field
    if (_isProgrammaticUpdate) {
      print('TaskEditScreen: Skipping - programmatic update');
      return;
    }

    // Trigger rebuild for button state
    setState(() {});

    // Check if headline contains a URL
    final headlineText = _headlineController.text.trim();
    print('TaskEditScreen: Checking for URL in: "$headlineText"');

    final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(headlineText);
    print('TaskEditScreen: URL match found: ${urlMatch != null}');

    if (urlMatch != null && !_isProcessingUrl) {
      final url = urlMatch.group(0)!;
      print('TaskEditScreen: Matched URL: $url');

      // Remove trailing punctuation
      final cleanUrl = url.replaceAll(RegExp(r'[.,;:!?]+$'), '');
      print('TaskEditScreen: Clean URL: $cleanUrl');
      print('TaskEditScreen: Last processed URL: $_lastProcessedUrl');

      // Only process if this is a new URL we haven't processed yet
      if (_lastProcessedUrl != cleanUrl) {
        print('TaskEditScreen: New URL detected, processing...');
        _lastProcessedUrl = cleanUrl;
        _processUrlInHeadline(cleanUrl, headlineText);
      } else {
        print('TaskEditScreen: URL already processed, skipping');
      }
    } else if (urlMatch == null) {
      print('TaskEditScreen: No URL found in headline');
    } else if (_isProcessingUrl) {
      print('TaskEditScreen: Already processing a URL, skipping');
    }
  }

  /// Process a URL found in the headline field
  Future<void> _processUrlInHeadline(
      String url, String originalHeadline) async {
    if (_isProcessingUrl) {
      print('TaskEditScreen: Already processing, returning');
      return;
    }

    print('TaskEditScreen: === STARTING URL PROCESSING ===');
    print('TaskEditScreen: URL: $url');

    setState(() {
      _isProcessingUrl = true;
      _error = 'Processing link...'; // Show visual feedback
    });

    try {
      print('TaskEditScreen: Fetching webpage metadata...');

      // Fetch the webpage metadata
      final processedLink = await LinkProcessor.validateAndProcessLink(url);
      print('TaskEditScreen: Fetch complete');
      print('TaskEditScreen: Title: ${processedLink.title}');
      print(
          'TaskEditScreen: Description: ${processedLink.description?.substring(0, 50)}...');

      final fetchedTitle = processedLink.title;

      if (fetchedTitle == null) {
        print('TaskEditScreen: ERROR - Could not fetch title for URL');
        setState(() {
          _error = 'Could not fetch title from link';
        });
        return;
      }

      print('TaskEditScreen: Fetched title: "$fetchedTitle"');

      // Check if this is a streaming media link in a streaming media category
      final isStreamingCategory = widget.category.originalId != null &&
          STREAMING_MEDIA_CATEGORY_IDS.contains(widget.category.originalId);

      print(
          'TaskEditScreen: Category original_id: ${widget.category.originalId}');
      print('TaskEditScreen: Is streaming category: $isStreamingCategory');
      print('TaskEditScreen: Is streaming URL: ${isStreamingMediaUrl(url)}');

      if (isStreamingMediaUrl(url) && isStreamingCategory) {
        print('TaskEditScreen: === PROCESSING AS STREAMING MEDIA ===');

        // Try to extract artist and work from the title
        print(
            'TaskEditScreen: Attempting to extract artist/work from: "$fetchedTitle"');
        final artistWorkInfo = extractArtistAndWorkFromTidal(fetchedTitle);
        print('TaskEditScreen: Extraction result: $artistWorkInfo');

        if (artistWorkInfo != null) {
          print(
              'TaskEditScreen: Successfully extracted - artist: "${artistWorkInfo.artist}", work: "${artistWorkInfo.work}"');

          // Create HTML link
          final htmlLink = '<a href="$url">$fetchedTitle</a>';
          print('TaskEditScreen: Created HTML link: $htmlLink');

          // Update the fields (mark as programmatic to avoid triggering listener)
          print('TaskEditScreen: Setting _isProgrammaticUpdate = true');
          _isProgrammaticUpdate = true;

          setState(() {
            print(
                'TaskEditScreen: Updating headline to: "${artistWorkInfo.artist}"');
            print(
                'TaskEditScreen: Updating notes to: "${artistWorkInfo.work}"');
            print('TaskEditScreen: Adding link to links array');
            _headlineController.text = artistWorkInfo.artist;
            _notesController.text = artistWorkInfo.work;
            _links.add(htmlLink);
            _error = null; // Clear error message
          });

          print('TaskEditScreen: Setting _isProgrammaticUpdate = false');
          _isProgrammaticUpdate = false;

          print(
              'TaskEditScreen: Successfully updated headline and notes with artist/work');

          // Check for existing artist tasks (only for new tasks, not editing)
          if (_localTask == null && mounted) {
            final userId = AuthUtils.getCurrentUserId();
            final existingTask = await IncomingLinkProcessor
                .findTaskByArtistInStreamingCategories(
              artistWorkInfo.artist,
              userId,
            );

            if (existingTask != null && mounted) {
              // Show dialog asking if user wants to switch to existing task
              final shouldSwitch = await _showExistingArtistDialog(
                existingTask,
                artistWorkInfo.work,
              );

              if (shouldSwitch == true && mounted) {
                // Navigate back and then to the existing task
                Navigator.of(context).pop(); // Close current screen

                // Navigate to existing task edit screen
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => TaskEditScreen(
                      category: widget.category,
                      task: existingTask,
                      initialNotes: existingTask.notes != null
                          ? '${existingTask.notes}\n${artistWorkInfo.work}'
                          : artistWorkInfo.work,
                      initialLinks: [
                        ...existingTask.links ?? [],
                        htmlLink,
                      ],
                    ),
                  ),
                );
              }
            }
          }
        }
      } else {
        print('TaskEditScreen: === PROCESSING AS REGULAR LINK ===');
        // For non-streaming URLs, just set the title and add the link
        final htmlLink = '<a href="$url">$fetchedTitle</a>';

        _isProgrammaticUpdate = true;
        setState(() {
          _headlineController.text = fetchedTitle;
          _links.add(htmlLink);
          _error = null; // Clear error message
        });
        _isProgrammaticUpdate = false;

        print('TaskEditScreen: Updated headline with fetched title');
      }

      print('TaskEditScreen: === URL PROCESSING COMPLETE ===');
    } catch (e, stackTrace) {
      print('TaskEditScreen: === ERROR PROCESSING URL ===');
      print('TaskEditScreen: Error: $e');
      print('TaskEditScreen: Stack trace: $stackTrace');
      setState(() {
        _error = 'Error processing link: $e';
      });
    } finally {
      print('TaskEditScreen: Cleaning up - resetting flags');
      _isProgrammaticUpdate = false; // Ensure flag is reset
      setState(() {
        _isProcessingUrl = false;
      });
      print('TaskEditScreen: === END URL PROCESSING ===');
    }
  }

  /// Get suggested category IDs from current links
  List<int> _getSuggestedCategoryIds() {
    final suggestedIds = <int>{};

    for (final htmlLink in _links) {
      try {
        // Extract URL from HTML link
        final urlMatch = RegExp(r'href="([^"]+)"').firstMatch(htmlLink);
        if (urlMatch != null) {
          final url = urlMatch.group(1)!;
          // Get suggested categories for this URL
          final suggestions =
              LinkToTaskConverter.analyzeLinkForCategorySuggestions(url);
          suggestedIds.addAll(suggestions);
        }
      } catch (e) {
        print('TaskEditScreen: Error extracting URL from link: $e');
      }
    }

    return suggestedIds.toList();
  }

  /// Show category selection dialog
  void _showCategorySelectionDialog() async {
    // Get suggested categories from current links
    final suggestedCategoryIds = _getSuggestedCategoryIds();
    print('TaskEditScreen: Suggested category IDs: $suggestedCategoryIds');

    // Extract first link URL for domain-based relevance scoring
    String? linkUrl;
    if (_links.isNotEmpty) {
      try {
        final urlMatch = RegExp(r'href="([^"]+)"').firstMatch(_links.first);
        if (urlMatch != null) {
          linkUrl = urlMatch.group(1);
          print('TaskEditScreen: Using link for domain relevance: $linkUrl');
        }
      } catch (e) {
        print('TaskEditScreen: Error extracting URL from link: $e');
      }
    }

    await CategoryPickerDialog.show(
      context,
      title:
          'Select ${NamingUtils.categoriesName(capitalize: false, plural: false)}',
      defaultCategory: widget.category,
      suggestedCategoryIds:
          suggestedCategoryIds.isNotEmpty ? suggestedCategoryIds : null,
      linkUrl: linkUrl,
      onCategorySelected: (Category selectedCategory,
          {bool? shouldMove, bool? applyToAll}) async {
        if (selectedCategory.id != widget.category.id) {
          if (_localTask == null) {
            // For new tasks, just change the category
            await _changeCategoryForNewTask(selectedCategory);
          } else {
            // For existing tasks, show move/copy dialog
            await _showMoveOrCopyDialog(selectedCategory);
          }
        }
      },
    );
  }

  /// Change category for a new task
  Future<void> _changeCategoryForNewTask(Category newCategory) async {
    // Navigate back to TaskEditScreen with the new category
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => TaskEditScreen(
          category: newCategory,
          initialLinks: _links.isNotEmpty ? _links : null,
          initialHeadline: _headlineController.text.isNotEmpty
              ? _headlineController.text
              : null,
          initialNotes:
              _notesController.text.isNotEmpty ? _notesController.text : null,
          showAlternativeOptions: widget.showAlternativeOptions,
        ),
      ),
    );
  }

  /// Show dialog to choose between moving or copying the task
  Future<void> _showMoveOrCopyDialog(Category newCategory) async {
    bool shouldMove = true; // Default to move

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
              'Change ${NamingUtils.categoriesName(capitalize: false, plural: false)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Move this ${NamingUtils.tasksName(capitalize: false, plural: false)} to "${newCategory.headline}"?'),
              const SizedBox(height: 16),
              RadioListTile<bool>(
                title: Text(
                    'Move ${NamingUtils.tasksName(capitalize: false, plural: false)}'),
                subtitle: Text('Remove from "${widget.category.headline}"'),
                value: true,
                groupValue: shouldMove,
                onChanged: (value) {
                  setState(() {
                    shouldMove = value ?? true;
                  });
                },
              ),
              RadioListTile<bool>(
                title: Text(
                    'Copy ${NamingUtils.tasksName(capitalize: false, plural: false)}'),
                subtitle: Text(
                    'Keep in both "${widget.category.headline}" and "${newCategory.headline}"'),
                value: false,
                groupValue: shouldMove,
                onChanged: (value) {
                  setState(() {
                    shouldMove = value ?? false;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(shouldMove),
              child: const Text('Okay'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      final shouldMove = result;

      if (shouldMove) {
        if (widget.isPanel) {
          // In panel mode, do a direct DB update and close the panel
          await supabase
              .from('Tasks')
              .update({'category_id': newCategory.id})
              .eq('id', _localTask!.id);
          if (mounted) Navigator.pop(context);
          TaskEditScreen.onEditComplete?.call();
        } else {
          // MOVE: Navigate to TaskEditScreen with new category, preserving task data
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => TaskEditScreen(
                category: newCategory,
                task: _localTask, // Pass the existing task
                initialLinks: _links.isNotEmpty ? _links : null,
                initialHeadline: _headlineController.text.isNotEmpty
                    ? _headlineController.text
                    : null,
                initialNotes: _notesController.text.isNotEmpty
                    ? _notesController.text
                    : null,
                showAlternativeOptions: widget.showAlternativeOptions,
              ),
            ),
          );
        }
      } else {
        // COPY: Create a new task in the new category while keeping the old one
        try {
          final userId = AuthUtils.getCurrentUserId();
          final data = {
            'headline': _headlineController.text,
            'notes':
                _notesController.text.isEmpty ? null : _notesController.text,
            'category_id': newCategory.id,
            'owner_id': userId,
            'finished': false,
            'shared': _localTask?.shared ?? !newCategory.tasksArePrivate,
            'links': _links,
          };

          await supabase.from('Tasks').insert(data).select().single();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${NamingUtils.tasksName(capitalize: true, plural: false)} copied to "${newCategory.headline}"'),
            ),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error copying task: $e')),
          );
        }
      }
    }
  }

  Future<void> _addLink() async {
    final result = await Navigator.push<ProposedTask?>(
      context,
      MaterialPageRoute(
        builder: (context) => LinkEditScreen(
          currentTask: _currentTaskState,
          currentCategory: widget.category,
        ),
      ),
    );

    if (result != null && result.links.isNotEmpty) {
      final htmlLink = result.links.first;
      final errorMessage = await _addLinkToTask(htmlLink);
      if (errorMessage != null) {
        setState(() {
          _error = errorMessage;
        });
      }
    }
  }

  Future<void> _editLink(int index) async {
    final result = await Navigator.push<ProposedTask?>(
      context,
      MaterialPageRoute(
        builder: (context) => LinkEditScreen(
          initialLink: _links[index],
          currentTask: _currentTaskState,
          currentCategory: widget.category,
        ),
      ),
    );

    if (result != null && result.links.isNotEmpty) {
      final htmlLink = result.links.first;
      final errorMessage = await _updateLinkInTask(htmlLink, index);
      if (errorMessage != null) {
        setState(() {
          _error = errorMessage;
        });
      }
    }
  }

  void _removeLink(int index) {
    setState(() {
      _links.removeAt(index);
    });
  }

  /// Get the current task state with all unsaved changes
  Task? get _currentTaskState {
    if (_localTask == null) return null;

    return Task(
      id: _localTask!.id,
      categoryId: _localTask!.categoryId,
      ownerId: _localTask!.ownerId,
      headline: _headlineController.text,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
      links: _links, // Always store as array, even if empty
      processedLinks: _localTask!.processedLinks,
      createdAt: _localTask!.createdAt,
      suggestibleAt: _localTask!.suggestibleAt,
      finished: _localTask!.finished,
      shared: _isShared,
    );
  }

  /// Adds a link to the current task (duplicate checking handled by LinkEditScreen).
  /// Returns an error message if the link cannot be added, null if successful.
  Future<String?> _addLinkToTask(String htmlLink) async {
    print('TaskEditScreen: _addLinkToTask called with: $htmlLink');

    // Add the link to the current task's links list
    // Note: Duplicate checking is now handled by LinkEditScreen
    setState(() {
      _links.add(htmlLink);
      _error = null;
    });

    print('TaskEditScreen: Link added successfully: $htmlLink');

    // Check if this is a streaming media link and handle accordingly
    await _handleStreamingMediaLink(htmlLink);

    return null; // No error
  }

  /// Handle streaming media links (e.g., Tidal) by parsing artist/work and populating fields
  Future<void> _handleStreamingMediaLink(String htmlLink) async {
    try {
      // Extract URL from HTML link
      final url = _extractUrlFromHtmlLink(htmlLink);
      if (url == null) return;

      // Check if this is a streaming media URL
      if (!isStreamingMediaUrl(url)) return;

      // Check if current category is a streaming media category
      final isStreamingCategory = widget.category.originalId != null &&
          STREAMING_MEDIA_CATEGORY_IDS.contains(widget.category.originalId);

      if (!isStreamingCategory) {
        print(
            'TaskEditScreen: Not a streaming media category, skipping artist extraction');
        return;
      }

      // Extract the link title from HTML
      final titleMatch = RegExp(r'<a[^>]*>(.+?)</a>').firstMatch(htmlLink);
      final linkTitle = titleMatch?.group(1);

      if (linkTitle == null) return;

      // Try to extract artist and work from the title
      final artistWorkInfo = extractArtistAndWorkFromTidal(linkTitle);

      if (artistWorkInfo == null) {
        print(
            'TaskEditScreen: Could not extract artist/work from title: $linkTitle');
        return;
      }

      print(
          'TaskEditScreen: Extracted artist: "${artistWorkInfo.artist}", work: "${artistWorkInfo.work}"');

      // Check if headline is empty before auto-populating
      if (_headlineController.text.trim().isEmpty) {
        setState(() {
          _headlineController.text = artistWorkInfo.artist;
        });
        print(
            'TaskEditScreen: Set headline to artist: ${artistWorkInfo.artist}');
      }

      // Check if notes are empty before auto-populating
      if (_notesController.text.trim().isEmpty) {
        setState(() {
          _notesController.text = artistWorkInfo.work;
        });
        print('TaskEditScreen: Set notes to work: ${artistWorkInfo.work}');
      } else {
        // If notes already have content, append the work on a new line
        setState(() {
          _notesController.text =
              '${_notesController.text}\n${artistWorkInfo.work}';
        });
        print('TaskEditScreen: Appended work to notes: ${artistWorkInfo.work}');
      }

      // Check for existing artist tasks (only if creating a new task, not editing)
      if (_localTask == null && mounted) {
        final userId = AuthUtils.getCurrentUserId();
        final existingTask =
            await IncomingLinkProcessor.findTaskByArtistInStreamingCategories(
          artistWorkInfo.artist,
          userId,
        );

        if (existingTask != null && mounted) {
          // Show dialog asking if user wants to switch to existing task
          final shouldSwitch = await _showExistingArtistDialog(
            existingTask,
            artistWorkInfo.work,
          );

          if (shouldSwitch == true && mounted) {
            // Navigate back and then to the existing task
            Navigator.of(context).pop(); // Close current screen

            // Navigate to existing task edit screen
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => TaskEditScreen(
                  category: widget.category,
                  task: existingTask,
                  initialNotes: existingTask.notes != null
                      ? '${existingTask.notes}\n${artistWorkInfo.work}'
                      : artistWorkInfo.work,
                  initialLinks: [
                    ...existingTask.links ?? [],
                    htmlLink,
                  ],
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      print('TaskEditScreen: Error handling streaming media link: $e');
      // Don't throw - just log and continue
    }
  }

  /// Show dialog when an existing artist task is found
  Future<bool?> _showExistingArtistDialog(
      Task existingTask, String workTitle) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Found Existing Artist',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You already have a ${NamingUtils.tasksName(capitalize: false, plural: false)} for this artist:',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existingTask.headline,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'in ${widget.category.headline}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (existingTask.notes != null &&
                      existingTask.notes!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      existingTask.notes!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Would you like to add "$workTitle" to that ${NamingUtils.tasksName(capitalize: false, plural: false)} instead?',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep This One'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
            ),
            child: const Text('Switch to Existing'),
          ),
        ],
      ),
    );
  }

  /// Helper method to extract URL from HTML link string
  String? _extractUrlFromHtmlLink(String htmlLink) {
    if (htmlLink.startsWith('<a href="') && htmlLink.contains('">')) {
      final startIndex = htmlLink.indexOf('href="') + 6;
      final endIndex = htmlLink.indexOf('">', startIndex);
      if (endIndex > startIndex) {
        return htmlLink.substring(startIndex, endIndex);
      }
    }
    // If it's not an HTML link, return as is (might be a plain URL)
    if (htmlLink.startsWith('http')) {
      return htmlLink;
    }
    return null;
  }

  /// Updates a link in the current task (duplicate checking handled by LinkEditScreen).
  /// Returns an error message if the link cannot be updated, null if successful.
  Future<String?> _updateLinkInTask(String htmlLink, int index) async {
    print(
        'TaskEditScreen: _updateLinkInTask called with: $htmlLink at index $index');

    // Update the link in the current task's links list
    // Note: Duplicate checking is now handled by LinkEditScreen
    setState(() {
      _links[index] = htmlLink;
      _error = null;
    });

    print('TaskEditScreen: Link updated successfully: $htmlLink');
    return null; // No error
  }

  Future<void> _pasteLinkFromClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData?.text == null) {
        setState(() {
          _error = 'No text found in clipboard';
        });
        return;
      }

      final text = clipboardData!.text!.trim();
      setState(() {
        _isLoading = true;
        _error = null;
      });

      try {
        // Parse the text as HTML link
        final (url, linkText) = LinkProcessor.parseHtmlLink(text);

        String htmlLink;
        // If it's not an HTML link, treat it as a plain URL
        if (url == text) {
          if (LinkProcessor.isValidUrl(text)) {
            // Validate the URL
            final processedLink = await LinkProcessor.validateAndProcessLink(
              text,
            );

            // Create an HTML link with the fetched title
            htmlLink = '<a href="$text">${processedLink.title ?? text}</a>';
          } else {
            // Open link edit screen with the text pre-filled
            final result = await Navigator.push<ProposedTask?>(
              context,
              MaterialPageRoute(
                builder: (context) => LinkEditScreen(
                  initialLink: text,
                  errorMessage:
                      'Clipboard text is not a valid URL or HTML link',
                  currentTask: _currentTaskState,
                  currentCategory: widget.category,
                ),
              ),
            );
            if (result != null && result.links.isNotEmpty) {
              htmlLink = result.links.first;
            } else {
              setState(() {
                _isLoading = false;
              });
              return;
            }
          }
        } else {
          // It was an HTML link, validate the extracted URL
          final processedLink = await LinkProcessor.validateAndProcessLink(
            url,
            linkText: linkText,
          );

          // Create a new HTML link with the validated data
          htmlLink =
              '<a href="$url">${linkText ?? processedLink.title ?? url}</a>';
        }

        // Add the link (duplicate checking handled by LinkEditScreen)
        await _addLinkToTask(htmlLink);
      } catch (e) {
        print('Error processing pasted link: $e');
        // Open link edit screen with error message
        final result = await Navigator.push<ProposedTask?>(
          context,
          MaterialPageRoute(
            builder: (context) => LinkEditScreen(
              initialLink: text,
              errorMessage: e.toString(),
              currentTask: _currentTaskState,
              currentCategory: widget.category,
            ),
          ),
        );
        if (result != null && result.links.isNotEmpty) {
          final htmlLink = result.links.first;
          // Add the link (duplicate checking handled by LinkEditScreen)
          await _addLinkToTask(htmlLink);
        }
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error pasting link: $e');
      setState(() {
        _error = 'Failed to paste link: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  /// Check if a task with the same headline or same link already exists and merge information if needed
  Future<Task?> _checkForDuplicateAndMerge(
      Map<String, dynamic> newTaskData, String userId) async {
    print('TaskEditScreen: === DUPLICATE DETECTION START ===');
    print(
        'TaskEditScreen: Checking for duplicates of: "${newTaskData['headline']}"');
    print('TaskEditScreen: New task links: ${newTaskData['links']}');

    // First, check if the current task (if editing) already has the same link
    if (_localTask != null &&
        newTaskData['links'] != null &&
        (newTaskData['links'] as List).isNotEmpty) {
      print('TaskEditScreen: Checking current task for duplicate links...');
      print('TaskEditScreen: Current task links: ${_localTask!.links}');

      if (_localTask!.links != null && _localTask!.links!.isNotEmpty) {
        for (final newLink in newTaskData['links'] as List) {
          print('TaskEditScreen: Checking new link: $newLink');
          for (final existingLink in _localTask!.links!) {
            print('TaskEditScreen: Against current task link: $existingLink');
            // Extract URLs from HTML links for comparison
            final newUrl = _extractUrlFromHtmlLink(newLink);
            final existingUrl = _extractUrlFromHtmlLink(existingLink);
            print('TaskEditScreen: Extracted new URL: $newUrl');
            print('TaskEditScreen: Extracted existing URL: $existingUrl');

            if (newUrl != null &&
                existingUrl != null &&
                newUrl == existingUrl) {
              print('TaskEditScreen: Found duplicate link in current task!');
              print('TaskEditScreen: New link: $newUrl');
              print('TaskEditScreen: Existing link: $existingUrl');
              print(
                  'TaskEditScreen: === DUPLICATE DETECTION END - DUPLICATE IN CURRENT TASK ===');
              return _localTask; // Return current task since it already has this link
            }
          }
        }
      }
      print('TaskEditScreen: No duplicate links found in current task');
    }

    // Get existing tasks for the current category (excluding the current task being edited)
    final response = await supabase
        .from('Tasks')
        .select()
        .eq('category_id', widget.category.id)
        .eq('owner_id', userId)
        .order('created_at', ascending: false);

    final existingTasks = (response as List)
        .map((json) => Task.fromJson(json as Map<String, dynamic>))
        .where((task) =>
            _localTask == null ||
            task.id != _localTask!.id) // Exclude current task if editing
        .toList();
    print(
        'TaskEditScreen: Existing tasks count: ${existingTasks.length} (excluding current task)');

    // First, check for tasks with the same headline
    Task? existingTask;
    for (final task in existingTasks) {
      if (task.headline.toLowerCase().trim() ==
          (newTaskData['headline'] as String).toLowerCase().trim()) {
        existingTask = task;
        print(
            'TaskEditScreen: Found existing task with matching headline: "${task.headline}" (ID: ${task.id})');
        break;
      }
    }

    // If no headline match found, check for tasks with the same link
    if (existingTask == null &&
        newTaskData['links'] != null &&
        (newTaskData['links'] as List).isNotEmpty) {
      print(
          'TaskEditScreen: No headline match found, checking for link matches...');

      // Extract URL from the first new link and search for it in the database
      final firstNewLink = (newTaskData['links'] as List).first as String;
      final searchUrl = _extractUrlFromHtmlLink(firstNewLink);

      if (searchUrl != null) {
        // Escape special characters for LIKE pattern
        final escapedUrl =
            searchUrl.replaceAll('%', '\\%').replaceAll('_', '\\_');

        print('TaskEditScreen: Searching for tasks with URL: $searchUrl');

/*         
        Query database using unnest to find tasks where links array contains the URL.
        This uses a PostgreSQL function. Create it with:
        CREATE OR REPLACE FUNCTION find_tasks_by_link_url(search_url_pattern TEXT)
        RETURNS TABLE(id INTEGER, category_id INTEGER, headline TEXT, notes TEXT,
                      synopsis TEXT, owner_id TEXT, created_at TIMESTAMPTZ,
                      suggestible_at TIMESTAMPTZ, triggers_at TIMESTAMPTZ, deferral INTEGER,
                      links TEXT[], processed_links JSONB, finished BOOLEAN,
                      shared BOOLEAN, original_id INTEGER, dirty BOOLEAN) AS $$
        BEGIN
          RETURN QUERY
          SELECT t.* FROM "Tasks" t
          WHERE EXISTS (
            SELECT 1 FROM unnest(t.links) AS link
            WHERE link LIKE search_url_pattern
          )
          ORDER BY t.created_at DESC;
        END;
        $$ LANGUAGE plpgsql; 
        */
        try {
          final linkResponse = await supabase.rpc(
            'find_tasks_by_link_url',
            params: {'search_url_pattern': '%$escapedUrl%'},
          );

          final tasksWithLink = (linkResponse as List)
              .map((json) => Task.fromJson(json as Map<String, dynamic>))
              .where((task) =>
                  _localTask == null ||
                  task.id != _localTask!.id) // Exclude current task if editing
              .toList();

          print(
              'TaskEditScreen: Found ${tasksWithLink.length} task(s) with matching link');

          // Find the first task with an exact URL match
          for (final task in tasksWithLink) {
            if (task.links != null && task.links!.isNotEmpty) {
              for (final existingLink in task.links!) {
                final existingUrl = _extractUrlFromHtmlLink(existingLink);
                if (existingUrl != null && existingUrl == searchUrl) {
                  print(
                      'TaskEditScreen: Found existing task with matching link: "${task.headline}" (ID: ${task.id})');
                  print('TaskEditScreen:   New link: $searchUrl');
                  print('TaskEditScreen:   Existing link: $existingUrl');
                  existingTask = task;
                  break;
                }
              }
              if (existingTask != null) break;
            }
          }
        } catch (e) {
          print(
              'TaskEditScreen: Error querying tasks by link (RPC may not exist): $e');
          print(
              'TaskEditScreen: Using direct query with array_to_string fallback...');

          // Fallback: use array_to_string to search (less efficient but works without RPC)
          try {
            final linkResponse = await supabase
                .from('Tasks')
                .select()
                .filter('links', 'not.is', null)
                .order('created_at', ascending: false);

            final allTasks = (linkResponse as List)
                .map((json) => Task.fromJson(json as Map<String, dynamic>))
                .where((task) =>
                    _localTask == null ||
                    task.id !=
                        _localTask!.id) // Exclude current task if editing
                .toList();

            // Filter in memory using the escaped URL
            final tasksWithLink = allTasks.where((task) {
              if (task.links == null || task.links!.isEmpty) return false;
              return task.links!.any((link) => link.contains(escapedUrl));
            }).toList();

            print(
                'TaskEditScreen: Found ${tasksWithLink.length} task(s) with matching link');

            // Find the first task with an exact URL match
            for (final task in tasksWithLink) {
              for (final existingLink in task.links!) {
                final existingUrl = _extractUrlFromHtmlLink(existingLink);
                if (existingUrl != null && existingUrl == searchUrl) {
                  print(
                      'TaskEditScreen: Found existing task with matching link: "${task.headline}" (ID: ${task.id})');
                  print('TaskEditScreen:   New link: $searchUrl');
                  print('TaskEditScreen:   Existing link: $existingUrl');
                  existingTask = task;
                  break;
                }
              }
              if (existingTask != null) break;
            }
          } catch (e2) {
            print('TaskEditScreen: Error with fallback query: $e2');
            // Final fallback to in-memory search on existingTasks
            print('TaskEditScreen: Falling back to in-memory search...');
            for (final task in existingTasks) {
              if (task.links != null && task.links!.isNotEmpty) {
                for (final existingLink in task.links!) {
                  final existingUrl = _extractUrlFromHtmlLink(existingLink);
                  if (existingUrl != null && existingUrl == searchUrl) {
                    existingTask = task;
                    break;
                  }
                }
                if (existingTask != null) break;
              }
            }
          }
        }
      }
    }

    if (existingTask != null) {
      print(
          'TaskEditScreen: Found existing task: "${existingTask.headline}" (ID: ${existingTask.id})');
      // Found a duplicate - merge information and update
      print('TaskEditScreen: Found duplicate task: "${existingTask.headline}"');
      print(
          'TaskEditScreen: === DUPLICATE DETECTION END - DUPLICATE FOUND ===');
      // Found a duplicate - merge information and update
      print('TaskEditScreen: Found duplicate task: "${existingTask.headline}"');
      print(
          'TaskEditScreen: === DUPLICATE DETECTION END - DUPLICATE FOUND ===');

      // Check if we need to update the existing task with new information
      bool needsUpdate = false;
      Map<String, dynamic> updateData = {};

      // Add links if the new task has them and the existing task doesn't
      if (newTaskData['links'] != null &&
          (newTaskData['links'] as List).isNotEmpty &&
          (existingTask.links == null || existingTask.links!.isEmpty)) {
        updateData['links'] = newTaskData['links'];
        needsUpdate = true;
        print('TaskEditScreen:   -> Adding links to existing task');
      }

      // Add notes if the new task has them and the existing task doesn't
      if (newTaskData['notes'] != null &&
          (newTaskData['notes'] as String).isNotEmpty &&
          (existingTask.notes == null || existingTask.notes!.isEmpty)) {
        updateData['notes'] = newTaskData['notes'];
        needsUpdate = true;
        print('TaskEditScreen:   -> Adding notes to existing task');
      }

      // Always update the existing task to move it to the top of the list
      // Set suggestibleAt to null to make it appear first
      try {
        // Add suggestibleAt: null to the update data to move task to top
        updateData['suggestible_at'] = null;

        await supabase
            .from('Tasks')
            .update(updateData)
            .eq('id', existingTask.id)
            .eq('owner_id', userId);

        print(
            'TaskEditScreen:   -> Updated existing task and moved to top of list');

        // Create the updated task object
        final updatedTask = Task(
          id: existingTask.id,
          categoryId: existingTask.categoryId,
          ownerId: existingTask.ownerId,
          headline: existingTask.headline,
          notes: updateData['notes'] ?? existingTask.notes,
          links: updateData['links'] ?? existingTask.links,
          processedLinks: existingTask.processedLinks,
          createdAt: existingTask.createdAt,
          suggestibleAt: null, // Set to null to move to top
          finished: existingTask.finished,
        );

        // Update the cache to reflect the changes
        final cacheManager = CacheManager();
        await cacheManager.updateTask(updatedTask);
        print('TaskEditScreen:   -> Updated cache with moved task');

        return updatedTask;
      } catch (e) {
        print('TaskEditScreen: Error updating existing task: $e');
        return existingTask; // Return existing task without changes on error
      }
    } else {
      print(
          'TaskEditScreen: === DUPLICATE DETECTION END - NO DUPLICATE FOUND ===');
    }

    return null; // No duplicate found
  }

  /// Fetch Letterboxd notes/description for a URL (similar to the import screen logic)
  Future<String?> _fetchLetterboxdNotes(String url) async {
    // Skip description fetching for web platform due to CORS restrictions
    if (kIsWeb) {
      print(
          'TaskEditScreen: Skipping Letterboxd notes fetch on web platform (CORS restriction)');
      return null; // Leave as null to allow dynamic fetching
    }

    try {
      print('TaskEditScreen: Fetching Letterboxd notes from: $url');

      // Handle boxd.it redirects
      String finalUrl = url;
      if (url.contains('boxd.it')) {
        print(
            'TaskEditScreen: Detected boxd.it short URL, following redirect...');
        try {
          final redirectResponse = await http.head(Uri.parse(url));
          if (redirectResponse.headers.containsKey('location')) {
            finalUrl = redirectResponse.headers['location']!;
            print('TaskEditScreen: Redirect found, new URL: $finalUrl');
          } else {
            final testResponse = await http.get(Uri.parse(url));
            if (testResponse.request?.url != null) {
              finalUrl = testResponse.request!.url.toString();
              print('TaskEditScreen: Auto-redirected to: $finalUrl');
            }
          }
        } catch (e) {
          print(
              'TaskEditScreen: Error following redirect: $e, continuing with original URL');
        }
      }

      final response = await http.get(
        Uri.parse(finalUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.5',
          'Accept-Encoding': 'gzip, deflate, br',
          'DNT': '1',
          'Connection': 'keep-alive',
          'Upgrade-Insecure-Requests': '1',
        },
      );

      if (response.statusCode != 200) {
        print(
            'TaskEditScreen: HTTP status code ${response.statusCode} for URL: $url');
        return null; // Leave as null to allow dynamic fetching
      }

      final document = html_parser.parse(response.body);

      // Try different meta description tags in order of preference
      String? description;

      // First: Standard meta description
      description = document
          .querySelector('meta[name="description"]')
          ?.attributes['content']
          ?.trim();
      if (description != null && description.isNotEmpty) {
        print(
            'TaskEditScreen: Found description from meta[name="description"]: "$description"');
        return _formatLetterboxdNotes(description, url);
      }

      // Second: Open Graph description
      description = document
          .querySelector('meta[property="og:description"]')
          ?.attributes['content']
          ?.trim();
      if (description == null || description.isEmpty) {
        description = document
            .querySelector('meta[name="og:description"]')
            ?.attributes['content']
            ?.trim();
      }
      if (description != null && description.isNotEmpty) {
        print(
            'TaskEditScreen: Found description from og:description: "$description"');
        return _formatLetterboxdNotes(description, url);
      }

      // Third: Twitter Card description
      description = document
          .querySelector('meta[name="twitter:description"]')
          ?.attributes['content']
          ?.trim();
      if (description != null && description.isNotEmpty) {
        print(
            'TaskEditScreen: Found description from twitter:description: "$description"');
        return _formatLetterboxdNotes(description, url);
      }

      print('TaskEditScreen: No description found for Letterboxd URL: $url');
      return null; // Leave as null to allow dynamic fetching
    } catch (e) {
      print('TaskEditScreen: Error fetching Letterboxd notes for $url: $e');
      return null; // Leave as null to allow dynamic fetching
    }
  }

  /// Format Letterboxd notes similar to JustWatch imports
  String _formatLetterboxdNotes(String description, String url) {
    // Truncate to first 100 characters
    String truncatedDescription = description.length > 100
        ? '${description.substring(0, 100)}...'
        : description;

    // Create formatted notes with description + Letterboxd link
    return '$truncatedDescription <a href="$url">(more)</a>';
  }

  /// Process headline text to extract links and set appropriate headline
  Future<Map<String, dynamic>> _processHeadlineText(String headlineText,
      {bool skipColonSplit = false}) async {
    print('TaskEditScreen: Processing headline text: "$headlineText"');

    if (headlineText.trim().isEmpty) {
      return {
        'headline': '',
        'notes': null,
        'links': <String>[],
      };
    }

    // Check if text contains a URL
    final urlMatch = RegExp(r'https?://[^\s:]+').firstMatch(headlineText);
    if (urlMatch != null) {
      final extractedURL = urlMatch.group(0)!;
      print('TaskEditScreen: Found URL in headline: $extractedURL');

      // Remove trailing colon if present
      String cleanURL = extractedURL;
      if (cleanURL.endsWith(':')) {
        cleanURL = cleanURL.substring(0, cleanURL.length - 1);
      }

      // Extract text before and after the URL
      final urlStart = urlMatch.start;
      final urlEnd = urlMatch.end;
      final beforeURL = headlineText.substring(0, urlStart);
      final afterURL = headlineText.substring(urlEnd);

      // Combine text before and after URL, removing any trailing colons
      String cleanHeadline = (beforeURL + afterURL).trim();
      if (cleanHeadline.endsWith(':')) {
        cleanHeadline =
            cleanHeadline.substring(0, cleanHeadline.length - 1).trim();
      }

      // Remove @ prefix if it's the only text before the URL
      if (cleanHeadline == '@') {
        cleanHeadline = '';
      }

      // Fetch the webpage title/description to get link metadata
      String? fetchedNotes;
      String? fetchedTitle;

      try {
        print('TaskEditScreen: Fetching webpage metadata...');
        final processedLink =
            await LinkProcessor.validateAndProcessLink(cleanURL);
        fetchedTitle = processedLink.title;
        print('TaskEditScreen: Fetched webpage title: "$fetchedTitle"');

        // Check if this is a streaming media link in a streaming media category
        final isStreamingCategory = widget.category.originalId != null &&
            STREAMING_MEDIA_CATEGORY_IDS.contains(widget.category.originalId);

        if (isStreamingMediaUrl(cleanURL) &&
            isStreamingCategory &&
            fetchedTitle != null) {
          print(
              'TaskEditScreen: Detected streaming media link in streaming category');

          // Try to extract artist and work from the title
          final artistWorkInfo = extractArtistAndWorkFromTidal(fetchedTitle);

          if (artistWorkInfo != null) {
            print(
                'TaskEditScreen: Extracted artist: "${artistWorkInfo.artist}", work: "${artistWorkInfo.work}"');

            // Set headline to artist name (overriding any text before/after URL)
            cleanHeadline = artistWorkInfo.artist;

            // Set notes to work title
            fetchedNotes = artistWorkInfo.work;

            print('TaskEditScreen: Set headline to artist and notes to work');
          }
        }
        // For non-streaming links with no headline text, use the fetched title
        else if (cleanHeadline.isEmpty && fetchedTitle != null) {
          cleanHeadline = fetchedTitle;
        }

        // Use the description from processedLink if available (and not already set by streaming media)
        if (fetchedNotes == null &&
            processedLink.description != null &&
            processedLink.description!.isNotEmpty) {
          fetchedNotes = processedLink.description;
          print(
              'TaskEditScreen: Using description from LinkProcessor: "${fetchedNotes!.length > 100 ? '${fetchedNotes.substring(0, 100)}...' : fetchedNotes}"');
        }
        // For Letterboxd URLs without description, try the special Letterboxd fetch
        if (fetchedNotes == null &&
            (cleanURL.contains('letterboxd.com') ||
                cleanURL.contains('boxd.it'))) {
          fetchedNotes = await _fetchLetterboxdNotes(cleanURL);
          if (fetchedNotes != null) {
            print('TaskEditScreen: Fetched Letterboxd notes: "$fetchedNotes"');
          }
        }
      } catch (e) {
        print('TaskEditScreen: Failed to fetch webpage metadata: $e');
      }

      // If still no headline text after processing, use a default
      if (cleanHeadline.isEmpty) {
        cleanHeadline = fetchedTitle ?? 'Link';
      }

      print('TaskEditScreen: Processed headline: "$cleanHeadline"');
      print('TaskEditScreen: Extracted link: "$cleanURL"');

      return {
        'headline': cleanHeadline,
        'notes': fetchedNotes,
        'links': [cleanURL],
      };
    }

    // Check if text contains a colon separator (title: description)
    // Skip this when editing an existing task — user may have colons in their text
    // (e.g. movie titles like "Mission: Impossible").
    final colonIndex = skipColonSplit ? -1 : headlineText.indexOf(':');
    if (colonIndex > 0) {
      final title = headlineText.substring(0, colonIndex).trim();
      final description = headlineText.substring(colonIndex + 1).trim();

      if (title.isNotEmpty) {
        print(
            'TaskEditScreen: Found colon separator - title: "$title", description: "$description"');
        return {
          'headline': title,
          'notes': description.isNotEmpty ? description : null,
          'links': <String>[],
        };
      }
    }

    // Check if text is a markdown link [title](url)
    final markdownMatch =
        RegExp(r'\[([^\]]+)\]\(([^)]+)\)').firstMatch(headlineText);
    if (markdownMatch != null) {
      final title = markdownMatch.group(1) ?? 'Link';
      final url = markdownMatch.group(2) ?? '';

      if (url.isNotEmpty) {
        print(
            'TaskEditScreen: Found markdown link - title: "$title", url: "$url"');
        return {
          'headline': title,
          'notes': null,
          'links': [url],
        };
      }
    }

    // Check if text is an HTML link
    if (headlineText.trim().startsWith('<a') &&
        headlineText.trim().endsWith('</a>')) {
      print('TaskEditScreen: Attempting HTML link parsing');
      final (url, title) = LinkProcessor.parseHtmlLink(headlineText);
      if (url != headlineText) {
        print(
            'TaskEditScreen: Parsed HTML link - title: "$title", url: "$url"');
        return {
          'headline': title ?? 'Link',
          'notes': null,
          'links': [url],
        };
      }
    }

    // Treat as plain text
    print('TaskEditScreen: Treating as plain text: "$headlineText"');
    return {
      'headline': headlineText.trim(),
      'notes': null,
      'links': <String>[],
    };
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = AuthUtils.getCurrentUserId();

      // Process the headline text to extract links and set appropriate headline.
      // Skip colon-splitting for existing tasks so user edits like "Mission: Impossible"
      // aren't silently truncated.
      final processedData = await _processHeadlineText(
        _headlineController.text,
        skipColonSplit: _localTask != null,
      );
      final processedHeadline = processedData['headline'] as String;
      final processedNotes = processedData['notes'] as String?;
      final newLinks = processedData['links'] as List<String>;

      // Combine existing links with newly processed links
      final allLinks = [..._links, ...newLinks];

      // Use processed notes if available, otherwise fall back to notes controller
      final finalNotes = processedNotes ??
          (_notesController.text.isEmpty ? null : _notesController.text);

      final data = {
        'headline': processedHeadline,
        'notes': finalNotes,
        'category_id': widget.category.id,
        'owner_id': userId,
        'finished': _localTask?.finished ?? false,
        'shared': _isShared,
        'links':
            allLinks, // PostgreSQL array - always store as array, even if empty
      };

      // For new tasks, explicitly set suggestible_at to null to ensure they appear at the top
      if (_localTask == null) {
        data['suggestible_at'] = null;
        print(
            'TaskEditScreen: Explicitly setting suggestible_at to null for new task to ensure it appears at top of list');

        // Check if any link in this task already exists in another task (for original_id linking)
        if (allLinks.isNotEmpty) {
          print(
              'TaskEditScreen: Checking for original_id from existing tasks with same links...');
          try {
            final firstLinkUrl = _extractUrlFromHtmlLink(allLinks.first);
            if (firstLinkUrl != null) {
              print(
                  'TaskEditScreen: Searching for original_id for URL: $firstLinkUrl');

              // Use LinkToTaskConverter to find original_id (more efficient than loading all tasks)
              final originalId = await LinkToTaskConverter.findExistingTaskOriginalId(
                firstLinkUrl,
                userId,
              );

              if (originalId != null) {
                data['original_id'] = originalId;
                print('TaskEditScreen: Found original_id: $originalId');

                // Try to get synopsis from existing task if we don't have one
                if (data['synopsis'] == null || (data['synopsis'] as String).isEmpty) {
                  final synopsis = await SynopsisFetcher.fetchSynopsisForUrl(firstLinkUrl);
                  if (synopsis != null && synopsis.isNotEmpty) {
                    data['synopsis'] = synopsis;
                    print(
                        'TaskEditScreen: Fetched synopsis from existing task: "${synopsis.substring(0, synopsis.length > 100 ? 100 : synopsis.length)}..."');
                  }
                }
              } else {
                print(
                    'TaskEditScreen: No existing task found with this link, this will be the original');
              }
            }
          } catch (e) {
            print('TaskEditScreen: Error finding original_id: $e');
          }
        }
      }

      Task? updatedTask;
      if (_localTask == null) {
        // Check for duplicates before creating new task
        print(
            'TaskEditScreen: Checking for duplicates before creating new task...');
        final existingTask = await _checkForDuplicateAndMerge(data, userId);

        if (existingTask != null) {
          // Found a duplicate - use the existing task
          print(
              'TaskEditScreen: Found duplicate task, using existing: ${existingTask.headline}');
          updatedTask = existingTask;
        } else {
          // No duplicate found - create new task
          print('TaskEditScreen: No duplicate found, creating new task...');
          final response =
              await supabase.from('Tasks').insert(data).select().single();

          updatedTask = Task.fromJson(response);
          print('TaskEditScreen: Created new task: ${updatedTask.headline}');
        }
      } else {
        // Update existing task
        print('TaskEditScreen: Updating existing task...');
        final response = await supabase
            .from('Tasks')
            .update(data)
            .eq('id', _localTask!.id)
            .eq('owner_id', userId)
            .select()
            .single();

        updatedTask = Task.fromJson(response);
        print('TaskEditScreen: Updated task: ${updatedTask.headline}');
      }

      // Wait longer for database transaction to commit
      await Future.delayed(const Duration(milliseconds: 500));

      // Debug: Check task state before synopsis fetch
      print('TaskEditScreen: Checking synopsis fetch conditions:');
      print(
          '  - Task has links: ${updatedTask.links != null && updatedTask.links!.isNotEmpty}');
      print('  - Links count: ${updatedTask.links?.length ?? 0}');
      print('  - Synopsis is null: ${updatedTask.synopsis == null}');
      print('  - Synopsis is empty: ${updatedTask.synopsis?.isEmpty ?? true}');
      print(
          '  - Synopsis value: ${updatedTask.synopsis != null ? "\"${updatedTask.synopsis!.substring(0, updatedTask.synopsis!.length > 50 ? 50 : updatedTask.synopsis!.length)}...\"" : "null"}');

      // Fetch synopsis from web if task has links and no synopsis
      if (updatedTask.links != null &&
          updatedTask.links!.isNotEmpty &&
          (updatedTask.synopsis == null || updatedTask.synopsis!.isEmpty)) {
        print(
            'TaskEditScreen: Task has links but no synopsis, fetching synopsis...');
        try {
          final synopsisResult =
              await SynopsisFetcher.fetchSynopsisForTask(updatedTask);
          if (synopsisResult != null && synopsisResult.synopsis.isNotEmpty) {
            print(
                'TaskEditScreen: Fetched synopsis from ${synopsisResult.source.name}');
            print(
                'TaskEditScreen: Synopsis already saved to database by SynopsisFetcher');
            // Update local task object with the synopsis
            // SynopsisFetcher already saved it to the database
            updatedTask = Task(
              id: updatedTask.id,
              categoryId: updatedTask.categoryId,
              ownerId: updatedTask.ownerId,
              headline: updatedTask.headline,
              notes: updatedTask.notes,
              synopsis: synopsisResult.synopsis,
              createdAt: updatedTask.createdAt,
              suggestibleAt: updatedTask.suggestibleAt,
              triggersAt: updatedTask.triggersAt,
              deferral: updatedTask.deferral,
              links: updatedTask.links,
              finished: updatedTask.finished,
              shared: updatedTask.shared,
              originalId: updatedTask.originalId,
            );
            print('TaskEditScreen: Updated local task with synopsis');
          } else {
            print('TaskEditScreen: No synopsis found');
          }
        } catch (e) {
          print('TaskEditScreen: Error fetching synopsis: $e');
          // Continue even if synopsis fetch fails
        }
      } else {
        print('TaskEditScreen: Skipping synopsis fetch - conditions not met');
        if (updatedTask.links == null || updatedTask.links!.isEmpty) {
          print('  - Reason: Task has no links');
        } else if (updatedTask.synopsis != null &&
            updatedTask.synopsis!.isNotEmpty) {
          print(
              '  - Reason: Task already has synopsis: "${updatedTask.synopsis!.substring(0, updatedTask.synopsis!.length > 100 ? 100 : updatedTask.synopsis!.length)}..."');
        }
      }

      // Update the task cache using CacheManager only when saving
      print('TaskEditScreen: Updating task cache...');
      final cacheManager = CacheManager();

      // Check if category changed (for existing tasks only)
      final bool categoryChanged =
          _localTask != null && _localTask!.categoryId != widget.category.id;

      if (categoryChanged) {
        print(
            'TaskEditScreen: Category changed from ${_localTask!.categoryId} to ${widget.category.id}');
        // If the cache is on the old category, refresh from API to get updated task list
        if (cacheManager.currentCategory?.id == _localTask!.categoryId) {
          print('TaskEditScreen: Refreshing old category cache from API...');
          await cacheManager.refreshCurrentCategoryTasks();
        }
        // Note: If cache is on the new category, it will be refreshed when user navigates there
      } else {
        // Category didn't change, update normally if cache is on this category
        if (cacheManager.currentCategory?.id == widget.category.id) {
          print(
              'TaskEditScreen: Updating task in cache... (new task: ${_localTask == null})');
          if (updatedTask != null) {
            await cacheManager.updateTask(updatedTask);
          }
        } else {
          print(
              'TaskEditScreen: Cache is on different category (${cacheManager.currentCategory?.id} vs ${widget.category.id}), skipping cache update');
        }
      }

      print(
        'TaskEditScreen: Task saved successfully, calling edit complete callback...',
      );
      // Call the edit complete callback before popping
      if (TaskEditScreen.onEditComplete != null) {
        print('TaskEditScreen: Static callback available, calling it...');
        try {
          TaskEditScreen.onEditComplete!();
          print('TaskEditScreen: Static callback executed successfully');
        } catch (e) {
          print('TaskEditScreen: Error executing static callback: $e');
        }
      } else {
        print('TaskEditScreen: No static callback available');
      }

      if (mounted) {
        print('TaskEditScreen: Popping screen with true result...');
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      print('TaskEditScreen: Error saving task: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteTask() async {
    if (_localTask == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${NamingUtils.tasksName(plural: false)}?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = AuthUtils.getCurrentUserId();

      await supabase
          .from('Tasks')
          .delete()
          .eq('id', _localTask!.id)
          .eq('owner_id', userId);

      print('Deleted task: ${_localTask!.headline}');

      // Update the task cache using CacheManager
      print('TaskEditScreen: Updating task cache after deletion...');
      final cacheManager = CacheManager();
      if (cacheManager.currentCategory?.id == widget.category.id) {
        print('TaskEditScreen: Removing task from cache...');
        await cacheManager.removeTask(_localTask!.id);
        print('TaskEditScreen: Task removed from cache successfully');
      }

      // Call the edit complete callback to notify the parent screen
      if (TaskEditScreen.onEditComplete != null) {
        print(
            'TaskEditScreen: Calling edit complete callback after deletion...');
        try {
          TaskEditScreen.onEditComplete!();
          print('TaskEditScreen: Edit complete callback executed successfully');
        } catch (e) {
          print('TaskEditScreen: Error executing edit complete callback: $e');
        }
      }

      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      print('Error deleting task: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _handleBack() {
    print('TaskEditScreen: Back button pressed');
    print('TaskEditScreen: Current task: ${_localTask?.headline}');
    print(
      'TaskEditScreen: Static callback available: ${TaskEditScreen.onEditComplete != null}',
    );

    // Don't call the callback when going back without saving
    print('TaskEditScreen: Going back without saving, not calling callback');

    // Pop without calling the callback since changes weren't saved
    if (mounted) {
      Navigator.of(
        context,
      ).pop(false); // Return false to indicate no changes were saved
      print('TaskEditScreen: Popped screen with false result');
    } else {
      print('TaskEditScreen: Widget not mounted, cannot pop');
    }
  }

  Widget _buildLinksList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Links:', style: TextStyle(fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add link',
              onPressed: _isLoading ? null : _addLink,
              style: AppButtons.iconGoForth(),
            ),
          ],
        ),
        if (_links.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...List.generate(_links.length, (index) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: LinkDisplayWidget(
                        linkText: _links[index],
                        showIcon: true,
                        showTitle: true,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit link',
                      onPressed: _isLoading ? null : () => _editLink(index),
                    ),
                    // Only show delete button for authenticated users
                    if (!AuthUtils.isGuestUser())
                      IconButton(
                        icon: const Icon(Icons.delete),
                        tooltip: 'Delete link',
                        onPressed: _isLoading ? null : () => _removeLink(index),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  List<Widget> _buildFormChildren() {
    return [
              // Info message banner (if provided)
              if (widget.infoMessage != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.blue[200]!,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue[700],
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.infoMessage!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.blue[900],
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
                          hintText:
                              'What have you been meaning to do?\n\nYou can use Enter to add line breaks for multi-line headlines.\n\nTip: Paste a link to automatically extract it and set the link title as the headline.',
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
                        enabled: !_isLoading,
                      ),
                      // Show preview of links that will be extracted from headline
                      if (_headlineController.text.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        FutureBuilder<Map<String, dynamic>>(
                          future:
                              _processHeadlineText(_headlineController.text),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              final processedData = snapshot.data!;
                              final newLinks =
                                  processedData['links'] as List<String>;

                              if (newLinks.isNotEmpty) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Links that will be extracted from headline:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    ...newLinks
                                        .map((link) => Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              margin: const EdgeInsets.only(
                                                  bottom: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                    color:
                                                        Colors.blue.shade200),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(Icons.link,
                                                      size: 16,
                                                      color:
                                                          Colors.blue.shade600),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      link,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors
                                                            .blue.shade700,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ))
                                        .toList(),
                                  ],
                                );
                              }
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          hintText: 'Add any additional details...',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                        enabled: !_isLoading,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Error: $_error',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                      _buildLinksList(),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          // Cancel button (only show when editing existing task)
                          if (_localTask != null) ...[
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _isLoading
                                    ? null
                                    : () => Navigator.pop(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey[300],
                                  foregroundColor: Colors.black,
                                  minimumSize: const Size(0, 48),
                                ),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 16),
                          ],
                          // Save button
                          Expanded(
                            child: ElevatedButton(
                              onPressed: (_isLoading ||
                                      _headlineController.text.trim().isEmpty)
                                  ? null
                                  : _saveTask,
                              style: AppButtons.finalize().copyWith(
                                minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Text(
                                      _localTask == null
                                          ? 'Register ${NamingUtils.tasksName(plural: false)}'
                                          : 'Save Changes',
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_localTask == null) ...[
                const SizedBox(height: 16),
                Center(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Alternative options section - only show if enabled
                      if (widget.showAlternativeOptions) ...[
                        // Labeled divider to set off alternatives (now inside container)
                        const Row(
                          children: [
                            Expanded(child: Divider()),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 2.0),
                              child: Text(
                                'Alternative options',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                            Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Add a List of Tasks button
                        FractionallySizedBox(
                          widthFactor: 0.7,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading
                                ? null
                                : () async {
                                    final result =
                                        await Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => AddTasksScreen(
                                          category: widget.category,
                                          currentTask: _currentTaskState,
                                        ),
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.add_task),
                            label: Text(
                                'Add a List of ${NamingUtils.tasksName(plural: true)}'),
                            style: AppButtons.goForth(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Separator with helpful text for shop suggestions
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Text(
                                '** You can also get ${NamingUtils.tasksName(plural: true)} from other people! **',
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
                        // Shop for Suggestions button with pre-check
                        FutureBuilder<bool>(
                          future: ShopEndeavorsScreen
                              .hasAnyPublicSuggestionsForCategory(
                                  widget.category),
                          builder: (context, snapshot) {
                            final hasSuggestions = snapshot.data == true;
                            return FractionallySizedBox(
                              widthFactor: 0.7,
                              child: ElevatedButton.icon(
                                onPressed: (_isLoading || !hasSuggestions)
                                    ? null
                                    : () async {
                                        final result =
                                            await Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                ShopEndeavorsScreen(
                                              existingCategory: widget.category,
                                            ),
                                          ),
                                        );
                                        print(
                                            'TaskEditScreen: ShopEndeavorsScreen returned: $result');
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
                            );
                          },
                        ),
                        if (widget.category.originalId != null &&
                            (widget.category.originalId == 1 ||
                                widget.category.originalId == 2)) ...[
                          const SizedBox(height: 24),
                          // Separator with helpful text for JustWatch import
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0),
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
                          // Single JustWatch Import button
                          FractionallySizedBox(
                            widthFactor: 0.7,
                            child: ElevatedButton.icon(
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      print(
                                          'Import from JustWatch button pressed');
                                      print(
                                          'Category: ${widget.category.headline}');

                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              JustWatchImportScreen(
                                            category: widget.category,
                                          ),
                                        ),
                                      ).then((result) {
                                        if (result is Category && mounted) {
                                          print('JustWatch import completed');
                                          Navigator.pop(context, result);
                                        }
                                      });
                                    },
                              icon: const DomainFaviconWidget(
                                domain: 'www.justwatch.com',
                                size: 20,
                                fallbackIcon: Icon(Icons.movie),
                              ),
                              label: const Text('Import from JustWatch'),
                              style: AppButtons.goForth(),
                            ),
                          ),
                        ],
                        // Add Letterboxd import button only for category original_id == 1
                        if (widget.category.originalId == 1) ...[
                          const SizedBox(height: 16),
                          // Separator for Letterboxd import
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0),
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
                          // Letterboxd Import button
                          FractionallySizedBox(
                            widthFactor: 0.7,
                            child: ElevatedButton.icon(
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      print(
                                          'Import from Letterboxd button pressed');
                                      print(
                                          'Category: ${widget.category.headline}');

                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              LetterboxdImportScreen(
                                            category: widget.category,
                                          ),
                                        ),
                                      ).then((result) {
                                        if (result is Category && mounted) {
                                          print('Letterboxd import completed');
                                          Navigator.pop(context, result);
                                        }
                                      });
                                    },
                              icon: const DomainFaviconWidget(
                                domain: 'letterboxd.com',
                                size: 20,
                                fallbackIcon: Icon(Icons.movie_outlined),
                              ),
                              label: const Text('Import from Letterboxd'),
                              style: AppButtons.goForth(),
                            ),
                          ),
                        ],
                      ], // Close the showAlternativeOptions conditional
                    ],
                  ),
                ),
              ],
    ];
  }

  Widget _buildPanelContent() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: _buildFormChildren(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isPanel) {
      return _buildPanelContent();
    }
    return WillPopScope(
      onWillPop: () async {
        print('TaskEditScreen: WillPopScope triggered');
        _handleBack();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              print('TaskEditScreen: Back button pressed in app bar');
              _handleBack();
            },
          ),
          title: Text(
            _localTask == null
                ? 'New ${NamingUtils.tasksName(capitalize: true, plural: false)} to ${widget.category.headline}'
                : 'Edit ${NamingUtils.tasksName(capitalize: true, plural: false)} to ${widget.category.headline}',
          ),
          actions: [
            // Only show delete button for authenticated users
            if (_localTask != null && !AuthUtils.isGuestUser())
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: _isLoading ? null : _deleteTask,
                tooltip:
                    'Delete ${NamingUtils.tasksName(capitalize: false, plural: false)}',
              ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: _buildFormChildren(),
          ),
        ),
      ),
    );
  }
}
