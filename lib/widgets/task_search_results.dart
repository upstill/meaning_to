import 'package:flutter/material.dart';
import 'package:meaning_to/theme/app_colors.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/models/category.dart';

/// Renders task search results grouped by pursuit (Category), with the
/// searching / empty-query / no-results placeholder states.
///
/// The per-task row is delegated to [taskTileBuilder] so each caller can supply
/// its own tile (Home uses a full [TaskDisplay]; the add-to-existing picker uses
/// a simple selectable [ListTile]).
class TaskSearchResults extends StatelessWidget {
  /// Flat list of matching tasks (grouped internally by [Task.categoryId]).
  final List<Task> results;

  /// True while a search request is in flight.
  final bool isSearching;

  /// The current query text (used to distinguish "no query yet" from "no hits").
  final String query;

  /// All owned pursuits, used to resolve each task's Category by id.
  final List<Category> categories;

  /// Tapped on a pursuit header. Null to make headers non-interactive.
  final void Function(Category)? onCategoryTap;

  /// Builds the row for a single task within its pursuit group.
  final Widget Function(Task, Category) taskTileBuilder;

  const TaskSearchResults({
    super.key,
    required this.results,
    required this.isSearching,
    required this.query,
    required this.categories,
    required this.taskTileBuilder,
    this.onCategoryTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isSearching) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Searching...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (query.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Enter a search term to find tasks',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No tasks found',
                style: TextStyle(fontSize: 16, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Text('Try a different search term',
                style: TextStyle(fontSize: 14, color: Colors.grey[500])),
          ],
        ),
      );
    }

    final Map<int, List<Task>> tasksByCategory = {};
    for (final task in results) {
      tasksByCategory.putIfAbsent(task.categoryId, () => []).add(task);
    }
    final Map<int, Category> categoryMap = {
      for (final cat in categories) cat.id: cat
    };

    return ListView.builder(
      itemCount: tasksByCategory.length,
      itemBuilder: (context, index) {
        final categoryId = tasksByCategory.keys.elementAt(index);
        final category = categoryMap[categoryId];
        final tasks = tasksByCategory[categoryId]!;
        if (category == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: InkWell(
                onTap: onCategoryTap == null
                    ? null
                    : () => onCategoryTap!(category),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        category.headline,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                      ),
                    ),
                    if (onCategoryTap != null)
                      const Icon(Icons.arrow_forward_ios,
                          size: 16, color: Colors.grey),
                  ],
                ),
              ),
            ),
            ...tasks.map((task) => taskTileBuilder(task, category)),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}
