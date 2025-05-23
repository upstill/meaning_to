import 'dart:convert';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:meaning_to/models/category.dart';
import 'package:meaning_to/utils/link_processor.dart';

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
  List<ProcessedLink>? processedLinks;
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
    this.processedLinks,
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
          // If it's a single HTML link, return it as is
          if (linksData.trim().startsWith('<a href="')) {
            return [linksData];
          }
          // Otherwise try to parse as JSON
          final decoded = jsonDecode(linksData) as List;
          return List<String>.from(decoded);
        } catch (e) {
          print('Error parsing links: $e');
          // If parsing fails, return the string as a single link
          return [linksData];
        }
      }
      return null;
    }

    final links = parseLinks(json['links']);
    print('Parsed links from JSON: $links');
    
    // Get suggestibleAt, defaulting to current time if null
    final suggestibleAt = json['suggestible_at'] != null 
        ? DateTime.parse(json['suggestible_at'] as String)
        : DateTime.now();
    
    // Create the task with the links
    final task = Task(
      id: json['id'] as int,
      categoryId: json['category_id'] as int,
      headline: json['headline'] as String,
      notes: json['notes'] as String?,
      ownerId: json['owner_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      suggestibleAt: suggestibleAt,
      triggersAt: json['triggers_at'] != null 
          ? DateTime.parse(json['triggers_at'] as String)
          : null,
      deferral: json['deferral'] as int?,
      links: links,
      processedLinks: null,  // Will be processed when needed
      finished: json['finished'] as bool,
    );

    // If we had to set suggestibleAt to now, update it in the database
    if (json['suggestible_at'] == null) {
      print('Updating suggestible_at to now for task ${task.headline}');
      supabase
          .from('Tasks')
          .update({'suggestible_at': suggestibleAt.toIso8601String()})
          .eq('id', task.id)
          .eq('owner_id', task.ownerId)
          .then((_) => print('Updated suggestible_at in database'))
          .catchError((e) => print('Error updating suggestible_at: $e'));
    }

    return task;
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
      'links': links != null ? (links!.length == 1 ? links![0] : jsonEncode(links)) : null,
      'finished': finished,
    };
  }

  // Static cache for current context
  static Task? _currentTask;
  static List<Task>? _currentTaskSet;
  static Category? _currentCategory;
  static String? _currentUserId;

  // Getters for the cache
  static Task? get currentTask => _currentTask;
  static List<Task>? get currentTaskSet => _currentTaskSet;
  static Category? get currentCategory => _currentCategory;
  static String? get currentUserId => _currentUserId;

  // Clear the cache
  static void clearCache() {
    _currentTask = null;
    _currentTaskSet = null;
    _currentCategory = null;
    _currentUserId = null;
  }

  /// Updates the current context and fetches tasks for the given category and user.
  /// Returns the task set if successful, null if no tasks are found.
  static Future<List<Task>?> loadTaskSet(Category category, String userId) async {
    try {
      print('Loading task set for category ${category.id} and user $userId');
      
      // Update current context
      _currentCategory = category;
      _currentUserId = userId;
      _currentTask = null;  // Clear current task when changing context
      
      // Query tasks from the database
      final response = await supabase
          .from('Tasks')
          .select()
          .eq('category_id', category.id)
          .eq('owner_id', userId)
          .order('created_at', ascending: false);
      
      print('Task response fields: ${response.isNotEmpty ? response.first.keys.toList() : 'No tasks found'}');

      if (response == null || response.isEmpty) {
        print('No tasks found for category ${category.id}');
        _currentTaskSet = null;
        return null;
      }

      // Convert to Task objects and update cache
      _currentTaskSet = (response as List)
          .map((json) => Task.fromJson(json as Map<String, dynamic>))
          .toList();
      // Sort: unfinished first, then by suggestibleAt ascending
      sortTaskSet(_currentTaskSet!);
      
      print('Loaded ${_currentTaskSet!.length} tasks into cache');

      // Process links for all tasks in the set
      print('Processing links for all tasks in set');
      for (final task in _currentTaskSet!) {
        if (task.links != null && task.links!.isNotEmpty) {
          print('Processing links for task: ${task.headline}');
          await task.ensureLinksProcessed();
        }
      }
      
      return _currentTaskSet;
    } catch (e, stackTrace) {
      print('Error loading task set: $e');
      print('Stack trace: $stackTrace');
      clearCache();  // Clear cache on error
      rethrow;
    }
  }

  /// Fetches a random unfinished task for the given category and user.
  /// Uses cached task set if available and context matches.
  /// Returns null if no tasks are found.
  static Future<Task?> nextTask(Category category, String userId) async {
    try {
      // Check if we need to load a new task set
      if (_currentTaskSet == null || 
          _currentCategory?.id != category.id || 
          _currentUserId != userId) {
        await loadTaskSet(category, userId);
      }

      if (_currentTaskSet == null || _currentTaskSet!.isEmpty) {
        print('No tasks available for category \\${category.id}');
        return null;
      }

      // Count the number of unfinished tasks at the beginning of the sorted list
      int unfinishedCount = 0;
      for (final task in _currentTaskSet!) {
        if (!task.finished && (task.suggestibleAt == null || !task.suggestibleAt!.isAfter(DateTime.now()))) {
          unfinishedCount++;
        } else {
          break;
        }
      }
      if (unfinishedCount == 0) {
        print('No unfinished tasks available for category ${category.id}');
        return null;
      }
      // Select a random unfinished task from the first unfinishedCount tasks
      final random = Random();
      _currentTask = _currentTaskSet![random.nextInt(unfinishedCount)];
      print('Selected random task: \\${_currentTask!.headline}');

      // Process links for the selected task
      print('Processing links for selected task: ${_currentTask!.headline}');
      await _currentTask!.ensureLinksProcessed();
      
      // Update only the suggestible_at field in the database for the selected task
      await supabase
          .from('Tasks')
          .update({'suggestible_at': _currentTask!.suggestibleAt?.toIso8601String()})
          .eq('id', _currentTask!.id)
          .eq('owner_id', _currentTask!.ownerId);
      return _currentTask;
    } catch (e, stackTrace) {
      print('Error loading random task: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Marks the current task as finished in both the database and cache.
  static Future<void> finishCurrentTask() async {
    final currentTask = _currentTask;
    final currentUserId = _currentUserId;
    
    if (currentTask == null || currentUserId == null) {
      print('[finishCurrentTask] No current task or user ID');
      throw Exception('No current task to finish');
    }

    try {
      print('[finishCurrentTask] Attempting to update task id: \\${currentTask.id}, owner_id: \\${currentUserId}');
      // Update in database
      final response = await supabase
          .from('Tasks')
          .update({'finished': true})
          .eq('id', currentTask.id)
          .eq('owner_id', currentUserId);
      print('[finishCurrentTask] Update response: \\${response.toString()}');

      // Update cache
      final updatedTask = Task(
        id: currentTask.id,
        categoryId: currentTask.categoryId,
        headline: currentTask.headline,
        notes: currentTask.notes,
        ownerId: currentTask.ownerId,
        createdAt: currentTask.createdAt,
        suggestibleAt: currentTask.suggestibleAt,
        triggersAt: currentTask.triggersAt,
        deferral: currentTask.deferral,
        links: currentTask.links,
        processedLinks: currentTask.processedLinks,
        finished: true,  // Set to true
      );

      // Update the task in the cache
      if (_currentTaskSet != null) {
        final index = _currentTaskSet!.indexWhere((t) => t.id == currentTask.id);
        if (index != -1) {
          _currentTaskSet![index] = updatedTask;
        }
        // Resort the cache after modification
        sortTaskSet(_currentTaskSet!);
      }
      _currentTask = updatedTask;

      print('[finishCurrentTask] Task marked as finished and cache updated');
    } catch (e, stackTrace) {
      print('[finishCurrentTask] Error finishing task: \\${e.toString()}');
      print('[finishCurrentTask] Stack trace: \\${stackTrace.toString()}');
      rethrow;
    }
  }

  /// Rejects the current task by deferring it to a later time.
  /// If the task has no deferral set, initializes it to 60 minutes.
  /// Doubles the deferral time for next time.
  /// Updates both the database and cache.
  static Future<void> rejectCurrentTask() async {
    final currentTask = _currentTask;
    final currentUserId = _currentUserId;
    
    print("Rejecting task ${currentTask?.headline}");
    if (currentTask == null || currentUserId == null) {
      throw Exception('No current task to reject');
    }

    try {
      // Calculate new deferral time (default to 60 minutes if not set)
      final currentDeferral = currentTask.deferral ?? 60;
      final newDeferral = currentDeferral * 2;
      
      // Calculate new suggestible time
      final now = DateTime.now();
      final newSuggestibleAt = now.add(Duration(minutes: currentDeferral));

      // Update in database
      await supabase
          .from('Tasks')
          .update({
            'suggestible_at': newSuggestibleAt.toIso8601String(),
            'deferral': newDeferral,
          })
          .eq('id', currentTask.id)
          .eq('owner_id', currentUserId);

      // Update cache
      final updatedTask = Task(
        id: currentTask.id,
        categoryId: currentTask.categoryId,
        headline: currentTask.headline,
        notes: currentTask.notes,
        ownerId: currentTask.ownerId,
        createdAt: currentTask.createdAt,
        suggestibleAt: newSuggestibleAt,
        triggersAt: currentTask.triggersAt,
        deferral: newDeferral,
        links: currentTask.links,
        processedLinks: currentTask.processedLinks,
        finished: currentTask.finished,
      );

      // Update the task in the cache
      if (_currentTaskSet != null) {
        final index = _currentTaskSet!.indexWhere((t) => t.id == currentTask.id);
        if (index != -1) {
        print("Updating task \\${updatedTask.headline} in cache");
          _currentTaskSet![index] = updatedTask;
        }
        // Resort the cache after modification
        sortTaskSet(_currentTaskSet!);
      }
      _currentTask = updatedTask;

      print('Task deferred to ${newSuggestibleAt.toLocal()} with new deferral of $newDeferral minutes');
    } catch (e, stackTrace) {
      print('Error rejecting task: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  static Future<Task?> loadRandomTask(Category category, String userId) async {
    try {
      print('Before nextTask:');
      print('Current task: ${currentTask?.headline}');
      print('Task set size: ${currentTaskSet?.length}');
      print('Current category: ${currentCategory?.headline}');
      print('Current user: $currentUserId');

      final task = await nextTask(category, userId);
      
      print('After nextTask:');
      print('Current task: ${currentTask?.headline}');
      print('Task set size: ${currentTaskSet?.length}');
      print('Current category: ${currentCategory?.headline}');
      print('Current user: $currentUserId');
      
      return task;
    } catch (e, stackTrace) {
      print('Error loading random task: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Sorts a list of tasks: unfinished first, then by suggestibleAt ascending
  static void sortTaskSet(List<Task> tasks) {
    tasks.sort((a, b) {
      // 1. Unfinished (false) first
      if (a.finished != b.finished) {
        return a.finished ? 1 : -1;
      }
      // 2. Ascending suggestibleAt (nulls last)
      if (a.suggestibleAt == null && b.suggestibleAt == null) return 0;
      if (a.suggestibleAt == null) return 1;
      if (b.suggestibleAt == null) return -1;
      return a.suggestibleAt!.compareTo(b.suggestibleAt!);
    });
    // Print a report of the sorted tasks
    print('[sortTaskSet] Sorted task cache:');
    for (final t in tasks) {
      final minutes = t.suggestibleAt != null
          ? t.suggestibleAt!.difference(DateTime.now()).inMinutes
          : 'n/a';
      print('  headline: "${t.headline}", finished: ${t.finished}, suggestible in $minutes minutes');
    }
  }

  // Utility: Convert a string to a List<String> of URLs
  static List<String> parseLinks(String? linksString) {
    if (linksString == null || linksString.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(linksString);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (e) {
      // Fallback: try splitting by comma
      return linksString.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    return [];
  }

  // Utility: Convert a List<String> of URLs to a string for storage
  static String? linksToString(List<String>? links) {
    if (links == null || links.isEmpty) return null;
    return jsonEncode(links);
  }

  /// Returns a formatted string showing when the task will be available again.
  /// Returns null if the task is not deferred (suggestibleAt is null) or if the suggestible time is in the past.
  /// Time is expressed in the most appropriate unit:
  /// - Less than a minute: seconds
  /// - Less than an hour: minutes (and seconds if less than 5 minutes)
  /// - Less than a day: hours and minutes
  /// - Otherwise: days and hours
  String? getSuggestibleTimeDisplay() {
    if (suggestibleAt == null) return null;
    if (!suggestibleAt!.isAfter(DateTime.now())) return null;
    
    final difference = suggestibleAt!.difference(DateTime.now());
    final seconds = difference.inSeconds;
    final minutes = difference.inMinutes;
    final hours = difference.inHours;
    final days = difference.inDays;

    // Get the remainder for the next smaller unit
    final remainingSeconds = seconds % 60;
    final remainingMinutes = minutes % 60;
    final remainingHours = hours % 24;
    final preface = "Deferred for";

    if (seconds < 60) {
      return '$preface $seconds second${seconds == 1 ? '' : 's'}';
    } else if (minutes < 60) {
      if (minutes < 5) {
        // For times less than 5 minutes, show seconds too
        return '$preface $minutes minute${minutes == 1 ? '' : 's'} and $remainingSeconds second${remainingSeconds == 1 ? '' : 's'}';
      }
      return '$preface $minutes minute${minutes == 1 ? '' : 's'}';
    } else if (hours < 24) {
      return '$preface $hours hour${hours == 1 ? '' : 's'} and $remainingMinutes minute${remainingMinutes == 1 ? '' : 's'}';
    } else {
      return '$preface $days day${days == 1 ? '' : 's'} and $remainingHours hour${remainingHours == 1 ? '' : 's'}';
    }
  }

  // Update ensureLinksProcessed to only handle display processing
  Future<void> ensureLinksProcessed() async {
    // If links are already processed or there are no links, return immediately
    if (links == null || (processedLinks != null && processedLinks!.length == links!.length)) {
      return;
    }

    print('Processing links for display: $headline');
    print('Raw URLs: $links');
    
    // Process links for display only
    final processed = await LinkProcessor.processLinksForDisplay(links!);
    processedLinks = processed;
    
    print('Processed links for display: ${processed.map((p) => p.originalLink).toList()}');
  }

  // Add a method to validate links before saving
  static List<String> validateLinks(List<String> links) {
    return links.where((link) => LinkProcessor.isValidUrl(link)).toList();
  }

  /// Revives a task by setting its suggestibleAt time to now.
  /// Updates both the database and cache.
  static Future<void> reviveTask(Task task, String userId) async {
    try {
      final now = DateTime.now();
      
      // Update in database
      await supabase
          .from('Tasks')
          .update({'suggestible_at': now.toIso8601String()})
          .eq('id', task.id)
          .eq('owner_id', userId);

      // Update cache
      final updatedTask = Task(
        id: task.id,
        categoryId: task.categoryId,
        headline: task.headline,
        notes: task.notes,
        ownerId: task.ownerId,
        createdAt: task.createdAt,
        suggestibleAt: now,  // Set to current time
        triggersAt: task.triggersAt,
        deferral: task.deferral,
        links: task.links,
        processedLinks: task.processedLinks,
        finished: task.finished,
      );

      // Update the task in the cache
      if (_currentTaskSet != null) {
        final index = _currentTaskSet!.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          _currentTaskSet![index] = updatedTask;
        }
        // Resort the cache after modification
        sortTaskSet(_currentTaskSet!);
      }
      if (_currentTask?.id == task.id) {
        _currentTask = updatedTask;
      }

      print('Task ${task.headline} revived at ${now.toLocal()}');
    } catch (e, stackTrace) {
      print('Error reviving task: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }
} 