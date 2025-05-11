import 'dart:convert';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/models/category.dart';

final supabase = Supabase.instance.client;

class Task {
  final int id;
  final int categoryId;
  final String headline;
  final String? notes;
  final String ownerId;
  final DateTime createdAt;
  final DateTime? suggestibleAt;
  final DateTime? triggersAt;
  final int? deferral;
  final List<String>? links;
  final bool finished;

  Task({
    required this.id,
    required this.categoryId,
    required this.headline,
    this.notes,
    required this.ownerId,
    required this.createdAt,
    this.suggestibleAt,
    this.triggersAt,
    this.deferral,
    this.links,
    required this.finished,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    List<String>? parseLinks(dynamic linksData) {
      if (linksData == null) return null;
      if (linksData is List) {
        return List<String>.from(linksData);
      }
      if (linksData is String) {
        try {
          final decoded = jsonDecode(linksData) as List;
          return List<String>.from(decoded);
        } catch (e) {
          print('Error parsing links JSON: $e');
          return null;
        }
      }
      return null;
    }

    return Task(
      id: json['id'] as int,
      categoryId: json['category_id'] as int,
      headline: json['headline'] as String,
      notes: json['notes'] as String?,
      ownerId: json['owner_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      suggestibleAt: json['suggestible_at'] != null 
          ? DateTime.parse(json['suggestible_at'] as String)
          : null,
      triggersAt: json['triggers_at'] != null 
          ? DateTime.parse(json['triggers_at'] as String)
          : null,
      deferral: json['deferral'] as int?,
      links: parseLinks(json['links']),
      finished: json['finished'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category_id': categoryId,
      'headline': headline,
      'notes': notes,
      'owner_id': ownerId,
      'created_at': createdAt.toIso8601String(),
      'suggestible_at': suggestibleAt?.toIso8601String(),
      'triggers_at': triggersAt?.toIso8601String(),
      'deferral': deferral,
      'links': links != null ? jsonEncode(links) : null,
      'finished': finished,
    };
  }

  /// Fetches a random unfinished task for the given category and user.
  /// Returns null if no tasks are found.
  static Future<Task?> nextTask(Category category, String userId) async {
    try {
      print('Fetching tasks for category ${category.id} and user $userId');
      
      // Query tasks from the database
      final response = await supabase
          .from('Tasks')
          .select()
          .eq('category_id', category.id)
          .eq('owner_id', userId)
          .eq('finished', false)
          .order('created_at', ascending: false);
      
      print('Task response fields: ${response.isNotEmpty ? response.first.keys.toList() : 'No tasks found'}');

      if (response == null || response.isEmpty) {
        print('No tasks found for category ${category.id}');
        return null;
      }

      // Convert to Task objects
      final tasks = (response as List)
          .map((json) => Task.fromJson(json as Map<String, dynamic>))
          .toList();

      // Select a random task
      final random = Random();
      final randomTask = tasks[random.nextInt(tasks.length)];
      
      print('Selected random task: ${randomTask.headline}');
      return randomTask;
    } catch (e, stackTrace) {
      print('Error loading random task: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }
} 