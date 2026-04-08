import 'package:meaning_to/utils/auth.dart';
import 'package:meaning_to/models/task.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/models/share_invitation.dart';
import 'package:meaning_to/models/share_subscriber.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ApiClient {
  // Temporary: Use Supabase directly for testing
  static SupabaseClient get _supabase => Supabase.instance.client;

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

  /// Search tasks by headline using Postgres ILIKE for case-insensitive partial matching
  /// Returns all tasks where the headline contains the search query (case-insensitive)
  static Future<List<Task>> searchTasksByHeadline(String searchQuery) async {
    try {
      final userId = AuthUtils.getCurrentUserId();

      // Escape special ILIKE characters (% and _) in the user's query
      // These are wildcards in ILIKE, so we need to escape them to treat them as literals
      final escapedQuery = searchQuery
          .replaceAll('\\', '\\\\') // Escape backslashes first
          .replaceAll('%', '\\%') // Escape percent signs
          .replaceAll('_', '\\_'); // Escape underscores

      // Use ILIKE with wildcard pattern for partial matching
      // %query% means "contains query" (case-insensitive)
      final pattern = '%$escapedQuery%';

      final response = await _supabase
          .from('Tasks')
          .select('*')
          .eq('owner_id', userId)
          .ilike('headline', pattern)
          .order('created_at', ascending: false);

      return (response as List)
          .map((taskData) => Task.fromJson(taskData))
          .toList();
    } catch (e) {
      print('Error searching tasks by headline: $e');
      rethrow;
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

  /// Load tasks for a shared category (no owner_id filter — RLS grants access)
  static Future<List<Task>> getTasksByCategory(int categoryId) async {
    try {
      final response = await _supabase
          .from('Tasks')
          .select(
              'id,headline,notes,synopsis,category_id,owner_id,finished,shared,links,original_id,suggestible_at,created_at')
          .eq('category_id', categoryId)
          .order('suggestible_at', ascending: true)
          .order('created_at', ascending: false);

      return (response as List)
          .map((taskData) => Task.fromJson(taskData))
          .toList();
    } catch (e) {
      print('Error getting tasks by category in Supabase: $e');
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
      print('Supabase client initialized: true');

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

      // Fetch shared categories (subscribed by this user but owned by others)
      if (!isGuest) {
        try {
          final sharedRows = await _supabase
              .from('shared_categories')
              .select('category_id, owner_name, available, Categories(*)')
              .eq('user_id', userId);

          final sharedCategories = (sharedRows as List).map((row) {
            final cat = Category.fromJson(
                row['Categories'] as Map<String, dynamic>);
            return cat.copyWithShared(
              isShared: true,
              ownerName: row['owner_name'] as String,
              isAvailable: row['available'] as bool? ?? true,
            );
          }).toList();

          // Interleave: each shared category goes right after its owned counterpart.
          // Walk the owned list; after each owned entry, append any shared
          // entry with the same id. Orphaned shared categories go at the end.
          // Only surface available shared categories on the home screen.
          // Unavailable ones remain in shared_categories (visible in My Shares)
          // but should not appear in the main pursuit list.
          final availableShared =
              sharedCategories.where((c) => c.isAvailable).toList();

          final ownedIds = {for (final c in categories) c.id};
          final result = <Category>[];
          for (final owned in categories) {
            result.add(owned);
            for (final shared in availableShared) {
              if (shared.id == owned.id) result.add(shared);
            }
          }
          for (final shared in availableShared) {
            if (!ownedIds.contains(shared.id)) result.add(shared);
          }
          return result;
        } catch (e) {
          print('Error fetching shared categories: $e');
          // Fall through and return just owned categories
        }
      }

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
          candidates = (response)
              .map((data) => Task.fromJson(data as Map<String, dynamic>))
              .toList();
          print(
              '  ✓ Postgres function returned ${candidates.length} candidate(s)');
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

        if (response.isNotEmpty) {
          candidates = response.map((data) {
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
                final taskUrl =
                    _extractUrlFromLink(taskLink.toString())?.toLowerCase();
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

  // ── Sharing ────────────────────────────────────────────────────────────────

  /// Creates a share invitation for [categoryId] and returns the token UUID.
  /// Enforces a 7-day expiry regardless of the DB function default.
  static Future<String> createShareInvitation(int categoryId) async {
    try {
      // One link per category: remove any existing before creating.
      await _supabase
          .from('share_invitations')
          .delete()
          .eq('category_id', categoryId);
      final response = await _supabase.rpc(
        'create_share_invitation',
        params: {'p_category_id': categoryId},
      );
      final token = response as String;
      // Enforce 7-day expiry.
      await _supabase.from('share_invitations').update({
        'expires_at':
            DateTime.now().add(const Duration(days: 7)).toUtc().toIso8601String(),
      }).eq('id', token);
      return token;
    } catch (e) {
      print('Error creating share invitation: $e');
      rethrow;
    }
  }

  /// Returns all share invitations for [categoryId] created by the current user,
  /// newest first.
  static Future<List<ShareInvitation>> getShareInvitations(
      int categoryId) async {
    try {
      final rows = await _supabase
          .from('share_invitations')
          .select()
          .eq('category_id', categoryId)
          .order('created_at', ascending: false);
      return rows
          .map((r) => ShareInvitation.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error fetching share invitations: $e');
      rethrow;
    }
  }

  /// Extends the expiry of [tokenId] by 7 days from now and clears used_at,
  /// making the link reusable for another recipient.
  static Future<void> renewShareInvitation(String tokenId) async {
    try {
      await _supabase.from('share_invitations').update({
        'expires_at':
            DateTime.now().add(const Duration(days: 7)).toUtc().toIso8601String(),
        'used_at': null,
      }).eq('id', tokenId);
    } catch (e) {
      print('Error renewing share invitation: $e');
      rethrow;
    }
  }

  /// Permanently deletes the share invitation [tokenId].
  static Future<void> deleteShareInvitation(String tokenId) async {
    try {
      await _supabase.from('share_invitations').delete().eq('id', tokenId);
    } catch (e) {
      print('Error deleting share invitation: $e');
      rethrow;
    }
  }

  /// Redeems a share invitation token and returns the subscribed category ID.
  static Future<int> redeemInvitation(String token) async {
    print('[redeemInvitation] calling RPC redeem_invitation, token length=${token.length}');
    try {
      final response = await _supabase.rpc(
        'redeem_invitation',
        params: {'p_token': token},
      );
      print('[redeemInvitation] RPC raw response: $response (type: ${response.runtimeType})');
      return response as int;
    } catch (e, stack) {
      print('[redeemInvitation] ERROR: $e');
      print('[redeemInvitation] Stack: $stack');
      rethrow;
    }
  }

  /// Returns invitation details for a given token, or null if not found.
  /// Uses the get_invitation_info RPC (SECURITY DEFINER) so any authenticated
  /// user can inspect a token regardless of who created the invitation.
  static Future<({int? categoryId, bool openToAll})?>
      getInvitationDetails(String token) async {
    try {
      final rows = await _supabase.rpc(
        'get_invitation_info',
        params: {'p_token': token},
      );
      print('[getInvitationDetails] RPC response: $rows');
      if ((rows as List).isNotEmpty) {
        final row = rows.first as Map<String, dynamic>;
        return (
          categoryId: row['category_id'] as int?,
          openToAll: row['open_to_all'] as bool? ?? false,
        );
      }
      return null;
    } catch (e) {
      print('[getInvitationDetails] ERROR: $e');
      return null;
    }
  }

  /// Removes a shared category subscription for the current user.
  static Future<void> releaseSharedCategory(int categoryId) async {
    try {
      await _supabase
          .from('shared_categories')
          .delete()
          .eq('category_id', categoryId);
    } catch (e) {
      print('Error releasing shared category: $e');
      rethrow;
    }
  }

  /// Returns ALL categories shared with the current user (including unavailable),
  /// for use in My Shares where the full list is needed.
  static Future<List<Category>> getAllSharedWithMe() async {
    final userId = AuthUtils.getCurrentUserId();
    if (userId == null) return [];
    try {
      final rows = await _supabase
          .from('shared_categories')
          .select('category_id, owner_name, available, Categories(*)')
          .eq('user_id', userId);
      return (rows as List).map((row) {
        final cat =
            Category.fromJson(row['Categories'] as Map<String, dynamic>);
        return cat.copyWithShared(
          isShared: true,
          ownerName: row['owner_name'] as String,
          isAvailable: row['available'] as bool? ?? true,
        );
      }).toList();
    } catch (e) {
      print('Error fetching shared-with-me categories: $e');
      return [];
    }
  }

  /// Toggles whether a shared category subscription appears on the home screen.
  static Future<void> setSharedCategoryAvailable(
      int categoryId, bool available) async {
    try {
      final userId = AuthUtils.getCurrentUserId();
      await _supabase
          .from('shared_categories')
          .update({'available': available})
          .eq('category_id', categoryId)
          .eq('user_id', userId);
    } catch (e) {
      print('Error updating shared category availability: $e');
      rethrow;
    }
  }

  // ── Open To All sharing ────────────────────────────────────────────────────

  /// Toggles the open_to_all flag on an invitation.
  /// When enabling, clears expires_at; when disabling, sets a fresh 7-day expiry.
  static Future<void> setInvitationOpenToAll(
      String tokenId, bool openToAll) async {
    try {
      await _supabase.from('share_invitations').update({
        'open_to_all': openToAll,
        'expires_at': openToAll
            ? null
            : DateTime.now()
                .add(const Duration(days: 7))
                .toUtc()
                .toIso8601String(),
      }).eq('id', tokenId);
    } catch (e) {
      print('Error updating open_to_all: $e');
      rethrow;
    }
  }

  /// Returns all subscribers for [categoryId] (owner only).
  static Future<List<ShareSubscriber>> getCategorySubscribers(
      int categoryId) async {
    try {
      final response = await _supabase.rpc(
        'get_category_subscribers',
        params: {'p_category_id': categoryId},
      );
      return (response as List)
          .map((r) => ShareSubscriber.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error getting category subscribers: $e');
      rethrow;
    }
  }

  /// Subscribes the current user to all open-to-all categories owned by
  /// [ownerEmail]. If [available] is true they appear on the home screen
  /// immediately; if false they are hidden in My Shares only.
  /// Returns the number of new subscriptions created.
  static Future<int> redeemSampleShares({bool available = true}) async {
    try {
      final response = await _supabase.rpc(
        'redeem_sample_shares',
        params: {
          'p_owner_email': 'supstill@mac.com',
          'p_available': available,
        },
      );
      return response as int;
    } catch (e) {
      print('Error redeeming sample shares: $e');
      return 0;
    }
  }

  /// Revokes a subscriber's access to [categoryId].
  static Future<void> revokeSubscriber(int categoryId, String userId) async {
    try {
      await _supabase.rpc(
        'revoke_subscriber',
        params: {'p_category_id': categoryId, 'p_user_id': userId},
      );
    } catch (e) {
      print('Error revoking subscriber: $e');
      rethrow;
    }
  }

  /// Returns a summary of categories the current user is sharing out.
  /// Each map has: category_id (int), open_to_all (bool), subscriber_count (int).
  static Future<List<Map<String, dynamic>>> getSharedOutSummary() async {
    try {
      final userId = AuthUtils.getCurrentUserId();
      // Find categories owned by the user that have at least one invitation
      final invRows = await _supabase
          .from('share_invitations')
          .select('category_id, open_to_all')
          .eq('created_by', userId);

      // Group by category_id; prefer open_to_all=true if any row has it
      final Map<int, bool> byCategory = {};
      for (final row in invRows as List) {
        final catId = row['category_id'] as int;
        final isOpen = row['open_to_all'] as bool? ?? false;
        byCategory[catId] = (byCategory[catId] ?? false) || isOpen;
      }

      if (byCategory.isEmpty) return [];

      // Count subscribers per category
      final subRows = await _supabase
          .from('shared_categories')
          .select('category_id')
          .inFilter('category_id', byCategory.keys.toList());

      final Map<int, int> subCounts = {};
      for (final row in subRows as List) {
        final catId = row['category_id'] as int;
        subCounts[catId] = (subCounts[catId] ?? 0) + 1;
      }

      return byCategory.entries.map((e) => {
        'category_id': e.key,
        'open_to_all': e.value,
        'subscriber_count': subCounts[e.key] ?? 0,
      }).toList();
    } catch (e) {
      print('Error getting shared-out summary: $e');
      rethrow;
    }
  }
}
