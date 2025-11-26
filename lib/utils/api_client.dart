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
      final isGuest = AuthUtils.isGuestUser();

      print('Getting tasks for user: $userId (guest: $isGuest)');

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
      // Parse taskId to int for proper database comparison
      final taskIdInt = int.parse(taskId);
      final response = await _supabase
          .from('Tasks')
          .update(updates)
          .eq('id', taskIdInt)
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

  static Future<Task?> deleteTask(String taskId) async {
    try {
      // Temporary: Use Supabase directly
      final response =
          await _supabase.from('Tasks').delete().eq('id', taskId).select();

      if ((response as List).isEmpty) {
        print('No task found to delete with ID: $taskId');
        return null;
      }

      final taskData = (response as List).first;
      return Task.fromJson(taskData);
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

  static Future<void> updateTaskShared(int taskId, bool shared) async {
    try {
      await _supabase
          .from('Tasks')
          .update({'shared': shared}).eq('id', taskId.toString());
    } catch (e) {
      print('Error updating task shared in Supabase: $e');
      rethrow;
    }
  }

  static Future<List<Task>> getTasksByCategoryAndUser(
      int categoryId, String userId) async {
    try {
      final response = await _supabase
          .from('Tasks')
          .select(
              'id,headline,notes,synopsis,category_id,owner_id,finished,shared,links,original_id,suggestible_at,created_at')
          .eq('category_id', categoryId)
          .eq('owner_id', userId)
          .order('suggestible_at', ascending: true)
          .order('created_at', ascending: false);

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
      print(
          'updateGuestTasks: Resetting all tasks for guest user: $guestUserId');

      // Reset all guest tasks to their initial state:
      // - suggestible_at: null (immediately suggestible)
      // - deferral: null (reset deferral counter)
      // - finished: false (mark as unfinished)
      await _supabase.from('Tasks').update({
        'suggestible_at': null,
        'deferral': null,
        'finished': false,
      }).eq('owner_id', guestUserId);

      print('updateGuestTasks: Successfully reset $guestUserId tasks');
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
      final isGuest = AuthUtils.isGuestUser();

      print('Getting categories for user: $userId (guest: $isGuest)');
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

      // Convert to Category objects first
      final categories = filteredCategories
          .map((categoryData) => Category.fromJson(categoryData))
          .toList();

      // Sort by last_access, most recent first
      categories.sort((a, b) {
        // Handle null last_access values (put them at the end)
        if (a.lastAccess == null && b.lastAccess == null) return 0;
        if (a.lastAccess == null) return 1;
        if (b.lastAccess == null) return -1;

        // Sort by last_access in descending order (most recent first)
        return b.lastAccess!.compareTo(a.lastAccess!);
      });

      return categories;
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

  static Future<Category> updateCategory(
      String categoryId, Map<String, dynamic> updates) async {
    try {
      // Temporary: Use Supabase directly
      final response = await _supabase
          .from('Categories')
          .update(updates)
          .eq('id', categoryId)
          .select()
          .single();

      return Category.fromJson(response);
    } catch (e) {
      print('Error updating category in Supabase: $e');
      rethrow;
    }
  }

  static Future<Category?> getCategoryById(int categoryId) async {
    try {
      // Temporary: Use Supabase directly
      final response = await _supabase
          .from('Categories')
          .select('*')
          .eq('id', categoryId)
          .single();

      return Category.fromJson(response);
    } catch (e) {
      // Category not found or other error
      print('Error fetching category by ID: $e');
      return null;
    }
  }

  static Future<String?> getCategoryHeadlineById(int categoryId) async {
    try {
      // Only fetch the headline column
      final response = await _supabase
          .from('Categories')
          .select('headline')
          .eq('id', categoryId)
          .single();

      return response['headline'] as String?;
    } catch (e) {
      // Category not found or other error
      print('Error fetching category headline by ID: $e');
      return null;
    }
  }

  /// Find duplicate task by headline or links
  /// Only searches within categories owned by the user that match specified original_ids
  /// Uses Postgres function for efficient filtering, then precise matching in Dart
  static Future<Task?> findDuplicateTask({
    required String userId,
    required String headline,
    List<String>? links,
    required List<int> categoryOriginalIds,
  }) async {
    try {
      print('ApiClient.findDuplicateTask:');
      print('  userId: $userId');
      print('  headline: "$headline"');
      print('  links: $links');
      print('  categoryOriginalIds: $categoryOriginalIds');

      List<Task> candidates = [];

      // Try to call the Postgres function first
      try {
        print('  Attempting to call Postgres function...');
        final response = await _supabase.rpc(
          'find_duplicate_tasks_by_link_or_headline',
          params: {
            'p_user_id': userId,
            'p_headline': headline,
            'p_links': links,
            'p_category_original_ids': categoryOriginalIds,
          },
        );

        if (response != null && (response as List).isNotEmpty) {
          candidates = (response as List)
              .map((data) => Task.fromJson(data as Map<String, dynamic>))
              .toList();
          print('  ✓ Postgres function returned ${candidates.length} candidate(s)');
        } else {
          print('  Postgres function returned no candidates');
        }
      } catch (rpcError) {
        print('  ⚠ Postgres function call failed: $rpcError');
        print('  Falling back to join-based query...');

        // Fallback: Use join-based query
        final response = await _supabase
            .from('Tasks')
            .select('*, Categories!inner(id, owner_id, original_id)')
            .eq('Categories.owner_id', userId)
            .inFilter('Categories.original_id', categoryOriginalIds)
            .ilike('headline', headline.trim());

        if (response != null && (response as List).isNotEmpty) {
          candidates = (response as List).map((data) {
            final taskData = Map<String, dynamic>.from(data);
            taskData.remove('Categories');
            return Task.fromJson(taskData);
          }).toList();
          print('  ✓ Join query returned ${candidates.length} candidate(s)');
        }

        // If no headline match and we have links, search by links
        if (candidates.isEmpty && links != null && links.isNotEmpty) {
          print('  Searching by links...');
          final tasksResponse = await _supabase
              .from('Tasks')
              .select('*, Categories!inner(id, owner_id, original_id)')
              .eq('Categories.owner_id', userId)
              .inFilter('Categories.original_id', categoryOriginalIds)
              .not('links', 'is', null);

          final allTasks = (tasksResponse as List);
          print('  Checking ${allTasks.length} tasks with links');

          final searchUrls = links
              .map((link) => _extractUrlFromLink(link)?.toLowerCase())
              .where((url) => url != null)
              .toSet();

          for (final taskData in allTasks) {
            final taskLinks = taskData['links'] as List<dynamic>?;
            if (taskLinks != null) {
              for (final taskLink in taskLinks) {
                final taskUrl = _extractUrlFromLink(taskLink.toString())?.toLowerCase();
                if (taskUrl != null && searchUrls.contains(taskUrl)) {
                  final cleanTaskData = Map<String, dynamic>.from(taskData);
                  cleanTaskData.remove('Categories');
                  candidates.add(Task.fromJson(cleanTaskData));
                  break;
                }
              }
            }
          }
          print('  Found ${candidates.length} link-matching candidates');
        }
      }

      if (candidates.isEmpty) {
        print('  No duplicate candidates found');
        return null;
      }

      // Now do precise matching in Dart to find the best match
      // Priority 1: Exact headline match
      for (final candidate in candidates) {
        if (candidate.headline.toLowerCase().trim() ==
            headline.toLowerCase().trim()) {
          print('  ✓ Found exact headline match: "${candidate.headline}"');
          return candidate;
        }
      }

      // Priority 2: URL match with extracted URL comparison
      if (links != null && links.isNotEmpty) {
        final searchUrls = links
            .map((link) => _extractUrlFromLink(link)?.toLowerCase())
            .where((url) => url != null)
            .toSet();

        print('  Extracted ${searchUrls.length} search URLs for matching');

        for (final candidate in candidates) {
          if (candidate.links != null) {
            for (final candidateLink in candidate.links!) {
              final candidateUrl =
                  _extractUrlFromLink(candidateLink)?.toLowerCase();
              if (candidateUrl != null && searchUrls.contains(candidateUrl)) {
                print('  ✓ Found URL match: "${candidate.headline}"');
                print('    Matching URL: $candidateUrl');
                return candidate;
              }
            }
          }
        }
      }

      print('  No precise match found among candidates');
      return null;
    } catch (e) {
      print('Error finding duplicate task: $e');
      print('Error details: ${e.runtimeType}');
      return null;
    }
  }

  /// Extract URL from HTML link or return plain URL
  static String? _extractUrlFromLink(String linkText) {
    // If it's already a plain URL, return it
    if (linkText.startsWith('http://') || linkText.startsWith('https://')) {
      return linkText;
    }

    // Otherwise, try to extract from HTML format
    final regex = RegExp(r'href=["\x27]([^"\x27]+)["\x27]');
    final match = regex.firstMatch(linkText);
    return match?.group(1);
  }
}
