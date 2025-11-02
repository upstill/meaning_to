import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/app_buttons.dart';
import 'package:meaning_to/utils/naming.dart';
import 'package:meaning_to/new_content_screen.dart';

class AddTaskManuallyButton extends StatelessWidget {
  final Category category;
  final bool isLoading;
  final VoidCallback? onTaskAdded;

  const AddTaskManuallyButton({
    super.key,
    required this.category,
    this.isLoading = false,
    this.onTaskAdded,
  });

  Future<void> _createTask(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewContentScreen(
          selectedCategory: category,
          categoryLocked: true,
        ),
      ),
    );

    // If a task was created, call the callback
    if (result != null && onTaskAdded != null) {
      onTaskAdded!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: isLoading ? null : () => _createTask(context),
      icon: const Icon(Icons.add),
      label: Text(
          'Add ${NamingUtils.tasksName(capitalize: true, plural: false, withArticle: true)} manually'),
      style: AppButtons.goForth(),
    );
  }
}
