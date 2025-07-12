import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/models/category.dart';

class ApiClient {
  static const String _baseUrl = '/api'; // Vercel API route

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
    final result = await _makeRequest('getTasks');
    return (result['data'] as List)
        .map((taskData) => Task.fromJson(taskData))
        .toList();
  }

  static Future<Task?> getTask(String taskId) async {
    try {
      final result = await _makeRequest('getTask', data: {
        'taskId': taskId,
      });
      return Task.fromJson(result['data'][0]);
    } catch (e) {
      // Task not found
      return null;
    }
  }

  static Future<Task> updateTask(
      String taskId, Map<String, dynamic> updates) async {
    final result = await _makeRequest('updateTask', data: {
      'taskId': taskId,
      'updates': updates,
    });
    return Task.fromJson(result['data'][0]);
  }

  static Future<Task> createTask(Map<String, dynamic> taskData) async {
    final result = await _makeRequest('createTask', data: taskData);
    return Task.fromJson(result['data'][0]);
  }

  static Future<Task> deleteTask(String taskId) async {
    final result = await _makeRequest('deleteTask', data: {
      'taskId': taskId,
    });
    return Task.fromJson(result['data'][0]);
  }

  // Additional task operations needed by Task model
  static Future<void> updateTaskSuggestibleAt(
      int taskId, String? suggestibleAt) async {
    await _makeRequest('updateTask', data: {
      'taskId': taskId.toString(),
      'updates': {
        'suggestible_at': suggestibleAt,
      },
    });
  }

  static Future<void> updateTaskFinished(int taskId, bool finished) async {
    await _makeRequest('updateTask', data: {
      'taskId': taskId.toString(),
      'updates': {
        'finished': finished,
      },
    });
  }

  static Future<void> updateTaskDeferral(int taskId, int? deferral) async {
    await _makeRequest('updateTask', data: {
      'taskId': taskId.toString(),
      'updates': {
        'deferral': deferral,
      },
    });
  }

  static Future<List<Task>> getTasksByCategoryAndUser(
      int categoryId, String userId) async {
    final result = await _makeRequest('getTasksByCategoryAndUser', data: {
      'categoryId': categoryId,
      'userId': userId,
    });
    return (result['data'] as List)
        .map((taskData) => Task.fromJson(taskData))
        .toList();
  }

  static Future<void> updateGuestTasks(String guestUserId) async {
    await _makeRequest('updateGuestTasks', data: {
      'guestUserId': guestUserId,
    });
  }

  // Category operations
  static Future<List<Category>> getCategories() async {
    final result = await _makeRequest('getCategories');
    return (result['data'] as List)
        .map((categoryData) => Category.fromJson(categoryData))
        .toList();
  }

  static Future<Category> createCategory(
      Map<String, dynamic> categoryData) async {
    final result = await _makeRequest('createCategory', data: categoryData);
    return Category.fromJson(result['data'][0]);
  }

  static Future<Category> deleteCategory(String categoryId) async {
    final result = await _makeRequest('deleteCategory', data: {
      'categoryId': categoryId,
    });
    return Category.fromJson(result['data'][0]);
  }
}
