import 'package:meaning_to/models/task.dart';

class ShopItem {
  final String originalId;
  final String headline;
  final String? invitation;
  final List<String> categoryIds;
  List<Task> tasks;
  bool isSelected;
  bool isExpanded;
  bool tasksLoaded; // Track whether tasks have been loaded
  bool? hasTasksAvailable; // Track whether tasks exist (null = not checked yet)

  ShopItem({
    required this.originalId,
    required this.headline,
    this.invitation,
    required this.categoryIds,
    List<Task>? tasks,
    this.isSelected = false,
    this.isExpanded = false,
    this.tasksLoaded = false,
    this.hasTasksAvailable,
  }) : tasks = tasks ?? [];

  factory ShopItem.fromJson(Map<String, dynamic> json) {
    return ShopItem(
      originalId: json['original_id']?.toString() ?? '',
      headline: json['headline'] as String,
      invitation: json['invitation'] as String?,
      categoryIds: [json['id'].toString()], // Start with single category ID
      tasksLoaded: false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'originalId': originalId,
      'categoryIds': categoryIds,
      'isSelected': isSelected,
    };
  }
}
