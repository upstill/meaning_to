import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/app_buttons.dart';
import 'package:meaning_to/utils/naming.dart';

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
    // Pop back to the New Content screen
    Navigator.pop(context);
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
