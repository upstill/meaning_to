import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/widgets/link_display.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/cache_manager.dart';
import 'package:meaning_to/utils/synopsis_fetcher.dart';
import 'package:flutter_html/flutter_html.dart';

class TaskDisplay extends StatefulWidget {
  final Task task;
  final bool withControls;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;
  final Function(DateTime)? onUpdateSuggestibleAt;
  final Function(bool)? onShareToggle;
  final bool? isCategoryPrivate;
  final VoidCallback? onMakeCategoryPublic;

  const TaskDisplay({
    super.key,
    required this.task,
    this.withControls = false,
    this.onEdit,
    this.onDelete,
    this.onTap,
    this.onUpdateSuggestibleAt,
    this.onShareToggle,
    this.isCategoryPrivate,
    this.onMakeCategoryPublic,
  });

  /// Builds a widget to display a task, with optional controls.
  ///
  /// The [withControls] parameter determines whether to show edit/delete buttons.
  /// If [withControls] is true, [onEdit] and [onDelete] callbacks must be provided.
  static Widget buildTaskWidget({
    required Task task,
    required bool withControls,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
    VoidCallback? onTap,
    Function(DateTime)? onUpdateSuggestibleAt,
    Function(bool)? onShareToggle,
    bool? isCategoryPrivate,
    VoidCallback? onMakeCategoryPublic,
  }) {
    return TaskDisplay(
      task: task,
      withControls: withControls,
      onEdit: onEdit,
      onDelete: onDelete,
      onTap: onTap,
      onUpdateSuggestibleAt: onUpdateSuggestibleAt,
      onShareToggle: onShareToggle,
      isCategoryPrivate: isCategoryPrivate,
      onMakeCategoryPublic: onMakeCategoryPublic,
    );
  }

  @override
  State<TaskDisplay> createState() => _TaskDisplayState();
}

class _TaskDisplayState extends State<TaskDisplay> {
  bool _isExpanded = false;
  bool _isFetchingSynopsis = false;
  String? _fetchedSynopsis;
  String? _resolvedMoreUrl; // Store resolved URL for (more) link

  /// Simple method to extract URL from first link (no complex resolution)
  Future<void> _resolveMoreUrl() async {
    if (widget.task.links == null || widget.task.links!.isEmpty) {
      return;
    }

    for (final link in widget.task.links!) {
      // Extract URL from HTML link or return plain URL
      String? url;
      if (link.startsWith('http://') || link.startsWith('https://')) {
        url = link;
      } else {
        final regex = RegExp(r'href=["\x27]([^"\x27]+)["\x27]');
        final match = regex.firstMatch(link);
        url = match?.group(1);
      }

      if (url != null) {
        if (mounted) {
          setState(() {
            _resolvedMoreUrl = url!; // Use original URL, no resolution
          });
        }
        break;
      }
    }
  }

  @override
  void initState() {
    super.initState();
  }

