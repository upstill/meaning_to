import 'package:flutter/material.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/task_edit_screen.dart';
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/utils/cache_manager.dart';

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
    final result = await Navigator.pushNamed(
      context,
      '/edit-task',
      arguments: {'category': category, 'task': null},
    );

    if (result == true) {
      // Refresh the cache to get the new task
      try {
        final userId = AuthUtils.getCurrentUserId();
        await CacheManager().refreshFromApi();
        print('AddTaskManuallyButton: Cache refreshed after task creation');
      } catch (e) {
        print('AddTaskManuallyButton: Error refreshing cache: $e');
      }

      // Call the callback if provided
      if (onTaskAdded != null) {
        onTaskAdded!();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: isLoading ? null : () => _createTask(context),
      icon: const Icon(Icons.add),
      label: const Text('Add a Task Manually'),
    );
  }
}
