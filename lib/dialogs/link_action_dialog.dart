import 'package:flutter/material.dart';
import 'package:meaning_to/utils/incoming_link_processor.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/dialogs/category_picker_dialog.dart';
import 'package:meaning_to/dialogs/task_picker_dialog.dart';
import 'package:meaning_to/task_edit_screen.dart';

/// Primary dialog for handling incoming shared links
class LinkActionDialog extends StatelessWidget {
  final LinkProcessingResult result;
  final Category? defaultCategory;

  const LinkActionDialog({
    super.key,
    required this.result,
    this.defaultCategory,
  });

  static Future<void> show(
    BuildContext context,
    LinkProcessingResult result, {
    Category? defaultCategory,
  }) {
    return showDialog(
      context: context,
      builder: (context) => LinkActionDialog(
        result: result,
        defaultCategory: defaultCategory,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show different UI based on whether duplicates were found
    if (result.duplicates.isNotEmpty) {
      return _buildDuplicateFoundDialog(context);
    } else {
      return _buildNewLinkDialog(context);
    }
  }

  Widget _buildDuplicateFoundDialog(BuildContext context) {
    final duplicate = result.duplicates.first;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange,
            size: 28,
          ),
          const SizedBox(width: 8),
          const Text('Link Already Exists'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This link already exists in:'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.task_alt,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        duplicate.task.headline,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      duplicate.category.headline,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (result.duplicates.length > 1) ...[
            const SizedBox(height: 8),
            Text(
              '...and ${result.duplicates.length - 1} other location(s)',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => _viewExistingTask(context, duplicate),
          child: const Text('View Task'),
        ),
        OutlinedButton(
          onPressed: () => _addAnyway(context),
          child: const Text('Add Anyway'),
        ),
      ],
    );
  }

  Widget _buildNewLinkDialog(BuildContext context) {
    final title = result.title ?? 'Untitled Link';

    return AlertDialog(
      title: const Text('Add Link'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Link preview section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.hasValidMetadata) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.link,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ] else ...[
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Could not extract title',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  result.url,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('What would you like to do with this link?'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton.icon(
          onPressed: () => _addToExistingTask(context),
          icon: const Icon(Icons.add_task, size: 18),
          label: const Text('Add to Task'),
        ),
        FilledButton.icon(
          onPressed: () => _createNewTask(context),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Create Task'),
        ),
      ],
    );
  }

  void _viewExistingTask(BuildContext context, DuplicateMatch duplicate) {
    Navigator.of(context).pop();

    // Navigate to the task edit screen for the existing task
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TaskEditScreen(
          category: duplicate.category,
          task: duplicate.task,
        ),
      ),
    );
  }

  void _addAnyway(BuildContext context) {
    Navigator.of(context).pop();

    // Show the new link dialog, ignoring the duplicate warning
    showDialog(
      context: context,
      builder: (context) => LinkActionDialog(
        result: LinkProcessingResult(
          url: result.url,
          title: result.title,
          description: result.description,
          duplicates: [], // Clear duplicates to show as new link
          hasValidMetadata: result.hasValidMetadata,
        ),
        defaultCategory: defaultCategory,
      ),
    );
  }

  void _createNewTask(BuildContext context) {
    Navigator.of(context).pop();

    // Show category selection dialog
    CategoryPickerDialog.show(
      context,
      title: 'Select Category for New Task',
      defaultCategory: defaultCategory,
      onCategorySelected: (category, {bool? shouldMove}) {
        _createTaskInCategory(context, category);
      },
    );
  }

  void _addToExistingTask(BuildContext context) {
    Navigator.of(context).pop();

    // Show task selection dialog
    TaskPickerDialog.show(
      context,
      title: 'Select Task to Add Link',
      onTaskSelected: (task, category) {
        _addLinkToTask(context, task, category);
      },
    );
  }

  void _createTaskInCategory(BuildContext context, Category category) {
    // Navigate to task creation screen with pre-populated link
    final htmlLink = result.hasValidMetadata
        ? '<a href="${result.url}">${result.title}</a>'
        : '<a href="${result.url}">${result.url}</a>';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TaskEditScreen(
          category: category,
          initialLinks: [htmlLink],
          initialHeadline: result.title,
        ),
      ),
    );
  }

  void _addLinkToTask(BuildContext context, Task task, Category category) {
    // Navigate to task edit screen with the link to add
    final htmlLink = result.hasValidMetadata
        ? '<a href="${result.url}">${result.title}</a>'
        : '<a href="${result.url}">${result.url}</a>';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TaskEditScreen(
          category: category,
          task: task,
          linkToAdd: htmlLink,
        ),
      ),
    );
  }
}