  /// Fetch synopsis from task links using the SynopsisFetcher utility
  Future<void> _fetchSynopsisFromLinks() async {
    print(
        'TaskDisplay: _fetchSynopsisFromLinks called for task: ${widget.task.headline}');

    // Skip if already fetching
    if (_isFetchingSynopsis) {
      print('TaskDisplay: Skipping fetch - already fetching');
      return;
    }

    setState(() {
      _isFetchingSynopsis = true;
    });

    try {
      final result = await SynopsisFetcher.fetchSynopsisForTask(widget.task);

      if (result != null && mounted) {
        setState(() {
          _fetchedSynopsis = result.synopsis;
        });
        print('TaskDisplay: Synopsis fetched from ${result.source.name}');
      }
    } catch (e) {
      print('TaskDisplay: Error fetching synopsis: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingSynopsis = false;
        });
      }
    }
  }

  /// Check if we should fetch synopsis (synopsis is null or empty AND task has links)
  bool _shouldFetchNotes() {
    final synopsis = widget.task.synopsis;
    final links = widget.task.links;

    // Only fetch synopsis if it is null or empty AND the task has links to fetch from
    if ((synopsis == null || synopsis.trim().isEmpty) &&
        links != null &&
        links.isNotEmpty) {
      return true;
    }

    return false;
  }

  /// Clear fallback notes (for web users with old imported tasks)
  Future<void> _clearFallbackNotes() async {
    try {
      final updatedTask = Task(
        id: widget.task.id,
        categoryId: widget.task.categoryId,
        headline: widget.task.headline,
        notes: null, // Clear the notes
        ownerId: widget.task.ownerId,
        createdAt: widget.task.createdAt,
        suggestibleAt: widget.task.suggestibleAt,
        triggersAt: widget.task.triggersAt,
        deferral: widget.task.deferral,
        links: widget.task.links,
        processedLinks: widget.task.processedLinks,
        finished: widget.task.finished,
        shared: widget.task.shared,
        originalId: widget.task.originalId,
        dirty: true, // Mark as dirty to trigger database update
      );

      await CacheManager().updateTask(updatedTask);

      if (mounted) {
        setState(() {
          // This will cause the widget to rebuild with null notes
        });

        // On non-web platforms, trigger fetching after clearing
        if (!kIsWeb) {
          _fetchSynopsisFromLinks();
        }
      }
    } catch (e) {}
  }

  void _toggleExpanded() {
    if (!mounted) return;
    setState(() {
      _isExpanded = !_isExpanded;
    });

    // If expanding, extract URL from first link
    if (_isExpanded && _resolvedMoreUrl == null) {
      _resolveMoreUrl();
    }

    // If expanding and synopsis is null/empty, try to fetch it from links
    if (_isExpanded) {
      final shouldFetch = _shouldFetchNotes();
      if (shouldFetch && _fetchedSynopsis == null && !_isFetchingSynopsis) {
        _fetchSynopsisFromLinks();
      }
    }
  }

  void _showPrivateCategoryDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Private Pursuit'),
          content: const Text(
            'This pursuit is private, so ideas aren\'t being shared. Would you like to make the pursuit public so you can share them?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (widget.onMakeCategoryPublic != null) {
                  widget.onMakeCategoryPublic!();
                }
              },
              child: const Text('Yes, please share'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Use the new method from Task class for consistent evaluation
    // final isDeferred = widget.task.isDeferred; // Not currently used

    // Optimized hasLinks check - avoid complex operations during build
    final hasLinks = widget.task.links?.isNotEmpty == true;

    // Links available for display

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min, // Add this to ensure proper sizing
        children: [
          // Main task content
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Task headline and controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title with flexible width - clickable to toggle expanded state, with arrow
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          _toggleExpanded();
                        },
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  // Use gray for deferred or finished tasks, black for available tasks
                                  final textColor = (widget.task.isDeferred ||
                                          widget.task.finished)
                                      ? Colors.grey
                                      : Colors.black;

                                  return Text(
                                    widget.task.headline,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: textColor,
                                    ),
                                    softWrap: true,
                                    maxLines: null,
                                  );
                                },
                              ),
                            ),
                            if (hasLinks ||
                                (widget.task.notes != null &&
                                    widget.task.notes!.isNotEmpty) ||
                                (widget.task.synopsis != null &&
                                    widget.task.synopsis!.isNotEmpty) ||
                                _shouldFetchNotes())
                              Padding(
                                padding: const EdgeInsets.only(left: 4.0),
                                child: Text(
                                  _isExpanded ? '\u25B2' : '\u25BC', // ▲ or ▼
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Controls bundle - finished checkbox, edit, delete
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Finished checkbox
                        Builder(
                          builder: (context) {
                            return Container(
                              /* decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(4),
                              ), */
                              child: Checkbox(
                                value: widget.task.finished,
                                onChanged: (value) {
                                  if (widget.onTap != null) {
                                    widget.onTap!();
                                  }
                                },
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                            );
                          },
                        ),
                        // Share control
                        Builder(
                          builder: (context) {
                            return Container(
                              child: SizedBox(
                                width: 30,
                                height: 30,
                                child: IconButton(
                                  icon: Icon(
                                    // If category is private, always show as unshared
                                    (widget.isCategoryPrivate == true ||
                                            !widget.task.shared)
                                        ? Icons.share_outlined
                                        : Icons.share_sharp,
                                    size:
                                        18, // Slightly larger for better visibility
                                    color: (widget.isCategoryPrivate == true ||
                                            !widget.task.shared)
                                        ? Colors.grey
                                            .shade400 // Medium gray for unshared state
                                        : Colors.green.shade700,
                                  ),
                                  onPressed: () {
                                    // If category is private and user is trying to share, show dialog
                                    if (widget.isCategoryPrivate == true &&
                                        !widget.task.shared) {
                                      _showPrivateCategoryDialog(context);
                                    } else if (widget.onShareToggle != null) {
                                      widget.onShareToggle!(
                                        !widget.task.shared,
                                      );
                                    }
                                  },
                                  tooltip: (widget.isCategoryPrivate == true ||
                                          !widget.task.shared)
                                      ? 'Share task'
                                      : 'Unshare task',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 30,
                                    minHeight: 30,
                                    maxWidth: 30,
                                    maxHeight: 30,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        // Edit and Delete buttons grouped tightly together
                        if (widget.withControls) ...[
                          Builder(
                            builder: (context) {
                              return Container(
                                /* decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(4),
                                ), */
                                child: SizedBox(
                                  width: 30,
                                  height: 30,
                                  child: IconButton(
                                    icon: const Icon(Icons.edit, size: 16),
                                    onPressed: widget.onEdit,
                                    tooltip: 'Edit task',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 30,
                                      minHeight: 30,
                                      maxWidth: 30,
                                      maxHeight: 30,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          // Only show delete button for authenticated users
                          if (!AuthUtils.isGuestUser()) ...[
                            Builder(
                              builder: (context) {
                                return Container(
                                  /*                                   decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
 */
                                  child: SizedBox(
                                    width: 30,
                                    height: 30,
                                    child: IconButton(
                                      icon: const Icon(Icons.delete, size: 16),
                                      onPressed: widget.onDelete,
                                      tooltip: 'Delete task',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 30,
                                        minHeight: 30,
                                        maxWidth: 30,
                                        maxHeight: 30,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ],
                    ),
                  ],
                ),
                // Show notes if expanded and present (either existing or fetched)
                if (_isExpanded) ...[
                  // Show loading indicator if fetching notes
                  if (_isFetchingSynopsis) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Fetching description...',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ]
                  // Show notes if available (user-entered content)
                  else if (widget.task.notes != null &&
                      widget.task.notes!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Html(
                      data: widget.task.notes!,
                      style: {
                        "body": Style(
                          fontSize: FontSize(
                            theme.textTheme.bodyMedium?.fontSize ?? 14,
                          ),
                          color: theme.textTheme.bodySmall?.color,
                          margin: Margins.zero,
                          padding: HtmlPaddings.zero,
                        ),
                        "a": Style(
                          color: theme.colorScheme.primary,
                          textDecoration: TextDecoration.underline,
                        ),
                      },
                      onLinkTap: (url, htmlContext, attributes) async {
                        if (url != null) {
                          try {
                            await LinkDisplay.handleUrl(url, context);
                          } catch (e) {
                            // Error handling without verbose logging
                          }
                        }
                      },
                    ),
                  ],
                  // Show synopsis if available (auto-fetched or stored)
                  if (_isExpanded &&
                      ((_fetchedSynopsis != null &&
                              _fetchedSynopsis!.isNotEmpty) ||
                          (widget.task.synopsis != null &&
                              widget.task.synopsis!.isNotEmpty))) ...[
                    const SizedBox(height: 8),
                    Builder(
                      builder: (context) {
                        final htmlData =
                            _fetchedSynopsis ?? widget.task.synopsis ?? '';

                        // Check if this is a Letterboxd or JustWatch task with a (more) link
                        final isLetterboxdTask = htmlData.contains('boxd.it') ||
                            htmlData.contains('letterboxd.com');
                        final isJustWatchTask = htmlData.contains(
                          'justwatch.com',
                        );
                        final hasMoreLink = htmlData.contains('(more)');

                        if ((isLetterboxdTask || isJustWatchTask) &&
                            hasMoreLink) {
                          // Parse the HTML manually for better link handling
                          final parts = htmlData.split('<a href="');
                          if (parts.length >= 2) {
                            final beforeLink = parts[0];
                            final linkPart = parts[1];
                            final urlEndIndex = linkPart.indexOf('"');
                            if (urlEndIndex > 0) {
                              final url = linkPart.substring(0, urlEndIndex);
                              final afterUrl = linkPart.substring(urlEndIndex);
                              final linkTextMatch = RegExp(
                                r'>([^<]+)</a>',
                              ).firstMatch(afterUrl);
                              final linkText =
                                  linkTextMatch?.group(1) ?? '(more)';

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    beforeLink,
                                    style: TextStyle(
                                      fontSize: theme
                                              .textTheme.bodyMedium?.fontSize ??
                                          14,
                                      fontStyle: FontStyle.italic,
                                      color: theme.textTheme.bodySmall?.color,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () async {
                                      final urlToLaunch =
                                          _resolvedMoreUrl ?? url;
                                      try {
                                        await LinkDisplay.handleUrl(
                                            urlToLaunch, context);
                                      } catch (e) {
                                        print('Error launching URL: $e');
                                      }
                                    },
                                    child: Text(
                                      linkText,
                                      style: TextStyle(
                                        fontSize: theme.textTheme.bodyMedium
                                                ?.fontSize ??
                                            14,
                                        fontStyle: FontStyle.italic,
                                        color: theme.colorScheme.primary,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }
                          }
                        }

                        // Fallback to HTML widget for other cases
                        return Html(
                          data: htmlData,
                          style: {
                            "body": Style(
                              fontSize: FontSize(
                                theme.textTheme.bodyMedium?.fontSize ?? 14,
                              ),
                              fontStyle: FontStyle.italic,
                              color: theme.textTheme.bodySmall?.color,
                              margin: Margins.zero,
                              padding: HtmlPaddings.zero,
                            ),
                            "a": Style(
                              color: theme.colorScheme.primary,
                              textDecoration: TextDecoration.underline,
                              fontStyle: FontStyle.italic,
                            ),
                          },
                          onLinkTap: (url, htmlContext, attributes) async {
                            if (url != null) {
                              try {
                                // Use resolved URL if available, otherwise use original
                                final urlToLaunch = _resolvedMoreUrl ?? url;

                                // Use centralized URL handling with letterboxd protection
                                await LinkDisplay.handleUrl(
                                    urlToLaunch, context);
                              } catch (e) {
                                // Error handling without verbose logging
                              }
                            }
                          },
                        );
                      },
                    ),
                  ],
                  // Show suggestible time for deferred tasks (after synopsis)
                  if (widget.task.isDeferred &&
                      widget.task.suggestibleAt != null &&
                      widget.task.suggestibleAt!.isAfter(DateTime.now())) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.schedule, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          'Available again in ${_formatSuggestibleTime(widget.task.suggestibleAt!.toLocal())}  ',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        if (widget.onUpdateSuggestibleAt != null) ...[
                          ElevatedButton(
                            onPressed: () {
                              widget.onUpdateSuggestibleAt!(DateTime.now());
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              minimumSize: const Size(0, 28),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            child: const Text('Make Available Now'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
                // Show links if expanded and present
                if (_isExpanded && hasLinks) ...[
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...widget.task.links!.map(
                        (link) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: LinkDisplay(
                            linkText: link,
                            showIcon: true,
                            showTitle: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Format a suggestible time for display
  static String _formatSuggestibleTime(DateTime date) {
    final now = DateTime.now().toUtc(); // Use UTC for consistent comparison
    final difference = date.difference(now);

    // If the time has already passed, show "now"
    if (difference.isNegative) {
      return 'now';
    }

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes < 2) {
          return '${difference.inSeconds}s';
        }
        return '${difference.inMinutes}m';
      }
      return '${difference.inHours}h';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }
}
