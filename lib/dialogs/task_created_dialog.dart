import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/utils/app_buttons.dart';
import 'package:meaning_to/utils/link_processor.dart';
import 'package:meaning_to/widgets/link_display.dart';

class TaskCreatedDialog extends StatelessWidget {
  final Map<String, dynamic> taskData;
  final Category category;

  const TaskCreatedDialog({
    super.key,
    required this.taskData,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    final String headline = taskData['headline'] ?? '';
    final String? notes = taskData['notes'];
    final List<String>? links = taskData['links']?.cast<String>();
    final bool shared = taskData['shared'] ?? false;

    return AlertDialog(
      title: Text(
          'New ${NamingUtils.tasksName(capitalize: true, plural: false)} to ${category.headline} Created!'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category
            const SizedBox(height: 12),

            // Headline
            Text(
              headline,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            // Notes if present
            if (notes != null && notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                notes,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
            ],

            // Links if present
            if (links != null && links.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Links:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              ...links.take(3).map((link) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: FutureBuilder<ProcessedLink>(
                      future: LinkProcessor.processLinkForDisplay(link),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Row(
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Loading link...',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          );
                        }

                        if (snapshot.hasError || !snapshot.hasData) {
                          // Fallback to raw text display
                          return Text(
                            link,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.blue,
                              decoration: TextDecoration.underline,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          );
                        }

                        // Use LinkDisplay.buildLinkWidget for proper display
                        return LinkDisplay.buildLinkWidget(
                          snapshot.data!,
                          context,
                        );
                      },
                    ),
                  )),
              if (links.length > 3)
                Text(
                  '... and ${links.length - 3} more',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],

            // Shared status
            if (shared) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.share, color: Colors.green[600], size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'Shared publicly',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green[600],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('accept'),
          child: const Text('Accept'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop('edit'),
          style: AppButtons.goForth(),
          child: const Text('Edit'),
        ),
      ],
    );
  }
}
