import 'package:flutter/material.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/widgets/link_display.dart';
import 'package:meaning_to/utils/auth.dart';

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

  @override
  void initState() {
    super.initState();
  }

  void _toggleExpanded() {
    if (!mounted) return; // Safety check
    setState(() {
      _isExpanded = !_isExpanded;
    });
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

    // Fix hasLinks check to handle List<String> of HTML links
    final hasLinks = widget.task.links != null &&
        widget.task.links!.isNotEmpty &&
        widget.task.links!
            .any((link) => link.trim().isNotEmpty && link != '{}');

    // Debug logging for links
    if (widget.task.links != null) {
      print(
          'TaskDisplay: Task "${widget.task.headline}" has ${widget.task.links!.length} links');
      print('TaskDisplay: Links: ${widget.task.links}');
      print('TaskDisplay: hasLinks: $hasLinks');
    }

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
                                    widget.task.notes!.isNotEmpty))
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
                                      widget
                                          .onShareToggle!(!widget.task.shared);
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
                // Show suggestible time for deferred tasks
                if (widget.task.isDeferred &&
                    widget.task.suggestibleAt != null &&
                    widget.task.suggestibleAt!.isAfter(DateTime.now())) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 14,
                        color: Colors.grey[600],
                      ),
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
                                horizontal: 10, vertical: 4),
                            minimumSize: const Size(0, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: theme.textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          child: const Text('Make Available Now'),
                        ),
                      ],
                    ],
                  ),
                ] else ...[
                  // No debug logging needed
                  const SizedBox.shrink(),
                ],
                // Show notes if expanded and present
                if (_isExpanded &&
                    widget.task.notes != null &&
                    widget.task.notes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.task.notes!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ],
                // Show links if expanded and present
                if (_isExpanded && hasLinks) ...[
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...widget.task.links!.map((link) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: LinkDisplay(
                              linkText: link,
                              showIcon: true,
                              showTitle: true,
                            ),
                          )),
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

  /// Format a date for display
  static String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'just now';
        }
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
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
