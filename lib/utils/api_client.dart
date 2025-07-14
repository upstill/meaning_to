import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/models/category.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ApiClient {
  static const String _baseUrl = '/api'; // Vercel API route

  // Temporary: Use Supabase directly for testing
  static SupabaseClient get _supabase => Supabase.instance.client;

  static Future<Map<String, dynamic>> _makeRequest(
    String action, {
    Map<String, dynamic>? data,
  }) async {
    final userId = AuthUtils.getCurrentUserId();

    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'action': action,
        'data': data,
        'userId': userId,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('API request failed: ${response.statusCode}');
    }
  }

  // Task operations
  static Future<List<Task>> getTasks() async {
    try {
      // Temporary: Use Supabase directly
      final userId = AuthUtils.getCurrentUserId();
      final response =
          await _supabase.from('Tasks').select('*').eq('owner_id', userId);

      return (response as List)
          .map((taskData) => Task.fromJson(taskData))
          .toList();
    } catch (e) {
      print('Error getting tasks from Supabase: $e');
      rethrow;
    }
  }

  static Future<Task?> getTask(String taskId) async {
    try {
      // Temporary: Use Supabase directly
      final response =
          await _supabase.from('Tasks').select('*').eq('id', taskId).single();

      return Task.fromJson(response);
    } catch (e) {
      // Task not found
      return null;
    }
  }

  static Future<Task> updateTask(
      String taskId, Map<String, dynamic> updates) async {
    try {
      // Temporary: Use Supabase directly
      final response = await _supabase
          .from('Tasks')
          .update(updates)
          .eq('id', taskId)
          .select()
          .single();

      return Task.fromJson(response);
    } catch (e) {
      print('Error updating task in Supabase: $e');
      rethrow;
    }
  }

  static Future<Task> createTask(Map<String, dynamic> taskData) async {
    try {
      // Temporary: Use Supabase directly
      final response =
          await _supabase.from('Tasks').insert(taskData).select().single();

      return Task.fromJson(response);
    } catch (e) {
      print('Error creating task in Supabase: $e');
      rethrow;
    }
  }

  static Future<Task> deleteTask(String taskId) async {
    try {
      // Temporary: Use Supabase directly
      final response = await _supabase
          .from('Tasks')
          .delete()
          .eq('id', taskId)
          .select()
          .single();

      return Task.fromJson(response);
    } catch (e) {
      print('Error deleting task in Supabase: $e');
      rethrow;
    }
  }

  // Additional task operations needed by Task model
  static Future<void> updateTaskSuggestibleAt(
      int taskId, String? suggestibleAt) async {
    try {
      await _supabase.from('Tasks').update(
          {'suggestible_at': suggestibleAt}).eq('id', taskId.toString());
    } catch (e) {
      print('Error updating task suggestible_at in Supabase: $e');
      rethrow;
    }
  }

  static Future<void> updateTaskFinished(int taskId, bool finished) async {
    try {
      await _supabase
          .from('Tasks')
          .update({'finished': finished}).eq('id', taskId.toString());
    } catch (e) {
      print('Error updating task finished in Supabase: $e');
      rethrow;
    }
  }

  static Future<void> updateTaskDeferral(int taskId, int? deferral) async {
    try {
      await _supabase
          .from('Tasks')
          .update({'deferral': deferral}).eq('id', taskId.toString());
    } catch (e) {
      print('Error updating task deferral in Supabase: $e');
      rethrow;
    }
  }

  static Future<List<Task>> getTasksByCategoryAndUser(
      int categoryId, String userId) async {
    try {
      final response = await _supabase
          .from('Tasks')
          .select('*')
          .eq('category_id', categoryId)
          .eq('owner_id', userId);

      return (response as List)
          .map((taskData) => Task.fromJson(taskData))
          .toList();
    } catch (e) {
      print('Error getting tasks by category and user in Supabase: $e');
      rethrow;
    }
  }

  static Future<void> updateGuestTasks(String guestUserId) async {
    try {
      // This would be a complex operation, for now just log
      print('updateGuestTasks called for user: $guestUserId');
    } catch (e) {
      print('Error updating guest tasks in Supabase: $e');
      rethrow;
    }
  }

  // Category operations
  static Future<List<Category>> getCategories() async {
    try {
      // Temporary: Use Supabase directly
      final userId = AuthUtils.getCurrentUserId();
      print('Getting categories for user: $userId');
      print('User ID type: ${userId.runtimeType}');
      print('User ID length: ${userId.length}');

      // Check if Supabase client is working
      print('Supabase client initialized: ${_supabase != null}');

      // Get all categories and filter in Dart
      print('Getting all categories and filtering in Dart...');
      final allCategories = await _supabase.from('Categories').select('*');
      print('All categories in database: ${allCategories.length}');

      // Show all categories and their owner IDs
      print('All categories with owner IDs:');
      for (var category in allCategories) {
        print('- ${category['headline']} (owner: ${category['owner_id']})');
      }

      // Filter in Dart instead of database
      final filteredCategories = allCategories.where((category) {
        final ownerId = category['owner_id'] as String;
        final matches = ownerId == userId;
        print('Comparing $ownerId == $userId: $matches');
        return matches;
      }).toList();

      print('Filtered categories: ${filteredCategories.length}');

      for (var category in filteredCategories) {
        print(
            '- ${category['headline']} (ID: ${category['id']}, owner: ${category['owner_id']})');
      }

      return filteredCategories
          .map((categoryData) => Category.fromJson(categoryData))
          .toList();
    } catch (e) {
      print('Error getting categories from Supabase: $e');
      print('Error type: ${e.runtimeType}');
      rethrow;
    }
  }

  static Future<Category> createCategory(
      Map<String, dynamic> categoryData) async {
    try {
      // Temporary: Use Supabase directly
      final response = await _supabase
          .from('Categories')
          .insert(categoryData)
          .select()
          .single();

      return Category.fromJson(response);
    } catch (e) {
      print('Error creating category in Supabase: $e');
      rethrow;
    }
  }

  static Future<Category> deleteCategory(String categoryId) async {
    try {
      // Temporary: Use Supabase directly
      final response = await _supabase
          .from('Categories')
          .delete()
          .eq('id', categoryId)
          .select()
          .single();

      return Category.fromJson(response);
    } catch (e) {
      print('Error deleting category in Supabase: $e');
      rethrow;
    }
  }
}
