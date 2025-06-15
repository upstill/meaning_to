import 'package:flutter/material.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/widgets/link_display.dart';
import 'package:url_launcher/url_launcher.dart';

class TaskDisplay extends StatefulWidget {
  final Task task;
  final bool withControls;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  const TaskDisplay({
    super.key,
    required this.task,
    this.withControls = false,
    this.onEdit,
    this.onDelete,
    this.onTap,
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
  }) {
    return TaskDisplay(
      task: task,
      withControls: withControls,
      onEdit: onEdit,
      onDelete: onDelete,
      onTap: onTap,
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
    print('\n=== TaskDisplay initState for "${widget.task.headline}" ===');
    print('Task links: ${widget.task.links}');
    print('Task links type: ${widget.task.links?.runtimeType}');
    print('Task links length: ${widget.task.links?.length ?? 0}');
    print('Task links is null? ${widget.task.links == null}');
    print('Task links is empty? ${widget.task.links?.isEmpty}');
    if (widget.task.links?.isNotEmpty == true) {
      print('First link: ${widget.task.links!.first}');
      print('First link type: ${widget.task.links!.first.runtimeType}');
      print(
          'First link contains href: ${widget.task.links!.first.contains('href="')}');
      print(
          'First link contains justwatch: ${widget.task.links!.first.contains('justwatch.com')}');
    }
    print('=== End TaskDisplay initState ===\n');
  }

  void _toggleExpanded() {
    if (!mounted) return; // Safety check
    setState(() {
      _isExpanded = !_isExpanded;
    });
    print(
        'TaskDisplay: Toggled expanded state to $_isExpanded for ${widget.task.headline}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // SUPER detailed debug logging for link detection
    print('\n=== TaskDisplay build for "${widget.task.headline}" ===');
    print('Raw links data: ${widget.task.links}');
    print('Links type: ${widget.task.links?.runtimeType}');
    print('Links is null? ${widget.task.links == null}');
    print('Links is empty? ${widget.task.links?.isEmpty}');
    print('Links length: ${widget.task.links?.length ?? 0}');
    if (widget.task.links?.isNotEmpty == true) {
      print('First link: ${widget.task.links!.first}');
      print('First link type: ${widget.task.links!.first.runtimeType}');
      print(
          'First link contains href: ${widget.task.links!.first.contains('href="')}');
      print(
          'First link contains justwatch: ${widget.task.links!.first.contains('justwatch.com')}');
      print('First link toString: ${widget.task.links!.first.toString()}');
    }

    // Fix hasLinks check to handle List<String> of HTML links
    final hasLinks = widget.task.links != null &&
        widget.task.links!.isNotEmpty &&
        widget.task.links!.first.contains('href="'); // Only check for href
    print('\nhasLinks check:');
    print('  links != null: ${widget.task.links != null}');
    print('  links isNotEmpty: ${widget.task.links?.isNotEmpty}');
    print(
        '  first link contains href: ${widget.task.links?.firstOrNull?.toString().contains('href="')}');
    print('  FINAL hasLinks: $hasLinks');
    print('  withControls: ${widget.withControls}');
    print('=== End TaskDisplay build ===\n');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min, // Add this to ensure proper sizing
        children: [
          // Main task content
          InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Task headline and controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Title with flexible width
                      Expanded(
                        child: Text(
                          widget.task.headline,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // Controls bundle - expand, finished checkbox, edit, delete
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Expand button - only show if there are links or notes
                          if (hasLinks ||
                              (widget.task.notes != null &&
                                  widget.task.notes!.isNotEmpty)) ...[
                            Builder(
                              builder: (context) {
                                print(
                                    'TaskDisplay: Rendering expand button for "${widget.task.headline}"');
                                return Container(
                                  /* decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(4),
                                  ), */
                                  child: SizedBox(
                                    width: 30,
                                    height: 30,
                                    child: IconButton(
                                      icon: Icon(
                                        _isExpanded
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                        size: 16,
                                      ),
                                      onPressed: _toggleExpanded,
                                      tooltip: _isExpanded
                                          ? 'Hide details'
                                          : 'Show details',
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
                          // Finished checkbox
                          Builder(
                            builder: (context) {
                              print(
                                  'TaskDisplay: Rendering checkbox for "${widget.task.headline}"');
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
                          // Edit and Delete buttons grouped tightly together
                          if (widget.withControls) ...[
                            Builder(
                              builder: (context) {
                                print(
                                    'TaskDisplay: Rendering edit button for "${widget.task.headline}"');
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
                            Builder(
                              builder: (context) {
                                print(
                                    'TaskDisplay: Rendering delete button anew for "${widget.task.headline}"');
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
                      ),
                    ],
                  ),
                  // Show links if expanded
                  if (_isExpanded && hasLinks) ...[
                    const SizedBox(height: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Show notes if present
                        if (widget.task.notes != null &&
                            widget.task.notes!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.task.notes!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
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
}
