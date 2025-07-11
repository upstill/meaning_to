import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:meaning_to/utils/auth.dart';

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

  static Future<List<Map<String, dynamic>>> getTasks() async {
    final result = await _makeRequest('getTasks');
    return List<Map<String, dynamic>>.from(result['data']);
  }

  static Future<Map<String, dynamic>> updateTask(
    String taskId,
    Map<String, dynamic> updates,
  ) async {
    final result = await _makeRequest('updateTask', data: {
      'taskId': taskId,
      'updates': updates,
    });
    return result['data'][0];
  }
}
